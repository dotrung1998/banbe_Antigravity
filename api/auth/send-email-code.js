import { randomBytes } from 'node:crypto';
import { getMissingEmailVariables, sendWithGmail } from '../_lib/email.js';
import { getSupabaseAdmin, resolveAuthUserId, linkRegistration } from '../_lib/authLookup.js';
import { renderEmail, renderEmailText } from '../_lib/emailTemplate.js';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function t(locale, vi, en) {
  return locale === 'en' ? en : vi;
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
  // Only meaningful at signup (before there's a profiles row to read a
  // saved preference from) — an existing account's own profiles.locale
  // wins over whatever the client happens to be showing right now.
  const requestedLocale = body.locale === 'en' ? 'en' : 'vi';

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

    // An existing account's own saved locale wins for a login code; a
    // brand-new signup has no profile row yet, so fall back to whatever
    // language the client was showing when they requested it.
    let locale = requestedLocale;
    if (linkType === 'magiclink' && authUserId) {
      const { data: existingProfile } = await admin.from('profiles').select('locale').eq('id', authUserId).maybeSingle();
      if (existingProfile?.locale) locale = existingProfile.locale === 'en' ? 'en' : 'vi';
    }

    const subject = linkType === 'signup'
      ? t(locale, 'Mã đăng ký banbe của bạn', 'Your banbe sign-up code')
      : t(locale, 'Mã đăng nhập banbe của bạn', 'Your banbe sign-in code');
    const heading = t(locale, 'Nhập mã này để tiếp tục', 'Enter this code to continue');
    const paragraphs = [
      linkType === 'signup'
        ? t(locale, 'Nhập mã bên dưới trong ứng dụng banbe để hoàn tất đăng ký.', 'Enter the code below in the banbe app to finish creating your account.')
        : t(locale, 'Nhập mã bên dưới trong ứng dụng banbe để đăng nhập.', 'Enter the code below in the banbe app to sign in.'),
    ];
    const footNote = t(
      locale,
      'Mã hết hạn sau ít phút. Nếu bạn không yêu cầu email này, bạn có thể bỏ qua nó.',
      "This code expires in a few minutes. If you didn't request this, you can safely ignore this email."
    );

    try {
      await sendWithGmail({
        to: email,
        subject,
        text: renderEmailText({ heading, paragraphs, code, footNote }),
        html: renderEmail({ preheader: subject, eyebrow: subject, heading, paragraphs, code, footNote }),
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
