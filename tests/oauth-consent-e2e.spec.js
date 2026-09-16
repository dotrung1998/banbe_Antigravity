// @ts-check
import { test, expect } from '@playwright/test';
import { hasServiceRole, adminClient, createTestUser, signIn, cleanup } from './e2e/setup.mjs';

// Real-backend coverage for note 10's OAuth consent fix. There is no real
// Google/Facebook app configured for this project yet (see
// .claude/notes/10-oauth-login.md's Task 4 checklist), so an actual
// end-to-end OAuth redirect can't be driven here — instead, this simulates
// exactly what a real Google/Facebook sign-in produces: a session whose
// user.app_metadata.provider is a non-'email' value, built via the admin
// API the same way tests/global-setup.js already builds a real signed-in
// storageState. That's the one thing this repo's own auth code actually
// branches on (GocContext.jsx's syncUser(), AppState+Data.swift's
// applySession()), so faking it this way exercises the real client-side
// routing logic against a real session and a real database row — nothing
// about the consent gate itself is mocked.
test.describe('OAuth consent gate (real backend)', () => {
  test.skip(!hasServiceRole(), 'Needs SUPABASE_SERVICE_ROLE_KEY — see tests/e2e/loadEnv.mjs');

  const projectRef = new URL(process.env.VITE_SUPABASE_URL).hostname.split('.')[0];
  const storageKeyName = `sb-${projectRef}-auth-token`;

  /** Builds a Playwright storageState object from a real Supabase session. */
  function storageStateFor(session) {
    return {
      cookies: [],
      origins: [{
        origin: 'http://localhost:5173',
        localStorage: [{
          name: storageKeyName,
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
  }

  /** Tags a real test user's auth.users row as if it signed up via `provider`
   *  (Google/Facebook), then mints a fresh session so the JWT reflects it —
   *  app_metadata is embedded in the session token at mint time, so the
   *  order (patch, then sign in) matters. */
  async function createOAuthLikeUser(admin, label, provider) {
    const { email, password, userId } = await createTestUser(admin, label);
    const { error } = await admin.auth.admin.updateUserById(userId, {
      app_metadata: { provider, providers: [provider] },
    });
    if (error) throw error;
    // Same prefs_saved/locale/theme forcing tests/global-setup.js already
    // does for the shared fast-suite account — skips the language/theme
    // pickers so this lands straight on the post-auth decision instead of
    // racing setupToHome()-style clicks that aren't the point of this test.
    await admin.from('profiles').update({ locale: 'vi', theme: 'light', prefs_saved: true }).eq('id', userId);
    const { session } = await signIn(email, password);
    return { email, userId, session };
  }

  test('a returning OAuth user reaches Home directly — no consent screen, never signed out', async ({ browser }) => {
    const admin = adminClient();
    let userId;
    try {
      const created = await createOAuthLikeUser(admin, 'oauth-returning', 'google');
      userId = created.userId;
      // The whole point of "returning": policy_accepted_at is already set,
      // exactly as it would be for any account that finished signing up
      // before. Set explicitly rather than relying on a default so this
      // test doesn't depend on migration history.
      await admin.from('profiles').update({
        policy_accepted_at: new Date().toISOString(), policy_version: '2026-09-18',
      }).eq('id', userId);

      const context = await browser.newContext({ storageState: storageStateFor(created.session) });
      const page = await context.newPage();
      await page.goto('/');

      // Straight to Home — no Policy screen, no bounce back to Login.
      await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 10000 });
      await expect(page.locator('[data-screen-label="Policy"]')).toHaveCount(0);
      await expect(page.locator('[data-screen-label="Login"]')).toHaveCount(0);

      await context.close();
    } finally {
      if (userId) await cleanup(admin, { userIds: [userId] });
    }
  });

  test('a brand-new OAuth signup hits the consent gate exactly once, then reaches Home', async ({ browser }) => {
    const admin = adminClient();
    let userId;
    try {
      const created = await createOAuthLikeUser(admin, 'oauth-new', 'facebook');
      userId = created.userId;
      // Brand-new: policy_accepted_at is left at its default NULL.

      const context = await browser.newContext({ storageState: storageStateFor(created.session) });
      const page = await context.newPage();
      await page.goto('/');

      // Routed to the mandatory Policy gate, not signed out and not
      // silently let through to Home.
      await expect(page.locator('[data-screen-label="Policy"]')).toBeVisible({ timeout: 10000 });
      await expect(page.getByTestId('policy-gate-bar')).toBeVisible();
      await expect(page.locator('[data-screen-label="Login"]')).toHaveCount(0);

      await page.getByTestId('policy-gate-accept').click();

      // Accepting stamps consent for real and continues straight to Home —
      // no re-visit to Policy needed, exactly once.
      await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 10000 });

      const { data: profile } = await admin.from('profiles').select('policy_accepted_at').eq('id', userId).single();
      expect(profile.policy_accepted_at).not.toBeNull();

      // Reloading afterward must not show the gate again — same as any
      // other already-consented account.
      await page.reload();
      await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 10000 });
      await expect(page.locator('[data-screen-label="Policy"]')).toHaveCount(0);

      await context.close();
    } finally {
      if (userId) await cleanup(admin, { userIds: [userId] });
    }
  });
});
