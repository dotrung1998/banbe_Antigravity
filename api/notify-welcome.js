import { createClient } from '@supabase/supabase-js';
import { getMissingEmailVariables, sendWithGmail } from './_lib/email.js';
import { getRedirectUrl } from './_lib/authLookup.js';
import { renderEmail, renderEmailText } from './_lib/emailTemplate.js';

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) return null;
  return createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
}

function t(locale, vi, en) {
  return locale === 'en' ? en : vi;
}

// The one email in the set that's meant to be shared, not just read: sent
// once, right after a brand-new account's first successful sign-in (see
// GocContext's verifyEmailCode). It introduces the account's own referral
// link — every profile gets a code automatically (migration 023) — rather
// than a separate "here's your referral code" email nobody asked for.
//
// Re-derives everything from the caller's own verified session: the email
// address, display name, locale and referral code all come from the
// database keyed off the bearer token's user id, never from the request
// body, so this can't be used to email an arbitrary address.
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

  const token = getText((req.headers.authorization || '').replace(/^Bearer\s+/i, ''));
  if (!token) return res.status(401).json({ error: 'AUTH_REQUIRED' });

  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData?.user) return res.status(401).json({ error: 'AUTH_REQUIRED' });
  if (!userData.user.email) return res.status(200).json({ sent: 0 });

  try {
    const { data: profile, error: profileError } = await admin
      .from('profiles')
      .select('display_name, locale, referral_code')
      .eq('id', userData.user.id)
      .maybeSingle();
    if (profileError) throw profileError;
    if (!profile?.referral_code) return res.status(200).json({ sent: 0 });

    const locale = profile.locale === 'en' ? 'en' : 'vi';
    // Only ever used inside `heading`, which renderEmail()/renderEmailText()
    // escape as a whole — pre-escaping here would double-escape it.
    const name = (profile.display_name || '').trim();
    const referralLink = `${getRedirectUrl(req)}/?ref=${profile.referral_code}`;

    const subject = t(locale, 'Chào mừng bạn đến với banbe', 'Welcome to banbe');
    const heading = t(
      locale,
      name ? `Chào ${name}, tài khoản của bạn đã sẵn sàng` : 'Tài khoản của bạn đã sẵn sàng',
      name ? `Welcome, ${name} — you're all set` : "You're all set"
    );
    const paragraphs = [
      t(
        locale,
        'Từ giờ mỗi tuần sẽ có vài buổi hay ho dành cho bạn — supper club, phòng tranh, gig nhạc nhỏ. Không xếp hạng, không quảng cáo, không lướt vô tận.',
        "Every week from here on, there'll be a few good things happening near you — supper clubs, small galleries, tucked-away gigs. No ratings, no ads, no endless scrolling."
      ),
      t(
        locale,
        'banbe vui hơn khi có bạn bè cùng tham gia. Chia sẻ liên kết dưới đây — khi ai đó tham gia qua đó, bạn sẽ là người đã mời họ.',
        "banbe is better with people you know. Share your link below — anyone who joins through it, you'll be the one who brought them in."
      ),
    ];

    const html = renderEmail({
      preheader: t(locale, 'Tài khoản của bạn đã sẵn sàng.', "Your account is ready."),
      eyebrow: t(locale, 'Chào mừng', 'Welcome'),
      heading,
      paragraphs,
      cta: { label: t(locale, 'Chia sẻ banbe với bạn bè', 'Share banbe with a friend'), href: referralLink },
    });
    const text = renderEmailText({
      heading,
      paragraphs,
      cta: { label: t(locale, 'Chia sẻ banbe với bạn bè', 'Share banbe with a friend'), href: referralLink },
    });

    await sendWithGmail({ to: userData.user.email, subject, text, html });
    return res.status(200).json({ sent: 1 });
  } catch (error) {
    console.error('Welcome email failed:', error);
    return res.status(502).json({ error: 'NOTIFY_FAILED' });
  }
}
