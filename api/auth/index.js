import { randomBytes } from 'node:crypto';
import { getMissingEmailVariables, sendWithGmail } from '../_lib/email.js';
import { getSupabaseAdmin, resolveAuthUserId, linkRegistration, getRedirectUrl } from '../_lib/authLookup.js';
import { findOpenEventsBlockingDeletion } from '../_lib/accountDeletion.js';
import { createClient } from '@supabase/supabase-js';
import { signReauthProof, verifyReauthProof } from '../_lib/reauthProof.js';
import { gatherOrganizerFacts, planOrganizerCleanup, applyOrganizerCleanup } from '../_lib/organizerCleanup.js';
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

  // 'respond' (survey-respondent lightweight verification, task 3 of the
  // survey-sharing pass) deliberately does NOT pre-commit to signup/login —
  // a signed-out visitor answering a survey has no way to know in advance
  // whether their email already has a banbe account, and asking them to
  // guess (then getting a 404/409) would be a confusing dead end for a flow
  // that's supposed to be lightweight. It auto-detects, exactly like the
  // signup/login branches below already do internally — the ONLY behavior
  // difference is skipping the two mismatch guards that assume the caller
  // already knows which case they're in.
  const isRespondMode = mode === 'respond';
  if (!EMAIL_PATTERN.test(email)) return res.status(400).json({ error: 'VALID_EMAIL_REQUIRED' });
  if (!isRespondMode && mode !== 'signup' && mode !== 'login') return res.status(400).json({ error: 'VALID_AUTH_MODE_REQUIRED' });
  if (mode === 'signup' && !displayName) return res.status(400).json({ error: 'VALID_NAME_REQUIRED' });

  const { userId: authUserId, resolved, sources } = await resolveAuthUserId(admin, email);

  if (!resolved) {
    console.error('Account lookup could not be completed:', sources);
    return res.status(502).json({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' });
  }

  if (authUserId) await linkRegistration(admin, email, authUserId);

  if (!isRespondMode) {
    if (mode === 'login' && !authUserId) {
      return res.status(404).json({ error: 'AUTH_ACCOUNT_NOT_FOUND' });
    }
    if (mode === 'signup' && authUserId) {
      return res.status(409).json({ error: 'AUTH_ACCOUNT_EXISTS' });
    }
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

    // `isNewAccount` lets a caller that doesn't pre-know signup vs login
    // (mode: 'respond') disclose accurately which one just happened, before
    // the respondent types the code — task's own "disclose a new identity
    // accurately before confirmation, never silently" requirement. Harmless
    // to include for the ordinary signup/login modes too (the client
    // already knows which mode it asked for, so it simply doesn't read it).
    return res.status(200).json({ sent: true, isNewAccount: !authUserId });
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
      'Nếu bạn không yêu cầu đặt lại mật khẩu, bạn có thể bỏ qua email này. Mật khẩu hiện tại của bạn vẫn giữ nguyên.',
      "If you didn't request a password reset, you can ignore this email. Your current password stays unchanged."
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

// ---- Account deletion (Task 2, Account/Settings pass) ----
// See supabase/migrations/20261023000111_111_account_deletion_requests.sql
// for the full data-handling writeup (hard-deleted vs anonymized vs
// blocked). This is a recorded, step-tracked workflow, not a single atomic
// call — `account_deletion_requests` is updated after each step so a
// partial failure is inspectable/retryable, never silently reported as a
// full success.
//
// SAFETY (per this ticket's own explicit instruction): this code path is
// written and was verified by reading it back carefully, but this session
// never invoked it against any real account, including a throwaway one —
// no isolated fixture/staging environment was available. It is reported as
// "written, not exercised end-to-end."
async function markStep(admin, requestId, stepKey, value) {
  // Best-effort — a failure to WRITE progress must never mask the actual
  // step's own success/failure being returned to the caller, so this never
  // throws upward.
  try {
    const { data } = await admin.from('account_deletion_requests').select('steps').eq('id', requestId).maybeSingle();
    const steps = { ...(data?.steps || {}), [stepKey]: value };
    await admin.from('account_deletion_requests').update({ steps }).eq('id', requestId);
  } catch (error) {
    console.warn('account_deletion_requests step write failed (non-fatal):', stepKey, error);
  }
}

// Re-authentication for account deletion. Two ways, both checked on the server for the CALLER's own
// account, and neither replaces the caller's real session (a new session would trigger the account
// gate's date-of-birth re-confirmation and interrupt the deletion flow):
//   - { dob: 'YYYY-MM-DD' }  the account gate's own confirm_date_of_birth RPC, run as the caller
//                            (rate limited and locked out after 5 wrong answers by the database).
//   - { code }               the emailed login code, verified on a throwaway client.
// Success returns a short-lived proof that delete_account requires.
async function handleVerifyReauth(req, res, admin, body) {
  const token = getText((req.headers.authorization || '').replace(/^Bearer\s+/i, ''));
  if (!token) return res.status(401).json({ error: 'AUTH_REQUIRED' });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData?.user) return res.status(401).json({ error: 'AUTH_REQUIRED' });
  const { id: userId, email } = userData.user;
  const dob = getText(body.dob);
  const code = getText(body.code);

  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY;
  const proof = () => res.status(200).json({ proof: signReauthProof(userId, process.env.SUPABASE_SERVICE_ROLE_KEY) });

  if (dob) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dob)) return res.status(400).json({ error: 'REAUTH_DOB_INVALID' });
    // PostgREST takes the ROLE from the caller's bearer token; `apikey` only has to be a valid project key.
    // So when the anon key isn't set on the server, the service key works as the gateway key and the RPC
    // still runs as the caller (auth.uid() = caller).
    const gatewayKey = anonKey || process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!url || !gatewayKey) return res.status(503).json({ error: 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED' });
    try {
      const r = await fetch(`${url}/rest/v1/rpc/confirm_date_of_birth`, {
        method: 'POST',
        headers: { apikey: gatewayKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_dob: dob }),
      });
      const result = await r.json().catch(() => null);
      if (!r.ok || !result) return res.status(502).json({ error: 'REAUTH_SERVER_ERROR' });
      if (result.success === true) {
        // The account has no date of birth on file, so there is nothing to compare against.
        if (result.not_required) return res.status(400).json({ error: 'REAUTH_DOB_NOT_SET' });
        return proof();
      }
      if (result.error === 'LOCKED') return res.status(429).json({ error: 'REAUTH_DOB_LOCKED', retryAfter: result.retry_after_seconds });
      if (result.error === 'INCORRECT') return res.status(400).json({ error: 'REAUTH_DOB_INCORRECT', attemptsLeft: result.attempts_left });
      return res.status(400).json({ error: 'REAUTH_DOB_FAILED' });
    } catch (error) {
      console.error('verify_reauth (dob) failed:', error);
      return res.status(500).json({ error: 'REAUTH_SERVER_ERROR' });
    }
  }

  if (!email) return res.status(400).json({ error: 'REAUTH_EMAIL_REQUIRED' });
  if (!code) return res.status(400).json({ error: 'REAUTH_CODE_REQUIRED' });
  // Prefer the anon key; fall back to the service key (the client is throwaway and never persists).
  const key = anonKey || process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return res.status(503).json({ error: 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED' });
  try {
    const throwaway = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
    const { data, error } = await throwaway.auth.verifyOtp({ email, token: code, type: 'email' });
    if (error || data?.user?.id !== userId) {
      if (error) console.warn('verify_reauth: verifyOtp rejected:', error.status, error.code, error.message);
      return res.status(400).json({ error: 'REAUTH_CODE_INVALID' });
    }
    // Drop ONLY the session that verification just created (scope 'local'); the default global scope
    // would revoke every session of the account, including the caller's own.
    await throwaway.auth.signOut({ scope: 'local' }).catch(() => {});
    return proof();
  } catch (error) {
    console.error('verify_reauth failed:', error);
    return res.status(500).json({ error: 'REAUTH_SERVER_ERROR' });
  }
}

async function handleDeleteAccount(req, res, admin, body) {
  // The user id to delete comes ONLY from the caller's own verified bearer
  // token — never from a client-supplied body field. This is the one new
  // "verify the caller's OWN session, then act on their own row" pattern
  // this dispatcher didn't already have (every other action here resolves
  // a target by admin lookup, not by the caller's own identity).
  const token = getText((req.headers.authorization || '').replace(/^Bearer\s+/i, ''));
  if (!token) return res.status(401).json({ error: 'AUTH_REQUIRED' });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData?.user) return res.status(401).json({ error: 'AUTH_REQUIRED' });
  const userId = userData.user.id;

  // Re-authentication proof from verify_reauth (below). Required server-side, not just a client flag.
  if (!verifyReauthProof(getText(body.reauthProof), userId, process.env.SUPABASE_SERVICE_ROLE_KEY)) {
    return res.status(403).json({ error: 'REAUTH_REQUIRED' });
  }

  // Open-event refusal — matches Policy's own "refused while you still own
  // an open event" claim. "Open" = a currently live or pending-review
  // event on any organizer this user owns (owner_id OR user_id — both are
  // real ownership links per the schema, migration 001). A draft/cancelled/
  // ended event never blocks.
  const { data: ownedOrgs, error: orgError } = await admin
    .from('organizers')
    .select('id, name')
    .or(`owner_id.eq.${userId},user_id.eq.${userId}`);
  if (orgError) {
    console.error('Account deletion: organizer ownership lookup failed:', orgError);
    return res.status(502).json({ error: 'ACCOUNT_DELETION_LOOKUP_FAILED' });
  }
  const orgIds = (ownedOrgs || []).map(o => o.id);
  if (orgIds.length) {
    // Fetch every non-terminal-status candidate and let the pure function
    // decide what actually blocks — see api/_lib/accountDeletion.js
    // (unit-tested in tests/unit/account-deletion-open-event.test.mjs),
    // rather than re-encoding the "which statuses count as open" rule
    // twice (once in this query's own `.in(...)`, once conceptually).
    const { data: candidateEvents, error: eventsError } = await admin
      .from('events')
      .select('id, name, status, starts_at')
      .in('organizer_id', orgIds);
    if (eventsError) {
      console.error('Account deletion: open-event lookup failed:', eventsError);
      return res.status(502).json({ error: 'ACCOUNT_DELETION_LOOKUP_FAILED' });
    }
    const openEvents = findOpenEventsBlockingDeletion(candidateEvents);
    if (openEvents.length) {
      return res.status(409).json({
        error: 'ACCOUNT_DELETION_BLOCKED_OPEN_EVENT',
        openEvents: openEvents.map(e => ({ id: e.id, name: e.name, status: e.status })),
      });
    }
  }

  // Record the attempt BEFORE doing anything destructive — a row always
  // exists even if the very next step throws.
  const { data: reqRow, error: insertError } = await admin
    .from('account_deletion_requests')
    .insert({
      user_id: userId,
      status: 'processing',
      reason_code: getText(body.reasonCode) || null,
      reason_text: getText(body.reasonText).slice(0, 500) || null,
    })
    .select('id')
    .single();
  if (insertError || !reqRow) {
    console.error('Account deletion: could not create tracking row:', insertError);
    return res.status(502).json({ error: 'ACCOUNT_DELETION_INIT_FAILED' });
  }
  const requestId = reqRow.id;

  // Step 1 — Storage cleanup for files this user unambiguously owns by a
  // `<user_id>/...` path convention: the `avatars` bucket (migration 079).
  // KNOWN LIMITATION, documented here rather than silently skipped:
  // `payment-documents`/`pay-proof`/`organizer-photos` are keyed by
  // booking id/organizer id, not user id, so this pass does not enumerate
  // and remove those — they are left as orphaned private objects (never
  // publicly served, since those buckets are already private + RLS-scoped
  // to the specific booking/organizer). A future pass could resolve this
  // user's own booking ids first and delete matching `payment-documents`
  // paths; not done here to keep this endpoint's blast radius reviewable.
  try {
    const { data: avatarFiles } = await admin.storage.from('avatars').list(userId);
    if (avatarFiles?.length) {
      await admin.storage.from('avatars').remove(avatarFiles.map(f => `${userId}/${f.name}`));
    }
    // Keychain custom art (private bucket, `<user_id>/...`); rows cascade with the account.
    const { data: keychainFiles } = await admin.storage.from('keychain-art').list(userId);
    if (keychainFiles?.length) {
      await admin.storage.from('keychain-art').remove(keychainFiles.map(f => `${userId}/${f.name}`));
    }
    await markStep(admin, requestId, 'avatar_storage', 'ok');
  } catch (error) {
    // Non-fatal — a leftover avatar file is not a reason to abort deleting
    // the account itself, but it IS recorded so it can be found/cleaned up
    // later rather than silently vanishing from view.
    await markStep(admin, requestId, 'avatar_storage', `failed: ${error?.message || error}`);
  }

  // Step 1b — host profile. Deleting the auth user would leave each owned organizer behind with no owner
  // but still carrying its name, intro, photo, bank/MoMo and contact details (and Storage objects are never
  // cascaded). Remove what nothing depends on; anonymize what guests' records still reference. Must run
  // BEFORE deleteUser, which is what clears the ownership link. A database failure aborts so the request
  // can be retried; file-removal problems are recorded, not fatal.
  try {
    const summary = [];
    for (const org of ownedOrgs || []) {
      const facts = await gatherOrganizerFacts(admin, org.id, userId);
      const action = planOrganizerCleanup(facts);
      const result = await applyOrganizerCleanup(admin, org.id, action);
      summary.push(`${org.id}:${action}${result.filesRemoved ? `(${result.filesRemoved} files)` : ''}${result.notes.length ? `[${result.notes.join('; ')}]` : ''}`);
    }
    await markStep(admin, requestId, 'organizer_cleanup', summary.length ? `ok: ${summary.join(', ')}` : 'ok: none');
  } catch (error) {
    await markStep(admin, requestId, 'organizer_cleanup', `failed: ${error?.message || error}`);
    await admin.from('account_deletion_requests').update({ status: 'failed', error_detail: `organizer_cleanup: ${error?.message || error}` }).eq('id', requestId);
    console.error('Account deletion: organizer cleanup failed:', error);
    return res.status(502).json({ error: 'ACCOUNT_DELETION_ORGANIZER_CLEANUP_FAILED' });
  }

  // Step 2 — the actual account deletion. `profiles.id REFERENCES
  // auth.users(id) ON DELETE CASCADE` means this one call is what cascades
  // the profile row, which in turn cascades/detaches everything else per
  // each table's own FK rule (see the migration's own doc comment for the
  // full table).
  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    await markStep(admin, requestId, 'auth_delete', `failed: ${deleteError.message || deleteError}`);
    await admin.from('account_deletion_requests').update({
      status: 'failed',
      error_detail: deleteError.message || String(deleteError),
    }).eq('id', requestId);
    console.error('Account deletion: auth.admin.deleteUser failed:', deleteError);
    return res.status(502).json({ error: 'ACCOUNT_DELETION_FAILED', requestId });
  }
  await markStep(admin, requestId, 'auth_delete', 'ok');

  await admin.from('account_deletion_requests').update({
    status: 'done',
    completed_at: new Date().toISOString(),
  }).eq('id', requestId);

  return res.status(200).json({ deleted: true, requestId });
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }

  const admin = getSupabaseAdmin();
  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const type = getText(body.type);

  // Account deletion needs no outbound email config at all — checked
  // separately (only the service-role client) so a missing Gmail
  // credential (unrelated to this action) never blocks it.
  if (type === 'delete_account') {
    if (!admin) return res.status(503).json({ error: 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED', missing: ['SUPABASE_SERVICE_ROLE_KEY'] });
    return handleDeleteAccount(req, res, admin, body);
  }
  if (type === 'verify_reauth') {
    if (!admin) return res.status(503).json({ error: 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED', missing: ['SUPABASE_SERVICE_ROLE_KEY'] });
    return handleVerifyReauth(req, res, admin, body);
  }

  const missing = [
    ...getMissingEmailVariables(),
    !admin && 'SUPABASE_SERVICE_ROLE_KEY',
  ].filter(Boolean);
  if (missing.length) {
    return res.status(503).json({ error: 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED', missing });
  }

  switch (type) {
    case 'send_email_code': return handleSendEmailCode(req, res, admin, body);
    case 'send_password_reset': return handleSendPasswordReset(req, res, admin, body);
    case 'signup_password': return handleSignupPassword(req, res, admin, body);
    default: return res.status(400).json({ error: 'VALID_AUTH_TYPE_REQUIRED' });
  }
}
