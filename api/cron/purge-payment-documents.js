import { createClient } from '@supabase/supabase-js';
import { getMissingEmailVariables, sendWithGmail } from '../_lib/email.js';
import { renderEmail, renderEmailText, escapeHtml } from '../_lib/emailTemplate.js';

// Two jobs in one daily run (migration 057 added the 7d/1d reminder
// columns this needs) — reminders always run before the purge sweep, so a
// row that crosses BOTH its 1-day threshold and purge_after on the exact
// same run still gets warned first:
//
//  1. Advance-warning reminders for any payment_documents row nearing its
//     purge_after — live (Task 1's 12-month, event-anchored window) or
//     superseded (056's 24h replacement window) — at 7 days and 1 day out,
//     each sent at most once (reminder_7d_sent_at/reminder_1d_sent_at).
//     A superseded row's 24h window is never more than a day out, so it
//     only ever gets the 1-day reminder, never a misleading "7 days" one —
//     see the two queries below, they're mutually exclusive by construction
//     (the 7d query explicitly excludes anything already inside 1 day).
//  2. The purge itself: hard-deletes (not soft) rows (and their storage
//     object) past purge_after.
//
// Runs daily (vercel.json), same cadence as escalate-verifications.js —
// this project is on Vercel's Hobby plan, which only permits daily (not
// hourly) cron schedules and caps the project at 2 cron jobs total (both
// already spoken for by this pair), which is also why this is one job
// with two phases rather than two separate crons.

function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
    || 'https://ukchdgdnwytretvqjjqu.supabase.co';
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

function t(locale, vi, en) {
  return locale === 'en' ? en : vi;
}

async function emailFor(admin, userId) {
  const { data: auth } = await admin.auth.admin.getUserById(userId);
  if (!auth?.user?.email) return null;
  const { data: profile } = await admin.from('profiles').select('locale').eq('id', userId).maybeSingle();
  return { email: auth.user.email, locale: profile?.locale === 'en' ? 'en' : 'vi' };
}

async function downloadLink(admin, filePath, expiresInSeconds) {
  if (!filePath) return null;
  const { data, error } = await admin.storage.from('payment-documents').createSignedUrl(filePath, expiresInSeconds);
  if (error) {
    console.warn('purge-payment-documents: signed URL failed', filePath, error.message);
    return null;
  }
  return data?.signedUrl || null;
}

// Sends one reminder to every real recipient (participant + organizer's
// owner/user, whichever have emails) for one document row. `urgent`
// switches the copy between the 7-day and 1-day wording; the download
// link's expiry is set comfortably past the threshold it's warning about
// (10 days for the 7-day notice, 2 days for the 1-day notice) so the link
// itself doesn't die before the deadline it's warning the reader about.
async function sendReminder(admin, row, { urgent }) {
  const kindLabelVi = row.kind === 'invoice' ? 'hoá đơn' : 'biên nhận';
  const kindLabelEn = row.kind === 'invoice' ? 'invoice' : 'receipt';
  const daysLeft = urgent ? 1 : 7;
  const link = await downloadLink(admin, row.file_path, urgent ? 60 * 60 * 24 * 2 : 60 * 60 * 24 * 10);

  const recipientIds = new Set();
  if (row.user_id) recipientIds.add(row.user_id);
  if (row.organizer_owner_id) recipientIds.add(row.organizer_owner_id);
  if (row.organizer_user_id) recipientIds.add(row.organizer_user_id);

  let sent = 0;
  for (const uid of recipientIds) {
    const recipient = await emailFor(admin, uid);
    if (!recipient) continue;
    const { locale } = recipient;
    const subject = urgent
      ? t(locale, `Sẽ bị xoá trong 1 ngày ▪︎ ${kindLabelVi}`, `Deleted in 1 day ▪︎ ${kindLabelEn}`)
      : t(locale, `Sẽ bị xoá sau 7 ngày ▪︎ ${kindLabelVi}`, `Deleted in 7 days ▪︎ ${kindLabelEn}`);
    const heading = urgent
      ? t(locale, `${kindLabelVi[0].toUpperCase()}${kindLabelVi.slice(1)} sẽ bị xoá vĩnh viễn vào ngày mai`, `Your ${kindLabelEn} is deleted permanently tomorrow`)
      : t(locale, `${kindLabelVi[0].toUpperCase()}${kindLabelVi.slice(1)} sẽ bị xoá vĩnh viễn sau 7 ngày`, `Your ${kindLabelEn} is deleted permanently in 7 days`);
    const paragraphs = [
      t(locale,
        `Một ${kindLabelVi} (số ${escapeHtml(row.number)}) sẽ bị xoá vĩnh viễn khỏi banbe trong ${daysLeft} ngày tới.`,
        `A ${kindLabelEn} (No. ${escapeHtml(row.number)}) will be permanently deleted from banbe in the next ${daysLeft} day${daysLeft === 1 ? '' : 's'}.`),
      t(locale,
        'Hãy tải về ngay nếu bạn cần giữ lại bản này — sau khi xoá, banbe không thể khôi phục.',
        'Download it now if you need to keep a copy — once deleted, banbe cannot recover it.'),
    ];
    try {
      await sendWithGmail({
        to: recipient.email,
        subject,
        text: renderEmailText({ heading, paragraphs, cta: link ? { label: t(locale, 'Tải về', 'Download'), href: link } : undefined }),
        html: renderEmail({
          preheader: subject,
          eyebrow: t(locale, 'Chứng từ thanh toán', 'Payment document'),
          heading, paragraphs,
          cta: link ? { label: t(locale, 'Tải về', 'Download'), href: link } : undefined,
        }),
      });
      sent += 1;
    } catch (e) {
      console.warn('purge-payment-documents: reminder email failed', uid, e?.message);
    }

    await admin.from('notifications').insert({
      recipient_id: uid,
      kind: urgent ? 'payment_document_expiring_1d' : 'payment_document_expiring_7d',
      title: urgent
        ? t(locale, 'Sẽ bị xoá trong 1 ngày', 'Deleted in 1 day')
        : t(locale, 'Sẽ bị xoá sau 7 ngày', 'Deleted in 7 days'),
      body: t(locale,
        `${kindLabelVi[0].toUpperCase()}${kindLabelVi.slice(1)} số ${row.number} sẽ bị xoá vĩnh viễn trong ${daysLeft} ngày.`,
        `Your ${kindLabelEn} No. ${row.number} will be permanently deleted in ${daysLeft} day${daysLeft === 1 ? '' : 's'}.`),
      data: { document_id: row.id, booking_id: row.booking_id, kind: row.kind, purge_after: row.purge_after },
    });
  }
  return sent;
}

export default async function handler(req, res) {
  // Same signed-invocation check as escalate-verifications.js — without it
  // this is a free "delete anyone's receipts early" button.
  const secret = process.env.CRON_SECRET;
  const auth = req.headers.authorization || '';
  if (secret && auth !== `Bearer ${secret}`) {
    return res.status(401).json({ error: 'UNAUTHORIZED' });
  }

  const admin = getSupabaseAdmin();
  if (!admin) return res.status(503).json({ error: 'SUPABASE_SERVICE_ROLE_KEY_NOT_SET' });

  const emailReady = getMissingEmailVariables().length === 0;
  const now = new Date();
  const in1Day = new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString();
  const in7Days = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000).toISOString();

  const selectWithOrganizer = 'id, booking_id, kind, number, file_path, user_id, organizer_id, purge_after, ' +
    'organizers ( owner_id, user_id )';

  let reminded7d = 0;
  let reminded1d = 0;

  if (emailReady) {
    // 1-day: due first (and takes priority over 7-day — see header comment).
    const { data: urgent, error: urgentError } = await admin
      .from('payment_documents')
      .select(selectWithOrganizer)
      .not('purge_after', 'is', null)
      .lte('purge_after', in1Day)
      .is('reminder_1d_sent_at', null)
      .limit(200);
    if (urgentError) console.warn('purge-payment-documents: 1d query failed', urgentError.message);
    for (const row of urgent || []) {
      const flat = { ...row, organizer_owner_id: row.organizers?.owner_id, organizer_user_id: row.organizers?.user_id };
      const sent = await sendReminder(admin, flat, { urgent: true });
      if (sent > 0) reminded1d += 1;
      await admin.from('payment_documents').update({ reminder_1d_sent_at: now.toISOString() }).eq('id', row.id);
    }

    // 7-day: explicitly excludes anything already inside the 1-day window,
    // so a superseded row's 24h purge_after never gets this one at all.
    const { data: due7d, error: due7dError } = await admin
      .from('payment_documents')
      .select(selectWithOrganizer)
      .not('purge_after', 'is', null)
      .lte('purge_after', in7Days)
      .gt('purge_after', in1Day)
      .is('reminder_7d_sent_at', null)
      .limit(200);
    if (due7dError) console.warn('purge-payment-documents: 7d query failed', due7dError.message);
    for (const row of due7d || []) {
      const flat = { ...row, organizer_owner_id: row.organizers?.owner_id, organizer_user_id: row.organizers?.user_id };
      const sent = await sendReminder(admin, flat, { urgent: false });
      if (sent > 0) reminded7d += 1;
      await admin.from('payment_documents').update({ reminder_7d_sent_at: now.toISOString() }).eq('id', row.id);
    }
  } else {
    console.warn('purge-payment-documents: email not configured, skipping reminders this run');
  }

  const { data: due, error } = await admin
    .from('payment_documents')
    .select('id, file_path')
    .not('purge_after', 'is', null)
    .lte('purge_after', now.toISOString())
    .limit(200);

  if (error) {
    console.warn('purge-payment-documents: read failed', error.message);
    return res.status(500).json({ error: 'QUEUE_READ_FAILED', reminded7d, reminded1d });
  }

  let purged = 0;
  const failures = [];

  for (const row of due || []) {
    try {
      if (row.file_path) {
        const { error: storageError } = await admin.storage.from('payment-documents').remove([row.file_path]);
        // Not fatal — an already-missing object (a retry after a partial
        // prior run) shouldn't block deleting the row itself.
        if (storageError) console.warn('purge-payment-documents: storage remove failed', row.id, storageError.message);
      }
      const { error: deleteError } = await admin.from('payment_documents').delete().eq('id', row.id);
      if (deleteError) throw deleteError;
      purged += 1;
    } catch (e) {
      failures.push({ id: row.id, error: e?.message });
    }
  }

  return res.status(200).json({ ok: true, purged, failures, reminded7d, reminded1d });
}
