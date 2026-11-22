import { createClient } from '@supabase/supabase-js';
import { requestOrigin } from './origin.js';

// Shared by every auth endpoint that needs to answer "does this email
// already have an account?" (send-email-code, signup-password,
// send-password-reset) — factored out of what used to be three separate
// copies of the same lookup chain.

export function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) return null;

  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
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
export async function linkRegistration(admin, email, userId) {
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
export async function resolveAuthUserId(admin, email) {
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

// Keep a configured/header-derived origin on http(s), require https outside
// local development, and strip credentials and a trailing slash. This does not
// by itself prove that a forwarded Host is trustworthy — set AUTH_REDIRECT_URL
// in production — but it stops a non-http scheme or a plain-http external host
// from becoming an email redirect target.
function normaliseRedirect(value) {
  if (!value) return null;
  try {
    const url = new URL(String(value));
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
    if (url.username || url.password) return null;
    const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
    if (url.protocol === 'http:' && !local) return null;
    return `${url.origin}${url.pathname.replace(/\/+$/, '')}`;
  } catch {
    return null;
  }
}

export function getRedirectUrl(req) {
  const configured = process.env.AUTH_REDIRECT_URL || process.env.VITE_AUTH_REDIRECT_URL || process.env.VITE_SITE_URL;
  const configuredUrl = normaliseRedirect(configured);
  if (configuredUrl) return configuredUrl;

  // A forwarded Host is not proof of origin: an unknown host must never become
  // a password-reset redirect target (Supabase would hand the session tokens
  // to whatever site that Host names). requestOrigin() allowlists it and falls
  // back to the canonical site.
  return normaliseRedirect(requestOrigin(req)) || 'http://localhost:5173';
}
