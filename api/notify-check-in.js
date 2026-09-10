import { createClient } from '@supabase/supabase-js';
import { getMissingEmailVariables, sendWithGmail } from './_lib/email.js';

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[character]));
}

function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) return null;

  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
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

    const eventName = event.name || 'sự kiện';
    const subject = `Bạn đã được điểm danh ▪︎ ${eventName}`;
    const text = `Bạn vừa được điểm danh có mặt tại ${eventName} trên banbe.`;
    const html = `<p>Bạn vừa được điểm danh có mặt tại <strong>${escapeHtml(eventName)}</strong> trên banbe.</p>`;

    await sendWithGmail({ to: guest.user.email, subject, text, html });
    return res.status(200).json({ sent: 1 });
  } catch (error) {
    console.error('Check-in notification failed:', error);
    return res.status(502).json({ error: 'NOTIFY_FAILED' });
  }
}
