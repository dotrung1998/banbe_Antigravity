import { createClient } from '@supabase/supabase-js';
import { getMissingEmailVariables, sendWithGmail } from './_lib/email.js';
import { getRedirectUrl } from './_lib/authLookup.js';
import { renderEmail, renderEmailText, escapeHtml } from './_lib/emailTemplate.js';

// Consolidated dispatcher for every /api/notify-* endpoint the Hobby-plan
// serverless function cap forced together (max 12 functions per deployment;
// see api/auth/index.js for the same treatment of the /api/auth/* trio).
// Each branch below is the original standalone file's handler body,
// unchanged except for being a function instead of the default export —
// dispatch is purely `body.type`, resolved once auth/config are checked.

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) return null;

  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function t(locale, vi, en) {
  return locale === 'en' ? en : vi;
}

// ---- was api/notify-booking-cancelled.js ----
async function handleBookingCancelled(req, res, admin, userData, body) {
  const bookingId = getText(body.bookingId);
  const reason = getText(body.reason).slice(0, 200);
  if (!bookingId) return res.status(400).json({ error: 'VALID_BOOKING_REQUIRED' });

  try {
    const { data: booking, error: bookingError } = await admin
      .from('bookings')
      .select('id, event_id, user_id, status, paid_marked_at')
      .eq('id', bookingId)
      .maybeSingle();
    if (bookingError) throw bookingError;
    if (!booking || booking.status !== 'cancelled' || !booking.user_id || booking.user_id === userData.user.id) {
      return res.status(200).json({ sent: 0 });
    }

    const { data: event, error: eventError } = await admin
      .from('events')
      .select('id, name, organizer_id')
      .eq('id', booking.event_id)
      .maybeSingle();
    if (eventError) throw eventError;
    if (!event) return res.status(200).json({ sent: 0 });

    const { data: organizer, error: organizerError } = await admin
      .from('organizers')
      .select('owner_id, user_id')
      .eq('id', event.organizer_id)
      .maybeSingle();
    if (organizerError) throw organizerError;

    const isOwner = organizer && (organizer.owner_id === userData.user.id || organizer.user_id === userData.user.id);
    if (!isOwner) return res.status(403).json({ error: 'NOT_AUTHORIZED' });

    const { data: guest, error: guestError } = await admin.auth.admin.getUserById(booking.user_id);
    if (guestError || !guest?.user?.email) return res.status(200).json({ sent: 0 });

    const { data: guestProfile } = await admin.from('profiles').select('locale').eq('id', booking.user_id).maybeSingle();
    const locale = guestProfile?.locale === 'en' ? 'en' : 'vi';

    const eventNameRaw = event.name || t(locale, 'sự kiện', 'this event');
    const eventName = escapeHtml(eventNameRaw);
    const reasonSafe = reason ? escapeHtml(reason) : '';

    const subject = t(locale, `Vé của bạn đã bị huỷ ▪︎ ${eventNameRaw}`, `Your ticket was cancelled ▪︎ ${eventNameRaw}`);
    const heading = t(locale, 'Vé của bạn đã bị huỷ', 'Your ticket was cancelled');
    const paragraphs = [
      t(
        locale,
        `<strong>${eventName}</strong> đã huỷ vé của bạn trên banbe.`,
        `<strong>${eventName}</strong> cancelled your booking on banbe.`
      ),
    ];
    if (booking.paid_marked_at) {
      paragraphs.push(t(
        locale,
        'Khoản bạn đã thanh toán sẽ được hoàn lại.',
        "The payment you made will be refunded."
      ));
    }
    if (reasonSafe) {
      paragraphs.push(t(locale, `Lý do: ${reasonSafe}`, `Reason: ${reasonSafe}`));
    }

    await sendWithGmail({
      to: guest.user.email,
      subject,
      text: renderEmailText({ heading, paragraphs }),
      html: renderEmail({ preheader: subject, eyebrow: t(locale, 'Vé đã huỷ', 'Booking cancelled'), heading, paragraphs }),
    });
    return res.status(200).json({ sent: 1 });
  } catch (error) {
    console.error('Booking-cancelled notification failed:', error);
    return res.status(502).json({ error: 'NOTIFY_FAILED' });
  }
}

// ---- was api/notify-check-in.js ----
async function handleCheckIn(req, res, admin, userData, body) {
  const bookingId = getText(body.bookingId);
  if (!bookingId) return res.status(400).json({ error: 'VALID_BOOKING_REQUIRED' });

  try {
    const { data: booking, error: bookingError } = await admin
      .from('bookings')
      .select('id, event_id, user_id, status')
      .eq('id', bookingId)
      .maybeSingle();
    if (bookingError) throw bookingError;
    if (!booking || booking.status !== 'attended' || !booking.user_id) {
      return res.status(200).json({ sent: 0 });
    }

    const { data: event, error: eventError } = await admin
      .from('events')
      .select('id, name, organizer_id')
      .eq('id', booking.event_id)
      .maybeSingle();
    if (eventError) throw eventError;
    if (!event) return res.status(200).json({ sent: 0 });

    const { data: organizer, error: organizerError } = await admin
      .from('organizers')
      .select('owner_id, user_id')
      .eq('id', event.organizer_id)
      .maybeSingle();
    if (organizerError) throw organizerError;

    const isOwner = organizer && (organizer.owner_id === userData.user.id || organizer.user_id === userData.user.id);
    if (!isOwner) return res.status(403).json({ error: 'NOT_AUTHORIZED' });

    const { data: guest, error: guestError } = await admin.auth.admin.getUserById(booking.user_id);
    if (guestError || !guest?.user?.email) return res.status(200).json({ sent: 0 });

    const { data: guestProfile } = await admin
      .from('profiles')
      .select('locale, referral_code')
      .eq('id', booking.user_id)
      .maybeSingle();
    const locale = guestProfile?.locale === 'en' ? 'en' : 'vi';

    const eventNameRaw = event.name || t(locale, 'sự kiện', 'this event');
    const eventName = escapeHtml(eventNameRaw);
    const subject = t(locale, `Bạn đã có mặt ▪︎ ${eventNameRaw}`, `You're checked in ▪︎ ${eventNameRaw}`);
    const heading = t(locale, 'Bạn đã có mặt!', "You're checked in!");
    const paragraphs = [
      t(
        locale,
        `Bạn vừa được điểm danh tại <strong>${eventName}</strong> trên banbe. Chúc bạn một buổi thật vui!`,
        `You've just been checked in at <strong>${eventName}</strong> on banbe. Have a great time!`
      ),
    ];
    if (guestProfile?.referral_code) {
      const referralLink = `${getRedirectUrl(req)}/?ref=${guestProfile.referral_code}`;
      const referralLinkLabel = escapeHtml(referralLink.replace(/^https?:\/\//, ''));
      paragraphs.push(t(
        locale,
        `Muốn rủ thêm bạn bè cho buổi sau? Chia sẻ banbe qua liên kết riêng của bạn: <a href="${referralLink}">${referralLinkLabel}</a>`,
        `Want to bring friends next time? Share banbe with your own link: <a href="${referralLink}">${referralLinkLabel}</a>`
      ));
    }

    await sendWithGmail({
      to: guest.user.email,
      subject,
      text: renderEmailText({ heading, paragraphs }),
      html: renderEmail({ preheader: subject, eyebrow: t(locale, 'Đã điểm danh', 'Checked in'), heading, paragraphs }),
    });
    return res.status(200).json({ sent: 1 });
  } catch (error) {
    console.error('Check-in notification failed:', error);
    return res.status(502).json({ error: 'NOTIFY_FAILED' });
  }
}

// ---- was api/notify-checkin-undo.js ----
async function handleCheckinUndo(req, res, admin, userData, body) {
  const bookingId = getText(body.bookingId);
  const reason = getText(body.reason).slice(0, 200);
  if (!bookingId || !reason) return res.status(400).json({ error: 'VALID_BOOKING_AND_REASON_REQUIRED' });

  try {
    const { data: booking, error: bookingError } = await admin
      .from('bookings')
      .select('id, event_id, user_id, status')
      .eq('id', bookingId)
      .maybeSingle();
    if (bookingError) throw bookingError;
    if (!booking || booking.status !== 'confirmed' || !booking.user_id) {
      return res.status(200).json({ sent: 0 });
    }

    const { data: event, error: eventError } = await admin
      .from('events')
      .select('id, name, organizer_id')
      .eq('id', booking.event_id)
      .maybeSingle();
    if (eventError) throw eventError;
    if (!event) return res.status(200).json({ sent: 0 });

    const { data: organizer, error: organizerError } = await admin
      .from('organizers')
      .select('owner_id, user_id')
      .eq('id', event.organizer_id)
      .maybeSingle();
    if (organizerError) throw organizerError;

    const isOwner = organizer && (organizer.owner_id === userData.user.id || organizer.user_id === userData.user.id);
    if (!isOwner) return res.status(403).json({ error: 'NOT_AUTHORIZED' });

    const { data: guest, error: guestError } = await admin.auth.admin.getUserById(booking.user_id);
    if (guestError || !guest?.user?.email) return res.status(200).json({ sent: 0 });

    const { data: guestProfile } = await admin.from('profiles').select('locale').eq('id', booking.user_id).maybeSingle();
    const locale = guestProfile?.locale === 'en' ? 'en' : 'vi';

    const eventNameRaw = event.name || t(locale, 'sự kiện', 'this event');
    const eventName = escapeHtml(eventNameRaw);
    const reasonSafe = escapeHtml(reason);

    const subject = t(locale, `Điểm danh của bạn đã được huỷ ▪︎ ${eventNameRaw}`, `Your check-in was reversed ▪︎ ${eventNameRaw}`);
    const heading = t(locale, 'Điểm danh của bạn đã được huỷ', 'Your check-in was reversed');
    const paragraphs = [
      t(
        locale,
        `<strong>${eventName}</strong> vừa huỷ điểm danh có mặt của bạn trên banbe.`,
        `<strong>${eventName}</strong> just reversed your check-in on banbe.`
      ),
      t(locale, `Lý do: ${reasonSafe}`, `Reason: ${reasonSafe}`),
    ];
    const footNote = t(
      locale,
      'Nếu bạn vẫn đang ở sự kiện, người tổ chức có thể điểm danh lại cho bạn bất cứ lúc nào.',
      'If you\'re still at the event, the organizer can check you back in any time.'
    );

    await sendWithGmail({
      to: guest.user.email,
      subject,
      text: renderEmailText({ heading, paragraphs, footNote }),
      html: renderEmail({ preheader: subject, eyebrow: t(locale, 'Cập nhật vé', 'Ticket update'), heading, paragraphs, footNote }),
    });
    return res.status(200).json({ sent: 1 });
  } catch (error) {
    console.error('Check-in undo notification failed:', error);
    return res.status(502).json({ error: 'NOTIFY_FAILED' });
  }
}

// ---- was api/notify-name-change.js ----
async function findOrganizerRecipients(admin, guestId) {
  const { data: bookings, error: bookingsError } = await admin
    .from('bookings')
    .select('event_id')
    .eq('user_id', guestId);
  if (bookingsError) throw bookingsError;

  const eventIds = [...new Set((bookings || []).map(b => b.event_id).filter(Boolean))];
  if (eventIds.length === 0) return [];

  const { data: events, error: eventsError } = await admin
    .from('events')
    .select('id, organizer_id')
    .in('id', eventIds);
  if (eventsError) throw eventsError;

  const organizerIds = [...new Set((events || []).map(e => e.organizer_id).filter(Boolean))];
  if (organizerIds.length === 0) return [];

  const { data: organizers, error: organizersError } = await admin
    .from('organizers')
    .select('owner_id, user_id')
    .in('id', organizerIds);
  if (organizersError) throw organizersError;

  const targetIds = new Set();
  for (const org of organizers || []) {
    if (org.owner_id && org.owner_id !== guestId) targetIds.add(org.owner_id);
    if (org.user_id && org.user_id !== guestId) targetIds.add(org.user_id);
  }

  const recipients = [];
  for (const uid of targetIds) {
    const { data, error } = await admin.auth.admin.getUserById(uid);
    if (error || !data?.user?.email) continue;
    const { data: profile } = await admin.from('profiles').select('locale').eq('id', uid).maybeSingle();
    recipients.push({ email: data.user.email, locale: profile?.locale === 'en' ? 'en' : 'vi' });
  }
  return recipients;
}

async function handleNameChange(req, res, admin, userData, body) {
  const oldName = getText(body.oldName).slice(0, 60);
  const newName = getText(body.newName).slice(0, 60);
  if (!newName) return res.status(400).json({ error: 'VALID_NAME_REQUIRED' });

  try {
    const recipients = await findOrganizerRecipients(admin, userData.user.id);
    if (recipients.length === 0) return res.status(200).json({ sent: 0 });

    let sent = 0;
    for (const { email: to, locale } of recipients) {
      const displayOld = escapeHtml(oldName || t(locale, '(không rõ)', '(unknown)'));
      const displayNew = escapeHtml(newName);

      const subject = t(locale, 'Một khách đã đổi tên trên banbe', 'A guest changed their name on banbe');
      const heading = t(locale, 'Một khách đã đổi tên', 'A guest changed their name');
      const paragraphs = [
        t(
          locale,
          `${displayOld} đã đổi tên thành <strong>${displayNew}</strong> trên banbe.`,
          `${displayOld} is now shown as <strong>${displayNew}</strong> on banbe.`
        ),
      ];

      try {
        await sendWithGmail({
          to,
          subject,
          text: renderEmailText({ heading, paragraphs }),
          html: renderEmail({ preheader: subject, eyebrow: t(locale, 'Khách của bạn', 'Your guest'), heading, paragraphs }),
        });
        sent += 1;
      } catch (error) {
        console.error('Name-change notification email failed for', to, error);
      }
    }
    return res.status(200).json({ sent, total: recipients.length });
  } catch (error) {
    console.error('Name-change notification failed:', error);
    return res.status(502).json({ error: 'NOTIFY_FAILED' });
  }
}

// ---- was api/notify-referral-joined.js ----
async function handleReferralJoined(req, res, admin, userData) {
  try {
    const { data: newProfile, error: newProfileError } = await admin
      .from('profiles')
      .select('display_name, referred_by')
      .eq('id', userData.user.id)
      .maybeSingle();
    if (newProfileError) throw newProfileError;
    if (!newProfile?.referred_by) return res.status(200).json({ sent: 0 });

    const { data: referrer, error: referrerError } = await admin.auth.admin.getUserById(newProfile.referred_by);
    if (referrerError || !referrer?.user?.email) return res.status(200).json({ sent: 0 });

    const { data: referrerProfile } = await admin
      .from('profiles')
      .select('locale')
      .eq('id', newProfile.referred_by)
      .maybeSingle();
    const locale = referrerProfile?.locale === 'en' ? 'en' : 'vi';
    const newNameRaw = (newProfile.display_name || '').trim() || t(locale, 'Một người bạn', 'A friend');
    const newNameSafe = escapeHtml(newNameRaw);

    const subject = t(locale, 'Một người bạn vừa tham gia banbe', 'A friend just joined banbe');
    const heading = t(
      locale,
      `${newNameRaw} vừa tham gia banbe`,
      `${newNameRaw} just joined banbe`
    );
    const paragraphs = [
      t(
        locale,
        `${newNameSafe} vừa tham gia banbe qua lời mời của bạn. Cảm ơn bạn đã giới thiệu banbe cho bạn bè!`,
        `${newNameSafe} joined through your invite link. Thanks for bringing them along!`
      ),
    ];

    const html = renderEmail({
      preheader: heading,
      eyebrow: t(locale, 'Lời mời', 'Referral'),
      heading,
      paragraphs,
    });
    const text = renderEmailText({ heading, paragraphs });

    await sendWithGmail({ to: referrer.user.email, subject, text, html });
    return res.status(200).json({ sent: 1 });
  } catch (error) {
    console.error('Referral-joined notification failed:', error);
    return res.status(502).json({ error: 'NOTIFY_FAILED' });
  }
}

// ---- payment document upload/replacement (Tasks 3/4/6, migration 056) ----
// The caller here is the organizer who just called upload_payment_document()
// — this looks up the document THEY uploaded and emails a copy to the
// participant it belongs to, not to the caller. Re-verifies organizer
// ownership itself rather than trusting that the RPC already checked it,
// same defensive posture as every other handler in this file.
async function loadDocumentForNotify(admin, documentId, actorId) {
  const { data: doc, error: docError } = await admin
    .from('payment_documents')
    .select('id, booking_id, kind, file_path, upload_reason, user_id, organizer_id, superseded_at')
    .eq('id', documentId)
    .maybeSingle();
  if (docError) throw docError;
  if (!doc || !doc.user_id) return null;

  const { data: organizer, error: organizerError } = await admin
    .from('organizers')
    .select('owner_id, user_id, name')
    .eq('id', doc.organizer_id)
    .maybeSingle();
  if (organizerError) throw organizerError;
  const isOwner = organizer && (organizer.owner_id === actorId || organizer.user_id === actorId);
  if (!isOwner) return null;

  const { data: guest, error: guestError } = await admin.auth.admin.getUserById(doc.user_id);
  if (guestError || !guest?.user?.email) return null;

  const { data: guestProfile } = await admin
    .from('profiles')
    .select('locale, auto_email_documents')
    .eq('id', doc.user_id)
    .maybeSingle();

  return {
    doc,
    organizerName: organizer?.name || '',
    email: guest.user.email,
    locale: guestProfile?.locale === 'en' ? 'en' : 'vi',
    autoEmail: guestProfile?.auto_email_documents === true,
  };
}

async function attachmentForDocument(admin, doc) {
  if (!doc.file_path) return null;
  const { data: blob, error } = await admin.storage.from('payment-documents').download(doc.file_path);
  if (error || !blob) {
    console.error('payment-document notify: file download failed:', doc.file_path, error);
    return null;
  }
  const ext = doc.file_path.includes('.') ? doc.file_path.slice(doc.file_path.lastIndexOf('.')) : '';
  return {
    filename: (doc.kind === 'invoice' ? 'invoice' : 'receipt') + ext,
    content: Buffer.from(await blob.arrayBuffer()),
  };
}

// ---- new: first upload — only emails if the participant opted in (Task 4) ----
async function handleDocumentUploaded(req, res, admin, userData, body) {
  const documentId = getText(body.documentId);
  if (!documentId) return res.status(400).json({ error: 'VALID_DOCUMENT_REQUIRED' });

  try {
    const ctx = await loadDocumentForNotify(admin, documentId, userData.user.id);
    if (!ctx) return res.status(200).json({ sent: 0 });
    if (!ctx.autoEmail) return res.status(200).json({ sent: 0, reason: 'NOT_OPTED_IN' });

    const { doc, locale, email } = ctx;
    const kindLabel = t(locale, doc.kind === 'invoice' ? 'hoá đơn' : 'biên nhận', doc.kind === 'invoice' ? 'invoice' : 'receipt');
    const subject = t(locale, `Bạn có một ${kindLabel} mới từ banbe`, `You have a new ${kindLabel} from banbe`);
    const heading = t(locale, `${kindLabel[0].toUpperCase()}${kindLabel.slice(1)} của bạn đã sẵn sàng`, `Your ${kindLabel} is ready`);
    const paragraphs = [
      t(locale,
        `Người tổ chức vừa tải lên ${kindLabel} cho lượt đặt chỗ của bạn — đính kèm bản sao trong email này để lưu trữ.`,
        `The organizer just uploaded your ${kindLabel} — a copy is attached to this email for your records.`),
      t(locale,
        'Bạn đang nhận email này vì đã bật "Tự động gửi email hoá đơn/biên nhận" trong Tuỳ chọn. Có thể tắt bất cứ lúc nào.',
        'You are getting this because "Automatically email me a copy of invoices/receipts" is on in your Preferences. You can turn it off any time.'),
    ];

    const attachment = await attachmentForDocument(admin, doc);
    await sendWithGmail({
      to: email,
      subject,
      text: renderEmailText({ heading, paragraphs }),
      html: renderEmail({ preheader: subject, eyebrow: t(locale, 'Chứng từ thanh toán', 'Payment document'), heading, paragraphs }),
      attachments: attachment ? [attachment] : [],
    });
    return res.status(200).json({ sent: 1 });
  } catch (error) {
    console.error('Document-uploaded notification failed:', error);
    return res.status(502).json({ error: 'NOTIFY_FAILED' });
  }
}

// ---- new: replacement — always sent (Task 6), attaches the new file only if opted in (Task 4) ----
async function handleDocumentReplaced(req, res, admin, userData, body) {
  const documentId = getText(body.documentId);
  if (!documentId) return res.status(400).json({ error: 'VALID_DOCUMENT_REQUIRED' });

  try {
    const ctx = await loadDocumentForNotify(admin, documentId, userData.user.id);
    if (!ctx) return res.status(200).json({ sent: 0 });

    const { doc, locale, email, organizerName } = ctx;
    const reason = escapeHtml(doc.upload_reason || '');
    const kindLabel = t(locale, doc.kind === 'invoice' ? 'hoá đơn' : 'biên nhận', doc.kind === 'invoice' ? 'invoice' : 'receipt');
    const subject = t(locale, `${kindLabel[0].toUpperCase()}${kindLabel.slice(1)} của bạn đã được cập nhật`, `Your ${kindLabel} was updated`);
    const heading = t(locale, `${kindLabel[0].toUpperCase()}${kindLabel.slice(1)} đã được thay thế`, `Your ${kindLabel} was replaced`);
    const paragraphs = [
      t(locale,
        `${escapeHtml(organizerName) || 'Người tổ chức'} vừa tải lên bản ${kindLabel} mới, thay cho bản trước đó.`,
        `${escapeHtml(organizerName) || 'The organizer'} just uploaded a new ${kindLabel}, replacing the previous one.`),
      t(locale, `Lý do: ${reason}`, `Reason: ${reason}`),
      t(locale,
        'Bản cũ sẽ bị xoá trong vòng 24 giờ tới. Nếu bạn cần bản cũ trước khi bị xoá, hãy liên hệ trực tiếp email của người tổ chức.',
        "The previous version will be deleted within the next 24 hours. If you need it before then, contact the organizer's email directly."),
    ];
    if (ctx.autoEmail) {
      paragraphs.push(t(locale, 'Bản mới được đính kèm trong email này.', 'The new version is attached to this email.'));
    }

    const attachment = ctx.autoEmail ? await attachmentForDocument(admin, doc) : null;
    await sendWithGmail({
      to: email,
      subject,
      text: renderEmailText({ heading, paragraphs }),
      html: renderEmail({ preheader: subject, eyebrow: t(locale, 'Chứng từ thanh toán', 'Payment document'), heading, paragraphs }),
      attachments: attachment ? [attachment] : [],
    });
    return res.status(200).json({ sent: 1 });
  } catch (error) {
    console.error('Document-replaced notification failed:', error);
    return res.status(502).json({ error: 'NOTIFY_FAILED' });
  }
}

// ---- was api/notify-welcome.js ----
async function handleWelcome(req, res, admin, userData) {
  if (!userData.user.email) return res.status(200).json({ sent: 0 });

  try {
    const { data: profile, error: profileError } = await admin
      .from('profiles')
      .select('display_name, locale, referral_code')
      .eq('id', userData.user.id)
      .maybeSingle();
    if (profileError) throw profileError;
    if (!profile?.referral_code) return res.status(200).json({ sent: 0 });

    const locale = profile.locale === 'en' ? 'en' : 'vi';
    const name = (profile.display_name || '').trim();
    const referralLink = `${getRedirectUrl(req)}/?ref=${profile.referral_code}`;

    const subject = t(locale, 'Chào mừng bạn đến với banbe', 'Welcome to banbe');
    const heading = t(
      locale,
      name ? `Chào ${name}, tài khoản của bạn đã sẵn sàng` : 'Tài khoản của bạn đã sẵn sàng',
      name ? `Welcome, ${name} — you're all set` : "You're all set"
    );
    const paragraphs = [
      t(
        locale,
        'Từ giờ mỗi tuần sẽ có vài buổi hay ho dành cho bạn — supper club, phòng tranh, gig nhạc nhỏ. Không xếp hạng, không quảng cáo, không lướt vô tận.',
        "Every week from here on, there'll be a few good things happening near you — supper clubs, small galleries, tucked-away gigs. No ratings, no ads, no endless scrolling."
      ),
      t(
        locale,
        'banbe vui hơn khi có bạn bè cùng tham gia. Chia sẻ liên kết dưới đây — khi ai đó tham gia qua đó, bạn sẽ là người đã mời họ.',
        "banbe is better with people you know. Share your link below — anyone who joins through it, you'll be the one who brought them in."
      ),
    ];

    const html = renderEmail({
      preheader: t(locale, 'Tài khoản của bạn đã sẵn sàng.', "Your account is ready."),
      eyebrow: t(locale, 'Chào mừng', 'Welcome'),
      heading,
      paragraphs,
      cta: { label: t(locale, 'Chia sẻ banbe với bạn bè', 'Share banbe with a friend'), href: referralLink },
    });
    const text = renderEmailText({
      heading,
      paragraphs,
      cta: { label: t(locale, 'Chia sẻ banbe với bạn bè', 'Share banbe with a friend'), href: referralLink },
    });

    await sendWithGmail({ to: userData.user.email, subject, text, html });
    return res.status(200).json({ sent: 1 });
  } catch (error) {
    console.error('Welcome email failed:', error);
    return res.status(502).json({ error: 'NOTIFY_FAILED' });
  }
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }

  const admin = getSupabaseAdmin();
  const missing = [
    ...getMissingEmailVariables(),
    !admin && 'SUPABASE_SERVICE_ROLE_KEY',
  ].filter(Boolean);
  if (missing.length) {
    return res.status(503).json({ error: 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED', missing });
  }

  const token = getText((req.headers.authorization || '').replace(/^Bearer\s+/i, ''));
  if (!token) return res.status(401).json({ error: 'AUTH_REQUIRED' });

  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData?.user) return res.status(401).json({ error: 'AUTH_REQUIRED' });

  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const type = getText(body.type);

  switch (type) {
    case 'booking_cancelled': return handleBookingCancelled(req, res, admin, userData, body);
    case 'check_in': return handleCheckIn(req, res, admin, userData, body);
    case 'checkin_undo': return handleCheckinUndo(req, res, admin, userData, body);
    case 'name_change': return handleNameChange(req, res, admin, userData, body);
    case 'referral_joined': return handleReferralJoined(req, res, admin, userData, body);
    case 'welcome': return handleWelcome(req, res, admin, userData, body);
    case 'document_uploaded': return handleDocumentUploaded(req, res, admin, userData, body);
    case 'document_replaced': return handleDocumentReplaced(req, res, admin, userData, body);
    default: return res.status(400).json({ error: 'VALID_NOTIFY_TYPE_REQUIRED' });
  }
}
