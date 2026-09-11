import { getMissingEmailVariables, sendWithGmail } from '../_lib/email.js';
import { getSupabaseAdmin, resolveAuthUserId, linkRegistration, getRedirectUrl } from '../_lib/authLookup.js';
import { renderEmail, renderEmailText } from '../_lib/emailTemplate.js';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function t(locale, vi, en) {
  return locale === 'en' ? en : vi;
}

// "Automatic" password reset: unlike sign-in/sign-up, this stays a link
// rather than a code — clicking it lands the browser back on the app with
// a Supabase "recovery" session already established (src/lib/supabase.js
// has detectSessionInUrl on; GocContext's onAuthStateChange listens for the
// PASSWORD_RECOVERY event and routes to the reset-password screen), where
// the person sets a new password with supabase.auth.updateUser({ password })
// directly — no code to type in by hand.
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
  if (!EMAIL_PATTERN.test(email)) return res.status(400).json({ error: 'VALID_EMAIL_REQUIRED' });

  const { userId: authUserId, resolved, sources } = await resolveAuthUserId(admin, email);
  if (!resolved) {
    console.error('Account lookup could not be completed:', sources);
    return res.status(502).json({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' });
  }

  // Deliberately the same 200 response whether or not the account exists —
  // a password-reset form is exactly the wrong place to let someone probe
  // which emails have an account. Only actually send the email if one does.
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
