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

// Look up an auth user by email through the Auth Admin API. This
// supabase-js version has no getUserByEmail, so page through the admin
// user list instead. Used only as a last-resort fallback below: it needs a
// real service-role key and pages through every user in the project.
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

// Answer "does this email already have an account?" — and, crucially, be able
// to say "I could not find out". Each source below can be unavailable (the
// registry row can be missing or unlinked, the RPC may not be migrated yet,
// the Auth Admin API can reject the configured key or simply error), and
// silently treating an unavailable source as "no such account" is exactly
// what produced a false AUTH_ACCOUNT_NOT_FOUND for an email that had in fact
// just registered successfully. Only a source that actually answered counts;
// everything else is reported as "unresolved" instead of "absent".
async function resolveAuthUserId(admin, email) {
  const sources = [];

  // 1. The registry: a plain table read, no admin privileges needed. Cheap,
  // but only populated for accounts created after the registry existed, or
  // once linkRegistration has run for this email.
  try {
    const { data, error } = await admin
      .from('email_registrations')
      .select('auth_user_id')
      .eq('email', email)
      .maybeSingle();
    if (error && error.code !== 'PGRST205') throw error;
    if (data?.auth_user_id) {
      sources.push({ source: 'registry', ok: true, found: true });
      return { userId: data.auth_user_id, resolved: true, sources };
    }
    sources.push({ source: 'registry', ok: true, found: false });
  } catch (error) {
    sources.push({ source: 'registry', ok: false, code: error?.code || error?.message });
  }

  // 2. auth.users itself, via a SECURITY DEFINER RPC. Authoritative and a
  // single round trip, but only exists once its migration has run.
  try {
    const { data, error } = await admin.rpc('find_auth_user_by_email', { p_email: email });
    if (error) throw error;
    sources.push({ source: 'rpc', ok: true, found: Boolean(data) });
    return { userId: data || null, resolved: true, sources };
  } catch (error) {
    sources.push({ source: 'rpc', ok: false, code: error?.code || error?.message });
  }

  // 3. Auth Admin API. Also authoritative, but the most fragile (needs a
  // real service-role key and can page through thousands of users).
  try {
    const user = await findAuthUserByEmail(admin, email);
    sources.push({ source: 'adminApi', ok: true, found: Boolean(user) });
    return { userId: user?.id || null, resolved: true, sources };
  } catch (error) {
    sources.push({ source: 'adminApi', ok: false, code: error?.code || error?.message });
  }

  return { userId: null, resolved: false, sources };
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

  const { userId: authUserId, resolved, sources } = await resolveAuthUserId(admin, email);

  // Not knowing is not the same as not existing. Say so, instead of telling
  // someone with a perfectly good account — like one that just registered —
  // to go sign up again.
  if (!resolved) {
    console.error('Account lookup could not be completed:', sources);
    return res.status(502).json({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' });
  }

  // Keep the registry current so the cheap path works next time.
  if (authUserId) await linkRegistration(admin, email, authUserId);

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
