// @ts-check
import { test, expect } from '@playwright/test';

// Note 64: password sign-in morphs the button to a ✓ and hands off exactly once (no "Loading, just a moment…"),
// a failure returns the button with an alert, and onboarding Version 3 starts its tour over the real Home.
// EVERY Supabase request is answered here (a synthetic account and session), so nothing reaches the real backend
// and nothing is written anywhere. Optional screenshots: TOUR_SHOTS=<dir>.
const SHOTS = process.env.TOUR_SHOTS;
const SUPABASE = 'https://ukchdgdnwytretvqjjqu.supabase.co';
const UID = '00000000-0000-4000-8000-0000000064aa';
const json = (body, status = 200) => ({ status, contentType: 'application/json', body: JSON.stringify(body) });
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const exp = Math.floor(Date.now() / 1000) + 3600;
const JWT = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: UID, role: 'authenticated', aud: 'authenticated', exp, email: 'tour@example.test' })}.sig`;
const USER = { id: UID, aud: 'authenticated', role: 'authenticated', email: 'tour@example.test', app_metadata: { provider: 'email' }, user_metadata: {}, created_at: '2026-10-01T00:00:00Z' };
const SESSION = { access_token: JWT, token_type: 'bearer', expires_in: 3600, expires_at: exp, refresh_token: 'r-64', user: USER };
const PROFILE = {
  id: UID, role: 'participant', locale: 'en', theme: 'light', prefs_saved: true, display_name: 'Tour Test', handle: 'tourtest',
  organizer_mode_enabled: false, can_manage_admins: false, muted_notification_kinds: [], interests: [], social_links: [],
  auto_email_documents: false, policy_accepted_at: '2026-10-01T00:00:00Z',
};

test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

/** @param {import('@playwright/test').Page} page */
async function mockSupabase(page, { flags, failLogin = false, calls }) {
  await page.route(`${SUPABASE}/**`, async (r) => {
    const url = new URL(r.request().url());
    const p = url.pathname;
    const accept = r.request().headers().accept || '';
    if (p.endsWith('/auth/v1/token')) {
      if (url.searchParams.get('grant_type') === 'password' && failLogin) {
        return r.fulfill(json({ error: 'invalid_grant', error_description: 'Invalid login credentials' }, 400));
      }
      return r.fulfill(json(SESSION));
    }
    if (p.endsWith('/auth/v1/user')) return r.fulfill(json(USER));
    if (p.startsWith('/auth/v1/')) return r.fulfill({ status: 204, body: '' });
    if (p.startsWith('/rest/v1/rpc/')) {
      const fn = p.split('/').pop();
      calls?.push(fn);
      if (fn === 'get_feature_flags') return r.fulfill(json(flags));
      if (fn === 'account_gate_status') return r.fulfill(json({ ready: true }));
      if (fn === 'get_my_event_preferences') return r.fulfill(json({ success: true, preferences: null, needs_settings_step: false, needs_preferences_step: false }));
      return r.fulfill(json(null));
    }
    if (p.startsWith('/rest/v1/profiles')) return r.fulfill(json(accept.includes('vnd.pgrst.object') ? PROFILE : [PROFILE]));
    if (p.startsWith('/rest/v1/')) return r.fulfill(accept.includes('vnd.pgrst.object') ? json(null, 406) : json([]));
    return r.fulfill({ status: 404, body: '' });
  });
  await page.addInitScript((f) => { try { localStorage.setItem('banbe_feature_flags_v1', JSON.stringify(f)); } catch { /* */ } }, flags);
}

/** @param {import('@playwright/test').Page} page */
async function toLogin(page) {
  await page.goto('/');
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('lang-en').isVisible().catch(() => false)) { await page.getByTestId('lang-en').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('onboarding-continue').isVisible().catch(() => false)) { await page.getByTestId('onboarding-continue').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('welcome-login').isVisible().catch(() => false)) break;
    await page.waitForTimeout(300);
  }
  await page.getByTestId('welcome-login').click();
  await page.getByTestId('login-method-password').click();
  await page.getByTestId('login-email').fill('tour@example.test');
  await page.getByTestId('login-password').fill('not-a-real-password');
}

test('a refused password returns the button with its label and an alert, no ✓', async ({ page }) => {
  await mockSupabase(page, { flags: {}, failLogin: true });
  await toLogin(page);
  const submit = page.getByTestId('login-submit');
  await expect(submit).toHaveRole('button');
  await submit.click();
  await expect(page.getByTestId('login-error')).toHaveAttribute('role', 'alert');
  await expect(submit).toHaveAttribute('data-phase', 'idle');
  await expect(submit).toHaveText('Log in');
  await expect(page.getByTestId('login-submit-check')).toHaveCount(0);
  await expect(page.locator('[data-screen-label="Login"]')).toBeVisible();
});

test('success: ✓ then exactly one hand-off to Home, no loading screen; v3 tour runs and never mutates', async ({ page }) => {
  const calls = [];
  await mockSupabase(page, { flags: { onboarding_v3: true }, calls });
  await toLogin(page);

  // Record every screen the app shows from here on, and whether the gate loader ever appears.
  await page.evaluate(() => {
    window.__screens = [];
    window.__sawLoader = false;
    const note = () => {
      const label = document.querySelector('[data-screen-label]')?.getAttribute('data-screen-label');
      if (label && window.__screens[window.__screens.length - 1] !== label) window.__screens.push(label);
      if (document.querySelector('[data-testid="account-gate"]')) window.__sawLoader = true;
    };
    new MutationObserver(note).observe(document.body, { subtree: true, childList: true, attributes: true });
    note();
  });

  await page.getByTestId('login-submit').click();
  await expect(page.getByTestId('login-submit-check')).toBeVisible({ timeout: 10000 });
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/web-login-check.png` });
  await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 10000 });
  const screens = await page.evaluate(() => window.__screens);
  expect(screens.filter(x => x === 'Home').length).toBe(1);
  expect(screens.slice(0, 2)).toEqual(['Login', 'Home']);
  expect(await page.evaluate(() => window.__sawLoader)).toBe(false);

  // The sign-in reveal ends, then the v3 tour starts over the real Home.
  const overlay = page.getByTestId('tour-overlay');
  await expect(overlay).toBeVisible({ timeout: 8000 });
  await expect(page.getByTestId('tour-title')).toContainText('Find anything here');
  await expect(page.locator('#root')).toHaveAttribute('inert', '');
  await expect(page.getByRole('dialog')).toHaveAttribute('aria-modal', 'true');
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/web-tour-1.png` });

  const before = calls.length;
  // Clicking where the real search bar is does nothing: the scrim takes it.
  const bar = await page.getByTestId('home-search-bar').boundingBox();
  if (bar) await page.mouse.click(bar.x + bar.width / 2, bar.y + bar.height / 2);
  await expect(page.getByTestId('tour-title')).toContainText('Find anything here');

  // No For You preferences in this synthetic account: that step is skipped, not pointed at nothing. Home still
  // lists the bundled catalogue, so the event-card step has a real card to show.
  await page.getByTestId('tour-next').click();
  await expect(page.getByTestId('tour-title')).toContainText('An event', { timeout: 6000 });
  await expect(page.getByTestId('tour-step-2')).toBeDisabled();
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/web-tour-3.png` });
  await page.getByTestId('tour-next').click();
  await expect(page.getByTestId('tour-title')).toContainText('Map');

  // Direct jump, Back, and the Account step on the real Account screen.
  await page.getByTestId('tour-step-6').click();
  await expect(page.getByTestId('tour-title')).toContainText('Messages');
  await page.getByTestId('tour-back').click();
  await expect(page.getByTestId('tour-title')).toContainText('Schedule');
  await page.getByTestId('tour-step-7').click();
  await expect(page.getByTestId('tour-title')).toContainText('Want to host?', { timeout: 6000 });
  await expect(page.locator('[data-screen-label="Account"]')).toBeVisible();
  // The cut-out sits on the real organizer toggle, scrolled into view.
  await expect(page.getByTestId('tour-highlight')).toBeVisible();
  await expect.poll(async () => {
    const t = await page.getByTestId('organizer-mode-toggle').boundingBox();
    const h = await page.getByTestId('tour-highlight').boundingBox();
    return !!(t && h && Math.abs((t.y + t.height / 2) - (h.y + h.height / 2)) < 4 && t.y >= 0 && t.y + t.height <= 844);
  }, { timeout: 4000 }).toBe(true);
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/web-tour-7.png` });

  // Keyboard: Tab stays in the card; Escape = Skip, back on Home, #root usable again, marker written.
  await page.keyboard.press('Tab');
  expect(await page.evaluate(() => !!document.activeElement?.closest('[data-testid="tour-card"]'))).toBe(true);
  await page.keyboard.press('Escape');
  await expect(overlay).toHaveCount(0);
  await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  await expect(page.locator('#root')).not.toHaveAttribute('inert', '');
  expect(await page.evaluate((uid) => !!localStorage.getItem(`banbe.tour.v3.done.${uid}`), UID)).toBe(true);

  // Nothing the tour showed was acted on: no writing RPC ran while it was up.
  const during = calls.slice(before);
  const WRITES = /^(set_|save_|update_|toggle_|hold_|claim_|log_app_events|complete_|ensure_|admin_)/;
  expect(during.filter(fn => WRITES.test(fn))).toEqual([]);
});

test('reduced motion: the same hand-off, no spin or morph needed', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await mockSupabase(page, { flags: {} });
  await toLogin(page);
  await page.getByTestId('login-submit').click();
  await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 10000 });
  await expect(page.getByTestId('tour-overlay')).toHaveCount(0); // Version 1: no tour
});
