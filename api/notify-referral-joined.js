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
  return createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
}

function t(locale, vi, en) {
  return locale === 'en' ? en : vi;
}

// Tells the referrer their invite actually landed — sent once, right after
// redeem_referral() (migration 023) links a brand-new account to whoever
// invited them. The in-app notification is written by that RPC itself in
// the same transaction; this only dispatches the email side, and re-derives
// the referrer entirely from the new account's own profiles.referred_by
// rather than trusting a referrer id from the client.
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
    // Two variants: `heading` goes through renderEmail()'s own escaping of
    // the whole string, so it needs the raw name; `paragraphs` are trusted
    // HTML that renderEmail() doesn't touch, so anything dynamic inside one
    // has to be escaped here first.
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
