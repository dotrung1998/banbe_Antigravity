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
  const senderId = userData.user.id;

  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const threadId = getText(body.threadId);
  const messageBody = getText(body.body).slice(0, 1000);
  if (!threadId || !messageBody) return res.status(400).json({ error: 'VALID_MESSAGE_REQUIRED' });

  try {
    // The recipient is whoever is on the *other* side of the thread from the
    // caller — re-derived from the database, and only sent to if the caller
    // is actually a participant of this thread (the same check the messages
    // table's own RLS enforces on the insert itself).
    const { data: thread, error: threadError } = await admin
      .from('threads')
      .select('id, guest_id, organizer_id')
      .eq('id', threadId)
      .maybeSingle();
    if (threadError) throw threadError;
    if (!thread) return res.status(200).json({ sent: 0 });

    const { data: organizer, error: organizerError } = await admin
      .from('organizers')
      .select('owner_id, user_id')
      .eq('id', thread.organizer_id)
      .maybeSingle();
    if (organizerError) throw organizerError;

    const organizerIds = new Set([organizer?.owner_id, organizer?.user_id].filter(Boolean));
    const isGuest = thread.guest_id === senderId;
    const isOrganizer = organizerIds.has(senderId);
    if (!isGuest && !isOrganizer) return res.status(403).json({ error: 'NOT_AUTHORIZED' });

    const recipientIds = isGuest
      ? [...organizerIds].filter(id => id !== senderId)
      : (thread.guest_id && thread.guest_id !== senderId ? [thread.guest_id] : []);
    if (recipientIds.length === 0) return res.status(200).json({ sent: 0 });

    const { data: sender } = await admin.from('profiles').select('display_name').eq('id', senderId).maybeSingle();
    const senderName = (sender?.display_name || '').trim() || 'Một người dùng';
    const subject = `Tin nhắn mới từ ${senderName} trên banbe`;
    const text = `${senderName}: ${messageBody}`;
    const html = `<p><strong>${escapeHtml(senderName)}</strong>: ${escapeHtml(messageBody)}</p>`;

    let sent = 0;
    for (const uid of recipientIds) {
      const { data: recipient, error: recipientError } = await admin.auth.admin.getUserById(uid);
      if (recipientError || !recipient?.user?.email) continue;
      try {
        await sendWithGmail({ to: recipient.user.email, subject, text, html });
        sent += 1;
      } catch (error) {
        console.error('Chat notification email failed for', uid, error);
      }
    }
    return res.status(200).json({ sent });
  } catch (error) {
    console.error('Chat notification failed:', error);
    return res.status(502).json({ error: 'NOTIFY_FAILED' });
  }
}
