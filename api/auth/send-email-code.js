import { randomBytes } from 'node:crypto';
import { getMissingEmailVariables, sendWithGmail } from '../_lib/email.js';
import { getSupabaseAdmin, resolveAuthUserId, linkRegistration } from '../_lib/authLookup.js';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

// Sends a 6-digit sign-in/sign-up code by email — the replacement for the
// old magic-link flow (still generated the same way, via
// admin.auth.admin.generateLink, but this now mails the `email_otp` string
// that response carries instead of the `action_link`). The client verifies
// it directly against Supabase itself with
// supabase.auth.verifyOtp({ email, token, type }), the same shape the
// existing phone-OTP login already uses — no separate "verify" endpoint
// needed, since verifyOtp doesn't require the service role.
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

  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const email = getText(body.email).toLowerCase();
  const mode = getText(body.mode).toLowerCase();
  const displayName = getText(body.displayName).slice(0, 60);

  if (!EMAIL_PATTERN.test(email)) return res.status(400).json({ error: 'VALID_EMAIL_REQUIRED' });
  if (mode !== 'signup' && mode !== 'login') return res.status(400).json({ error: 'VALID_AUTH_MODE_REQUIRED' });
  if (mode === 'signup' && !displayName) return res.status(400).json({ error: 'VALID_NAME_REQUIRED' });

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
      options: {},
    };
    if (linkType === 'signup') {
      // generateLink still requires a password for a brand-new user even
      // though this app signs them in with the emailed code, not a
      // password — a placeholder the user never sees or needs, exactly
      // like before. If they later also set up password login (see
      // signup-password.js) that overwrites this with their real one.
      linkRequest.password = randomBytes(32).toString('base64url');
      // Becomes raw_user_meta_data, which handle_new_user() already reads
      // to seed profiles.display_name — no extra plumbing needed on the DB
      // side beyond what's already there.
      linkRequest.options.data = { display_name: displayName };
    }

    const { data, error } = await admin.auth.admin.generateLink(linkRequest);
    const code = data?.properties?.email_otp;

    if (error || !code) {
      console.error('Supabase OTP generation failed:', error);
      return res.status(502).json({ error: 'AUTH_LINK_GENERATION_FAILED' });
    }

    if (linkType === 'signup') await linkRegistration(admin, email, data?.user?.id || null);

    const subject = linkType === 'signup' ? 'Your banbe sign-up code' : 'Your banbe sign-in code';
    try {
      await sendWithGmail({
        to: email,
        subject,
        text: `${subject}\n\nEnter this code in the app: ${code}\n\nThis code expires shortly. If you did not request this, you can ignore it.`,
        html: `<p>${subject}</p><p style="font-size:28px;font-weight:700;letter-spacing:4px;">${code}</p><p>Enter this code in the app. It expires shortly. If you did not request this, you can ignore it.</p>`,
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
