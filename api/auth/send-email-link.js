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

// Look up an auth user by email through the Auth Admin API. Used only as a
// fallback: it needs a real service-role key and pages through every user.
async function listUsersByEmail(admin, email) {
  const perPage = 200;
  for (let page = 1; page <= 20; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) throw error;
    const users = data?.users || [];
    const match = users.find(u => (u.email || '').toLowerCase() === email);
    if (match) return match;
    if (users.length < perPage) break;
  }
  return null;
}

function errorCode(error) {
  return error?.code || error?.status || error?.name || 'UNKNOWN';
}

// Answer "does this email already have an account?" — and, crucially, be able
// to say "I could not find out". Every source here can be unavailable (the
// registry table may not exist yet, the RPC may not be migrated, the Auth
// Admin API needs a service-role key), and treating an unavailable source as
// "no such account" is what produced a bogus AUTH_ACCOUNT_NOT_FOUND for
// accounts that plainly existed. Only a source that actually answered counts.
async function resolveAuthUserId(admin, email) {
  const sources = [];

  // 1. The registry: a plain table read, no admin privileges needed.
  try {
    const { data, error } = await admin
      .from('email_registrations')
      .select('auth_user_id')
      .eq('email', email)
      .maybeSingle();
    if (error) throw error;
    if (data?.auth_user_id) {
      sources.push({ source: 'registry', ok: true, found: true });
      return { userId: data.auth_user_id, resolved: true, sources };
    }
    // A missing row (or one orphaned by a deleted user) is not proof of
    // absence — the registry is only populated going forward.
    sources.push({ source: 'registry', ok: true, found: false });
  } catch (error) {
    sources.push({ source: 'registry', ok: false, code: errorCode(error) });
  }

  // 2. auth.users itself, via the SECURITY DEFINER lookup. Authoritative.
  try {
    const { data, error } = await admin.rpc('find_auth_user_by_email', { p_email: email });
    if (error) throw error;
    sources.push({ source: 'rpc', ok: true, found: Boolean(data) });
    return { userId: data || null, resolved: true, sources };
  } catch (error) {
    sources.push({ source: 'rpc', ok: false, code: errorCode(error) });
  }

  // 3. Auth Admin API. Also authoritative, but the most fragile.
  try {
    const user = await listUsersByEmail(admin, email);
    sources.push({ source: 'adminApi', ok: true, found: Boolean(user) });
    return { userId: user?.id || null, resolved: true, sources };
  } catch (error) {
    sources.push({ source: 'adminApi', ok: false, code: errorCode(error) });
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

// Describes the configured server key without revealing any of it. A key with
// role "anon"/"sb_publishable" reads tables fine but cannot use the Auth Admin
// API, which is exactly the shape of failure that used to surface as
// "no account exists for this email".
function describeServerKey(key) {
  if (!key) return 'missing';
  if (key.startsWith('sb_secret_')) return 'sb_secret';
  if (key.startsWith('sb_publishable_')) return 'sb_publishable';
  const parts = key.split('.');
  if (parts.length === 3) {
    try {
      return `jwt:${JSON.parse(Buffer.from(parts[1], 'base64url').toString()).role || 'unknown'}`;
    } catch {
      return 'jwt:unreadable';
    }
  }
  return 'unrecognised';
}

// GET ?diagnose=1 — reports which lookup sources actually work, so a
// configuration problem can be told apart from a code problem without having
// to trigger a real sign-in. Returns capability flags only, never key material.
async function diagnose(admin) {
  const probeEmail = 'diagnostics-probe@banbe.invalid';
  const { sources } = await resolveAuthUserId(admin, probeEmail);
  const byName = Object.fromEntries(sources.map(s => [s.source, s]));
  return {
    serviceKey: describeServerKey(process.env.SUPABASE_SERVICE_ROLE_KEY),
    supabaseUrlConfigured: Boolean(process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL),
    emailVariablesMissing: getMissingEmailVariables(),
    registryTable: byName.registry?.ok ? 'ok' : `unavailable (${byName.registry?.code})`,
    lookupRpc: byName.rpc ? (byName.rpc.ok ? 'ok' : `unavailable (${byName.rpc.code})`) : 'not reached',
    authAdminApi: byName.adminApi ? (byName.adminApi.ok ? 'ok' : `unavailable (${byName.adminApi.code})`) : 'not reached',
    canResolveAccounts: sources.some(s => s.ok && s.source !== 'registry'),
  };
}

export default async function handler(req, res) {
  const wantsDiagnosis = req.method === 'GET' && /[?&]diagnose=1(&|$)/.test(req.url || '');
  if (req.method !== 'POST' && !wantsDiagnosis) {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }

  const admin = getSupabaseAdmin();
  if (wantsDiagnosis) {
    if (!admin) {
      return res.status(200).json({
        serviceKey: describeServerKey(process.env.SUPABASE_SERVICE_ROLE_KEY),
        supabaseUrlConfigured: Boolean(process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL),
        emailVariablesMissing: getMissingEmailVariables(),
        canResolveAccounts: false,
      });
    }
    return res.status(200).json(await diagnose(admin));
  }

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
  // someone with a perfectly good account to sign up again.
  if (!resolved) {
    console.error('Account lookup could not be completed:', sources);
    return res.status(502).json({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED', sources });
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
