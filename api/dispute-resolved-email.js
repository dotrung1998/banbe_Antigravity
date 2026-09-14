import { createClient } from '@supabase/supabase-js';
import { getMissingEmailVariables, sendWithGmail } from './_lib/email.js';
import { renderEmail, renderEmailText, escapeHtml } from './_lib/emailTemplate.js';
import { renderDisputeTranscript } from '../src/lib/disputeTranscript.js';

// The final step of resolving a dispute: a confirmation email to BOTH the
// guest and the organizer, summarizing the agreement, with the dispute
// chat's transcript (rendered to PDF) and the original receipt image
// attached — the only record of either that survives once
// purge_resolved_dispute_threads() deletes the temporary chat's rows.
//
// Called by the admin's browser right after resolve_dispute() (the DB RPC)
// succeeds — resolve_dispute() only flips database state and leaves a note
// in the ordinary thread; this is the one place that actually sends mail,
// same separation of concerns every other notify-*.js endpoint here uses.
//
// Admin-only: mirrors resolve_dispute()'s own authorization exactly, since
// this is the second half of the same action.

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) return null;
  return createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
}

// puppeteer-core + @sparticuz/chromium — the standard combo for rendering
// arbitrary HTML to PDF inside a size-constrained serverless function
// (a full Puppeteer + bundled Chromium install is far past Vercel's
// deployment size limit; this pair trims Chromium specifically for that).
async function htmlToPdf(html) {
  const chromium = (await import('@sparticuz/chromium')).default;
  const puppeteer = await import('puppeteer-core');
  const browser = await puppeteer.launch({
    args: chromium.args,
    executablePath: await chromium.executablePath(),
    headless: true,
  });
  try {
    const page = await browser.newPage();
    await page.setContent(html, { waitUntil: 'networkidle0' });
    return await page.pdf({ format: 'A4', printBackground: true });
  } finally {
    await browser.close();
  }
}

function t(locale, vi, en) {
  return locale === 'en' ? en : vi;
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }

  const admin = getSupabaseAdmin();
  const missing = [...getMissingEmailVariables(), !admin && 'SUPABASE_SERVICE_ROLE_KEY'].filter(Boolean);
  if (missing.length) return res.status(503).json({ error: 'EMAIL_SERVICE_NOT_CONFIGURED', missing });

  const token = getText((req.headers.authorization || '').replace(/^Bearer\s+/i, ''));
  if (!token) return res.status(401).json({ error: 'AUTH_REQUIRED' });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData?.user) return res.status(401).json({ error: 'AUTH_REQUIRED' });

  const { data: caller } = await admin.from('profiles').select('role').eq('id', userData.user.id).maybeSingle();
  if (caller?.role !== 'admin') return res.status(403).json({ error: 'ADMIN_ONLY' });

  const bookingId = getText((req.body || {}).bookingId);
  if (!bookingId) return res.status(400).json({ error: 'VALID_BOOKING_REQUIRED' });

  try {
    const { data: booking, error: bookingError } = await admin
      .from('bookings')
      .select('id, event_id, user_id, payment_ref, proof_path')
      .eq('id', bookingId).maybeSingle();
    if (bookingError) throw bookingError;
    if (!booking) return res.status(404).json({ error: 'BOOKING_NOT_FOUND' });

    const { data: thread, error: threadError } = await admin
      .from('dispute_threads')
      .select('id, organizer_id, resolved_at, resolution_kind, resolution_note')
      .eq('booking_id', bookingId).maybeSingle();
    if (threadError) throw threadError;
    if (!thread || !thread.resolved_at) return res.status(409).json({ error: 'NOT_RESOLVED' });

    const { data: event } = await admin.from('events').select('name').eq('id', booking.event_id).maybeSingle();
    const { data: organizer } = await admin
      .from('organizers').select('name, owner_id, user_id').eq('id', thread.organizer_id).maybeSingle();
    const { data: guestProfile } = await admin
      .from('profiles').select('display_name, locale').eq('id', booking.user_id).maybeSingle();
    // Previously only `data` was destructured from both getUserById calls —
    // a failed lookup (a deleted account, a bad service-role key, a
    // transient auth-admin API error) silently resolved to an undefined
    // email address with no log at all, rather than surfacing as the
    // resolvable problem it is.
    const { data: guestAuth, error: guestAuthError } = await admin.auth.admin.getUserById(booking.user_id);
    if (guestAuthError) console.error('dispute-resolved-email: guest auth lookup failed:', guestAuthError);
    const organizerUserId = organizer?.owner_id || organizer?.user_id;
    let organizerAuth = null;
    if (organizerUserId) {
      const result = await admin.auth.admin.getUserById(organizerUserId);
      if (result.error) console.error('dispute-resolved-email: organizer auth lookup failed:', result.error);
      organizerAuth = result.data;
    } else {
      console.warn('dispute-resolved-email: organizer has no owner_id/user_id, cannot resolve an email', thread.organizer_id);
    }

    const { data: messages } = await admin
      .from('dispute_messages')
      .select('sender_role, body, created_at')
      .eq('dispute_thread_id', thread.id)
      .order('created_at', { ascending: true });

    const transcriptHtml = renderDisputeTranscript({
      eventName: event?.name || 'Event',
      guestName: guestProfile?.display_name || guestAuth?.user?.email || 'Guest',
      organizerName: organizer?.name || 'Organizer',
      paymentRef: booking.payment_ref || '',
      resolutionKind: thread.resolution_kind,
      resolutionNote: thread.resolution_note,
      resolvedAt: thread.resolved_at,
    }, messages || []);

    // Previously unguarded and sitting directly in the same try block as
    // everything else in this handler — a puppeteer-core/@sparticuz/chromium
    // failure here (a genuinely common serverless failure mode: binary size,
    // missing/incompatible memory allocation, a cold-start timeout — this
    // path has never been exercised against a live Vercel deployment, per
    // this file's own header) threw straight past the send loop entirely,
    // into the outer catch (bottom of this handler), aborting BOTH
    // recipients' emails before either was ever attempted and reporting
    // only the generic SEND_FAILED — indistinguishable, from the client, from
    // an actual Gmail-send failure. Isolated here so a PDF failure costs the
    // transcript attachment, not the whole email to both parties.
    const attachments = [];
    try {
      const transcriptPdf = await htmlToPdf(transcriptHtml);
      attachments.push({ filename: 'dispute-transcript.pdf', content: transcriptPdf, contentType: 'application/pdf' });
    } catch (pdfError) {
      console.error('dispute-resolved-email: PDF generation failed, sending without the transcript attachment:', pdfError);
    }

    if (booking.proof_path) {
      const { data: proofBlob, error: proofError } = await admin.storage.from('pay-proof').download(booking.proof_path);
      if (proofError) console.error('dispute-resolved-email: receipt image download failed:', proofError);
      if (proofBlob) {
        attachments.push({
          filename: 'receipt' + (booking.proof_path.includes('.') ? booking.proof_path.slice(booking.proof_path.lastIndexOf('.')) : '.jpg'),
          content: Buffer.from(await proofBlob.arrayBuffer()),
        });
      }
    }

    const resolutionSummaryVi = thread.resolution_kind === 'ticket_issued'
      ? 'Vé đã được cấp cho khách.' : 'Đặt chỗ đã được huỷ và chỗ đã được mở lại.';
    const resolutionSummaryEn = thread.resolution_kind === 'ticket_issued'
      ? 'A ticket has been issued to the guest.' : 'The booking has been cancelled and the seat released.';
    const eventName = escapeHtml(event?.name || '');

    // Two independently-tracked outcomes, not one shared try/catch around
    // both sends: previously, if the guest's send threw, the organizer's
    // was never even attempted (the whole handler's outer catch aborted
    // everything) — a transient failure on one address silently cost the
    // other party their email too, with nothing distinguishing that from
    // total success in what the client saw.
    const recipients = [
      { role: 'guest', email: guestAuth?.user?.email, locale: guestProfile?.locale === 'en' ? 'en' : 'vi' },
      { role: 'organizer', email: organizerAuth?.user?.email, locale: 'vi' },
    ];
    let sent = 0;
    const failures = [];
    for (const recipient of recipients) {
      if (!recipient.email) {
        failures.push(`${recipient.role}:NO_EMAIL`);
        continue;
      }
      const subject = t(recipient.locale, `Kết quả tranh chấp thanh toán ▪︎ ${event?.name || ''}`, `Payment dispute resolved ▪︎ ${event?.name || ''}`);
      const heading = t(recipient.locale, 'Tranh chấp đã được giải quyết', 'Dispute resolved');
      const paragraphs = [
        t(recipient.locale, `Đối với <strong>${eventName}</strong>: ${resolutionSummaryVi}`, `For <strong>${eventName}</strong>: ${resolutionSummaryEn}`),
        t(recipient.locale,
          'Toàn bộ nội dung trao đổi trong lúc xem xét được đính kèm dưới dạng PDF cùng email này để lưu trữ.',
          'The full conversation from the review is attached as a PDF with this email, for your records.'),
      ];
      if (thread.resolution_note) {
        paragraphs.push(`<em>${escapeHtml(thread.resolution_note)}</em>`);
      }
      try {
        await sendWithGmail({
          to: recipient.email,
          subject,
          text: renderEmailText({ heading, paragraphs }),
          html: renderEmail({ preheader: subject, eyebrow: t(recipient.locale, 'banbe ▪︎ Tranh chấp', 'banbe ▪︎ Dispute'), heading, paragraphs }),
          attachments,
        });
        sent += 1;
      } catch (sendError) {
        console.error(`dispute-resolved-email: send to ${recipient.role} failed:`, sendError);
        failures.push(`${recipient.role}:${sendError.message || 'SEND_FAILED'}`);
      }
    }

    if (sent > 0) {
      await admin.from('dispute_threads').update({ email_sent_at: new Date().toISOString() }).eq('id', thread.id);
    }

    // The one place that gets to claim an email actually went out — moved
    // here from resolve_dispute() (migration 045), which posted this
    // unconditionally and synchronously, before this send was even
    // attempted. This message now reflects what really happened: full
    // success, partial (named), or — if this branch is never reached
    // because `sent === 0` below returns first — no message at all rather
    // than a false claim.
    if (sent > 0) {
      const { data: eventThread } = await admin
        .from('threads').select('id')
        .eq('event_id', booking.event_id).eq('guest_id', booking.user_id).maybeSingle();
      if (eventThread) {
        const body = failures.length === 0
          ? 'Email xác nhận đã được gửi cho cả hai bên. / Confirmation email sent to both parties.'
          : `Email xác nhận đã được gửi cho ${sent === 1 ? 'một bên' : 'cả hai bên'} (${failures.join(', ')} không nhận được).`
            + ` / Confirmation email sent to ${sent === 1 ? 'one party' : 'both parties'} (${failures.join(', ')} did not receive it).`;
        await admin.from('messages').insert({ thread_id: eventThread.id, sender_id: null, body, kind: 'system' });
      }
    }

    // Zero successful sends is not success — previously returned 200 here
    // regardless, which the client's `!res.ok` check reads as "nothing to
    // report," so a fully-silent failure (e.g. both recipients' emails
    // failing to resolve at all) surfaced no error anywhere at all.
    if (sent === 0) {
      console.error('dispute-resolved-email: no recipient received an email', { bookingId, failures });
      return res.status(502).json({ error: 'NO_EMAIL_DELIVERED', failures });
    }

    return res.status(200).json({ sent, failures });
  } catch (error) {
    console.error('dispute-resolved-email failed:', error);
    return res.status(502).json({ error: 'SEND_FAILED' });
  }
}
