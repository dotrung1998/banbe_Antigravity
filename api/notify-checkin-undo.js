import { createClient } from '@supabase/supabase-js';
import { getMissingEmailVariables, sendWithGmail } from './_lib/email.js';
import { renderEmail, renderEmailText, escapeHtml } from './_lib/emailTemplate.js';

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
  const bookingId = getText(body.bookingId);
  const reason = getText(body.reason).slice(0, 200);
  if (!bookingId || !reason) return res.status(400).json({ error: 'VALID_BOOKING_AND_REASON_REQUIRED' });

  try {
    // Re-derive everything from the database using the caller's own id: the
    // booking must be back to 'confirmed' (undo_check_in() already did that),
    // and the caller must own the organizer of its event.
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
