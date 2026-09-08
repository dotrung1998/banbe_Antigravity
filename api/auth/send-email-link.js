import { createClient } from '@supabase/supabase-js';
import { randomBytes } from 'node:crypto';
import { getMissingEmailVariables, sendWithGmail } from '../_lib/email.js';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const ACCOUNT_TYPES = new Set(['participant', 'organizer', 'admin']);

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
  const accountType = getText(body.accountType);

  if (!EMAIL_PATTERN.test(email)) return res.status(400).json({ error: 'VALID_EMAIL_REQUIRED' });
  if (mode !== 'signup' && mode !== 'login') return res.status(400).json({ error: 'VALID_AUTH_MODE_REQUIRED' });
  if (!ACCOUNT_TYPES.has(accountType)) return res.status(400).json({ error: 'VALID_ACCOUNT_TYPE_REQUIRED' });
  if (mode === 'signup' && accountType === 'admin') return res.status(400).json({ error: 'ADMIN_SIGNUP_NOT_ALLOWED' });

  let registration = null;
  try {
    const { data, error } = await admin
      .from('email_registrations')
      .select('role, auth_user_id')
      .eq('email', email)
      .maybeSingle();
    if (error) throw error;
    registration = data;
  } catch (error) {
    console.error('Supabase account registry lookup failed:', error);
    if (error?.code === 'PGRST205') {
      registration = null;
    } else {
      return res.status(502).json({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' });
    }
  }

  // Fall back to Auth whenever the registry row is missing OR is not linked
  // to a live auth user (auth_user_id can be NULL after a user was deleted
  // and re-created, or when the backfill migration has not run yet).
  if (!registration?.auth_user_id) {
    try {
      const { data: authUser } = await admin.auth.admin.getUserByEmail(email);
      if (authUser?.user) {
        try {
          const { data: profile } = await admin.from('profiles').select('role').eq('id', authUser.user.id).maybeSingle();
          const role = profile?.role || authUser.user.user_metadata?.account_type || authUser.user.raw_user_meta_data?.account_type;
          registration = { role, auth_user_id: authUser.user.id };
        } catch (profileError) {
          console.warn('Profile query failed:', profileError);
          const role = authUser.user.user_metadata?.account_type || authUser.user.raw_user_meta_data?.account_type;
          registration = role ? { role, auth_user_id: authUser.user.id } : null;
        }
      }
    } catch (e) {
      console.warn('Failed to check existing user role:', e);
    }
  }

  if (mode === 'login' && !registration?.auth_user_id) {
    return res.status(404).json({ error: 'AUTH_ACCOUNT_NOT_FOUND' });
  }

  // The email already has a live auth account, so a sign-up link cannot be
  // generated for it (Supabase rejects duplicate signups). Direct the user
  // to log in instead of failing with a generic link-generation error.
  if (mode === 'signup' && registration?.auth_user_id) {
    return res.status(409).json({ error: 'AUTH_ACCOUNT_EXISTS' });
  }

  try {
    const existingRole = registration?.role || null;

    if (existingRole && existingRole !== accountType) {
      return res.status(400).json({
        error: 'AUTH_ROLE_MISMATCH',
        message: `This email is already registered as ${/^[aeiou]/i.test(existingRole) ? 'an' : 'a'} ${existingRole}. Choose that account type to continue.`,
        existingRole,
      });
    }

    const linkRequest = {
      type: mode === 'signup' ? 'signup' : 'magiclink',
      email,
      options: {
        redirectTo: getRedirectUrl(req),
        data: { account_type: accountType },
      },
    };
    if (mode === 'signup') {
      linkRequest.password = randomBytes(32).toString('base64url');
    }

    const { data, error } = await admin.auth.admin.generateLink(linkRequest);

    if (error || !data?.properties?.action_link) {
      console.error('Supabase auth link generation failed:', error);
      return res.status(502).json({ error: 'AUTH_LINK_GENERATION_FAILED' });
    }

    const actionLink = data.properties.action_link;
    const subject = mode === 'signup' ? 'Confirm your banbe account' : 'Your banbe sign-in link';
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