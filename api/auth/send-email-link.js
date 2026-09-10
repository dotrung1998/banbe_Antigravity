import { createClient } from '@supabase/supabase-js';
import { randomBytes } from 'node:crypto';
import { getMissingEmailVariables, sendWithGmail } from '../_lib/email.js';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[character]));
}

function getRedirectUrl(req) {
  const configured = process.env.AUTH_REDIRECT_URL || process.env.VITE_AUTH_REDIRECT_URL || process.env.VITE_SITE_URL;
  if (configured) return configured.replace(/\/+$/, '');

  const protocol = getText(req.headers['x-forwarded-proto']) || 'http';
  const host = getText(req.headers['x-forwarded-host']) || getText(req.headers.host);
  return host ? `${protocol}://${host}` : 'http://localhost:5173';
}

// Look up an auth user by email. This supabase-js version has no
// getUserByEmail, so page through the admin user list instead.
async function findAuthUserByEmail(admin, email) {
  const perPage = 200;
  for (let page = 1; page <= 20; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) throw error;
    const users = data?.users || [];
    const match = users.find(u => (u.email || '').toLowerCase() === email);
    if (match) return match;
    if (!data || users.length < perPage) break;
  }
  return null;
}

// Keep the registry pointed at the live auth user so the login lookup can tell
// "never registered" apart from "registered". The role column is descriptive
// only — organizer mode is a toggle and never gates sign-in.
async function linkRegistration(admin, email, userId) {
  if (!userId) return;
  const { error } = await admin
    .from('email_registrations')
    .upsert({ email, auth_user_id: userId, updated_at: new Date().toISOString() }, { onConflict: 'email' });
  if (error) console.warn('Email registry link failed:', error);
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
    !admin && !(process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL) && 'SUPABASE_URL',
  ].filter(Boolean);
  if (missing.length) {
    return res.status(503).json({ error: 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED', missing });
  }

  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const email = getText(body.email).toLowerCase();
  const mode = getText(body.mode).toLowerCase();

  if (!EMAIL_PATTERN.test(email)) return res.status(400).json({ error: 'VALID_EMAIL_REQUIRED' });
  if (mode !== 'signup' && mode !== 'login') return res.status(400).json({ error: 'VALID_AUTH_MODE_REQUIRED' });

  // Does this email already have a live auth user? The registry answers first
  // because it is a plain table read; Auth is the fallback when the row is
  // missing or unlinked (auth_user_id is NULL after a user was deleted, or
  // when the backfill migration has not run yet).
  let authUserId = null;
  try {
    const { data, error } = await admin
      .from('email_registrations')
      .select('auth_user_id')
      .eq('email', email)
      .maybeSingle();
    if (error && error.code !== 'PGRST205') throw error;
    authUserId = data?.auth_user_id || null;
  } catch (error) {
    console.error('Supabase account registry lookup failed:', error);
    return res.status(502).json({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' });
  }

  if (!authUserId) {
    try {
      const authUser = await findAuthUserByEmail(admin, email);
      authUserId = authUser?.id || null;
      if (authUserId) await linkRegistration(admin, email, authUserId);
    } catch (e) {
      console.warn('Failed to check for an existing auth user:', e);
    }
  }

  if (mode === 'login' && !authUserId) {
    return res.status(404).json({ error: 'AUTH_ACCOUNT_NOT_FOUND' });
  }
  if (mode === 'signup' && authUserId) {
    return res.status(409).json({ error: 'AUTH_ACCOUNT_EXISTS' });
  }

  try {
    const linkType = authUserId ? 'magiclink' : 'signup';

    const linkRequest = {
      type: linkType,
      email,
      options: { redirectTo: getRedirectUrl(req) },
    };
    if (linkType === 'signup') {
      linkRequest.password = randomBytes(32).toString('base64url');
    }

    const { data, error } = await admin.auth.admin.generateLink(linkRequest);

    if (error || !data?.properties?.action_link) {
      console.error('Supabase auth link generation failed:', error);
      return res.status(502).json({ error: 'AUTH_LINK_GENERATION_FAILED' });
    }

    if (linkType === 'signup') await linkRegistration(admin, email, data?.user?.id || null);

    const actionLink = data.properties.action_link;
    const subject = linkType === 'signup' ? 'Confirm your banbe account' : 'Your banbe sign-in link';
    const safeLink = escapeHtml(actionLink);
    try {
      await sendWithGmail({
        to: email,
        subject,
        text: `${subject}\n\nOpen this link to continue: ${actionLink}\n\nIf you did not request this email, you can ignore it.`,
        html: `<p>${subject}</p><p><a href="${safeLink}">Continue to banbe</a></p><p>If you did not request this email, you can ignore it.</p>`,
      });
    } catch (error) {
      console.error('Gmail auth email delivery failed:', error);
      return res.status(502).json({ error: 'AUTH_EMAIL_DELIVERY_FAILED' });
    }

    return res.status(200).json({ sent: true });
  } catch (error) {
    console.error('Auth email request failed:', error);
    return res.status(502).json({ error: 'AUTH_EMAIL_REQUEST_FAILED' });
  }
}
