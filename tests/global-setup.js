// Runs once before the whole Playwright suite. Task 1 (mandatory login,
// this session) means Home — and every other screen — is unreachable
// signed-out now, which the ~54 pre-existing "fast" tests never accounted
// for: they were written assuming a signed-out visitor could browse Home
// freely, and used that as their common starting point regardless of what
// each test actually exercised (event browsing, Account preferences,
// payment screens, etc. — none of it actually about auth).
//
// Rather than rewrite every one of those tests to sign in individually
// (slow, and out of scope for the pass that introduced the gate), this
// creates one persistent, reused-across-runs test account via the
// Supabase admin API (tests/e2e/setup.mjs's pattern) and signs in for
// real, then saves the resulting session as a Playwright storageState —
// so every test's browser context starts already authenticated, the same
// way tests/e2e/setup.mjs's real-backend suites already do, just paid for
// once here instead of per test.
//
// Trade-off, disclosed rather than silent: the "fast" suite now depends on
// SUPABASE_SERVICE_ROLE_KEY being resolvable (via .env.local/.env — see
// tests/e2e/loadEnv.mjs) the same way the real-backend suites already do.
// It previously needed no backend credentials at all. If the key isn't
// available, this logs a warning and leaves storageState unwritten — every
// test then runs signed out and fails at the login gate, exactly as they
// would without this file, rather than the whole suite refusing to start.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { hasServiceRole, adminClient, signIn } from './e2e/setup.mjs';

const STORAGE_STATE_PATH = new URL('../playwright/.auth/user.json', import.meta.url).pathname;
// Deliberately NOT setup.mjs's createTestUser()/aliasEmail() — those bake a
// fresh Date.now()-based run id into the address on purpose, for
// disposable per-test accounts. This one needs a truly fixed address
// (recreated, never re-timestamped) so the lookup below actually finds the
// SAME account on the next run instead of silently piling up a new one
// every time the suite runs.
const PERSISTENT_TEST_EMAIL = 'doqanh0906+banbe-fast-suite-shared@gmail.com';
const PERSISTENT_TEST_PASSWORD = 'BanbeE2e!Test1234'; // matches setup.mjs's TEST_PASSWORD convention
const EMPTY_STORAGE_STATE = JSON.stringify({ cookies: [], origins: [] }, null, 2);

export default async function globalSetup() {
  // playwright/.auth/ is gitignored (a session token doesn't belong in git)
  // — a fresh checkout has neither the directory nor a placeholder file,
  // and playwright.config.js's `storageState` option errors on a path that
  // doesn't exist at all, so this always has to leave *something* valid
  // there before returning, signed-in or not.
  mkdirSync(dirname(STORAGE_STATE_PATH), { recursive: true });

  if (!hasServiceRole()) {
    writeFileSync(STORAGE_STATE_PATH, EMPTY_STORAGE_STATE);
    console.warn(
      '[global-setup] SUPABASE_SERVICE_ROLE_KEY not resolvable — skipping the ' +
      'fast suite\'s shared sign-in. Every test will run signed out and fail at ' +
      'the Task 1 login gate. See tests/global-setup.js.'
    );
    return;
  }

  const admin = adminClient();
  // Reused across runs, not recreated every time — look up the fixed
  // address first (same registry lookup setup.mjs's own
  // findAuthUserIdByEmail uses), reset its password so this run's sign-in
  // is guaranteed to work regardless of history, and only fall back to
  // actually creating it the very first time this ever runs.
  const { data: existing } = await admin.from('email_registrations')
    .select('auth_user_id').eq('email', PERSISTENT_TEST_EMAIL).maybeSingle();
  if (existing?.auth_user_id) {
    await admin.auth.admin.updateUserById(existing.auth_user_id, { password: PERSISTENT_TEST_PASSWORD });
  } else {
    const { error } = await admin.auth.admin.createUser({
      email: PERSISTENT_TEST_EMAIL, password: PERSISTENT_TEST_PASSWORD, email_confirm: true,
      user_metadata: { display_name: 'Fast Suite Shared Test User' },
    });
    if (error) throw error;
  }

  // Deterministic screen sequence for every test that reuses this account:
  // GocContext.jsx's syncUser() jumps straight to 'home' once it resolves
  // if profile.prefs_saved is already true, regardless of which of
  // splash/langPick/themePick the screen happens to be sitting on at that
  // moment — without this, a freshly (re)created account still has
  // prefs_saved=false the first time any test runs, so whether the
  // language/theme pickers flash by or get skipped depends on a race
  // between that async check and the test's own clicks, which is exactly
  // what made setupToHome() flaky against this shared, already-signed-in
  // account. Setting it once here, up front, removes the race entirely.
  const registryRow = await admin.from('email_registrations').select('auth_user_id').eq('email', PERSISTENT_TEST_EMAIL).single();
  await admin.from('profiles').update({ locale: 'vi', theme: 'light', prefs_saved: true }).eq('id', registryRow.data.auth_user_id);

  const { session } = await signIn(PERSISTENT_TEST_EMAIL, PERSISTENT_TEST_PASSWORD);
  const projectRef = new URL(process.env.VITE_SUPABASE_URL).hostname.split('.')[0];
  const storageKey = `sb-${projectRef}-auth-token`;

  const storageState = {
    cookies: [],
    origins: [{
      origin: 'http://localhost:5173',
      localStorage: [{
        name: storageKey,
        value: JSON.stringify({
          access_token: session.access_token,
          token_type: 'bearer',
          expires_in: session.expires_in,
          expires_at: session.expires_at,
          refresh_token: session.refresh_token,
          user: session.user,
        }),
      }],
    }],
  };
  writeFileSync(STORAGE_STATE_PATH, JSON.stringify(storageState, null, 2));
  console.log(`[global-setup] Signed in as ${PERSISTENT_TEST_EMAIL}, storageState written to ${STORAGE_STATE_PATH}`);
}
