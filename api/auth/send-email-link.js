import { createClient } from '@supabase/supabase-js';
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

  try {
    let existingRole = null;
    try {
      const { data: authUser } = await admin.auth.admin.getUserByEmail(email);
      if (authUser?.user) {
        try {
          const { data: profile } = await admin.from('profiles').select('role').eq('id', authUser.user.id).maybeSingle();
          if (profile?.role) {
            existingRole = profile.role;
          } else {
            existingRole = authUser.user.user_metadata?.account_type || authUser.user.raw_user_meta_data?.account_type;
          }
        } catch (profileError) {
          console.warn('Profile query failed:', profileError);
          existingRole = authUser.user.user_metadata?.account_type || authUser.user.raw_user_meta_data?.account_type;
        }
        if (!existingRole) existingRole = 'participant';
      }
    } catch (e) {
      console.warn('Failed to check existing user role:', e);
    }

    if (existingRole && existingRole !== accountType) {
      return res.status(400).json({
        error: `This email is registered as a ${existingRole}. To continue as an ${accountType}, please complete the ${accountType} registration process.`,
      });
    }

    const { data, error } = await admin.auth.admin.generateLink({
      type: mode === 'signup' ? 'signup' : 'magiclink',
      email,
      options: {
        redirectTo: getRedirectUrl(req),
        data: { account_type: accountType },
      },
    });

    if (error || !data?.properties?.action_link) {
      console.error('Supabase auth link generation failed:', error);
      return res.status(502).json({ error: 'AUTH_LINK_GENERATION_FAILED' });
    }

    const actionLink = data.properties.action_link;
    const subject = mode === 'signup' ? 'Confirm your banbe account' : 'Your banbe sign-in link';
    const safeLink = escapeHtml(actionLink);
    await sendWithGmail({
      to: email,
      subject,
      text: `${subject}\n\nOpen this link to continue: ${actionLink}\n\nIf you did not request this email, you can ignore it.`,
      html: `<p>${subject}</p><p><a href="${safeLink}">Continue to banbe</a></p><p>If you did not request this email, you can ignore it.</p>`,
    });

    return res.status(200).json({ sent: true });
  } catch (error) {
    console.error('Auth email delivery failed:', error);
    return res.status(502).json({ error: 'AUTH_EMAIL_DELIVERY_FAILED' });
  }
}