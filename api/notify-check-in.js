import { createClient } from '@supabase/supabase-js';
import { getMissingEmailVariables, sendWithGmail } from './_lib/email.js';
import { getRedirectUrl } from './_lib/authLookup.js';
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
  if (!bookingId) return res.status(400).json({ error: 'VALID_BOOKING_REQUIRED' });

  try {
    // Re-derive everything from the database using the caller's own id,
    // rather than trusting a recipient from the client: the booking must be
    // attended, and the caller must actually own the organizer of its event
    // — the same authorization check_in_guest() already enforced.
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
    // A good moment to mention it, never a required one — this is the only
    // place the referral link rides along with a notification rather than
    // its own email, since "you're having fun right now" is exactly when
    // asking "bring a friend next time" doesn't feel like an ask.
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
