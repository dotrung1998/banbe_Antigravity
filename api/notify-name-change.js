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

// Every organizer this guest has ever booked with — the same relationship
// rename_display_name() already used to write the in-app notification rows.
// Re-derived from the database here rather than trusting whatever the client
// sends, so this endpoint can't be made to email arbitrary addresses.
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
