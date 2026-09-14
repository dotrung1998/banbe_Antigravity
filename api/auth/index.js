import { randomBytes } from 'node:crypto';
import { getMissingEmailVariables, sendWithGmail } from '../_lib/email.js';
import { getSupabaseAdmin, resolveAuthUserId, linkRegistration, getRedirectUrl } from '../_lib/authLookup.js';
import { renderEmail, renderEmailText } from '../_lib/emailTemplate.js';

// Consolidated dispatcher for the /api/auth/* trio, folded together to fit
// the Hobby-plan 12-function cap (see api/notify.js for the same treatment
// of the /api/notify-* set). Each branch is the original standalone file's
// handler body, unchanged except for being a function instead of the
// default export — dispatch is purely `body.type`.

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function t(locale, vi, en) {
  return locale === 'en' ? en : vi;
}

// ---- was api/auth/send-email-code.js ----
async function handleSendEmailCode(req, res, admin, body) {
  const email = getText(body.email).toLowerCase();
  const mode = getText(body.mode).toLowerCase();
  const displayName = getText(body.displayName).slice(0, 60);
  const requestedLocale = body.locale === 'en' ? 'en' : 'vi';

  if (!EMAIL_PATTERN.test(email)) return res.status(400).json({ error: 'VALID_EMAIL_REQUIRED' });
  if (mode !== 'signup' && mode !== 'login') return res.status(400).json({ error: 'VALID_AUTH_MODE_REQUIRED' });
  if (mode === 'signup' && !displayName) return res.status(400).json({ error: 'VALID_NAME_REQUIRED' });

  const { userId: authUserId, resolved, sources } = await resolveAuthUserId(admin, email);

  if (!resolved) {
    console.error('Account lookup could not be completed:', sources);
    return res.status(502).json({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' });
  }

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
      linkRequest.password = randomBytes(32).toString('base64url');
      linkRequest.options.data = { display_name: displayName };
    }

    const { data, error } = await admin.auth.admin.generateLink(linkRequest);
    const code = data?.properties?.email_otp;

    if (error || !code) {
      console.error('Supabase OTP generation failed:', error);
      return res.status(502).json({ error: 'AUTH_LINK_GENERATION_FAILED' });
    }

    if (linkType === 'signup') await linkRegistration(admin, email, data?.user?.id || null);

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

// ---- was api/auth/send-password-reset.js ----
async function handleSendPasswordReset(req, res, admin, body) {
  const email = getText(body.email).toLowerCase();
  if (!EMAIL_PATTERN.test(email)) return res.status(400).json({ error: 'VALID_EMAIL_REQUIRED' });

  const { userId: authUserId, resolved, sources } = await resolveAuthUserId(admin, email);
  if (!resolved) {
    console.error('Account lookup could not be completed:', sources);
    return res.status(502).json({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' });
  }

  if (!authUserId) return res.status(200).json({ sent: true });
  await linkRegistration(admin, email, authUserId);

  try {
    const { data: profile } = await admin.from('profiles').select('locale').eq('id', authUserId).maybeSingle();
    const locale = profile?.locale === 'en' ? 'en' : 'vi';

    const { data, error } = await admin.auth.admin.generateLink({
      type: 'recovery',
      email,
      options: { redirectTo: getRedirectUrl(req) },
    });

    if (error || !data?.properties?.action_link) {
      console.error('Supabase recovery link generation failed:', error);
      return res.status(502).json({ error: 'AUTH_LINK_GENERATION_FAILED' });
    }

    const actionLink = data.properties.action_link;
    const subject = t(locale, 'Đặt lại mật khẩu banbe của bạn', 'Reset your banbe password');
    const heading = t(locale, 'Chọn mật khẩu mới', 'Choose a new password');
    const paragraphs = [
      t(
        locale,
        'Bấm nút bên dưới để chọn mật khẩu mới cho tài khoản banbe của bạn.',
        'Tap the button below to choose a new password for your banbe account.'
      ),
    ];
    const footNote = t(
      locale,
      'Nếu bạn không yêu cầu đặt lại mật khẩu, bạn có thể bỏ qua email này — mật khẩu hiện tại của bạn vẫn giữ nguyên.',
      "If you didn't request a password reset, you can ignore this email — your current password stays unchanged."
    );

    try {
      await sendWithGmail({
        to: email,
        subject,
        text: renderEmailText({ heading, paragraphs, cta: { label: t(locale, 'Đặt mật khẩu mới', 'Choose a new password'), href: actionLink }, footNote }),
        html: renderEmail({
          preheader: subject,
          eyebrow: t(locale, 'Đặt lại mật khẩu', 'Password reset'),
          heading,
          paragraphs,
          cta: { label: t(locale, 'Đặt mật khẩu mới', 'Choose a new password'), href: actionLink },
          footNote,
        }),
      });
    } catch (error) {
      console.error('Gmail auth email delivery failed:', error);
      return res.status(502).json({ error: 'AUTH_EMAIL_DELIVERY_FAILED' });
    }

    return res.status(200).json({ sent: true });
  } catch (error) {
    console.error('Password reset request failed:', error);
    return res.status(502).json({ error: 'AUTH_EMAIL_REQUEST_FAILED' });
  }
}

// ---- was api/auth/signup-password.js ----
async function handleSignupPassword(req, res, admin, body) {
  const email = getText(body.email).toLowerCase();
  const password = typeof body.password === 'string' ? body.password : '';
  const displayName = getText(body.displayName).slice(0, 60);
  const locale = body.locale === 'en' ? 'en' : 'vi';

  if (!EMAIL_PATTERN.test(email)) return res.status(400).json({ error: 'VALID_EMAIL_REQUIRED' });
  if (!displayName) return res.status(400).json({ error: 'VALID_NAME_REQUIRED' });
  if (password.length < 8) return res.status(400).json({ error: 'VALID_PASSWORD_REQUIRED' });

  const { userId: authUserId, resolved, sources } = await resolveAuthUserId(admin, email);
  if (!resolved) {
    console.error('Account lookup could not be completed:', sources);
    return res.status(502).json({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' });
  }
  if (authUserId) {
    await linkRegistration(admin, email, authUserId);
    return res.status(409).json({ error: 'AUTH_ACCOUNT_EXISTS' });
  }

  try {
    const { data, error } = await admin.auth.admin.generateLink({
      type: 'signup',
      email,
      password,
      options: { data: { display_name: displayName } },
    });
    const code = data?.properties?.email_otp;

    if (error || !code) {
      console.error('Supabase signup OTP generation failed:', error);
      return res.status(502).json({ error: 'AUTH_LINK_GENERATION_FAILED' });
    }

    await linkRegistration(admin, email, data?.user?.id || null);

    const subject = t(locale, 'Xác nhận tài khoản banbe của bạn', 'Confirm your banbe account');
    const heading = t(locale, 'Nhập mã này để tiếp tục', 'Enter this code to continue');
    const paragraphs = [
      t(locale, 'Nhập mã bên dưới trong ứng dụng banbe để hoàn tất đăng ký.', 'Enter the code below in the banbe app to finish creating your account.'),
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
    console.error('Signup password request failed:', error);
    return res.status(502).json({ error: 'AUTH_EMAIL_REQUEST_FAILED' });
  }
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

  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const type = getText(body.type);

  switch (type) {
    case 'send_email_code': return handleSendEmailCode(req, res, admin, body);
    case 'send_password_reset': return handleSendPasswordReset(req, res, admin, body);
    case 'signup_password': return handleSignupPassword(req, res, admin, body);
    default: return res.status(400).json({ error: 'VALID_AUTH_TYPE_REQUIRED' });
  }
}
