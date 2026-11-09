// @ts-check
import { test, expect } from '@playwright/test';

// Note 80: Home photo hero (Simple Shell is on by default), fully mocked Supabase, nothing reaches the real backend.
// Optional screenshots: ONBOARDING_SHOTS=<dir>.
const SHOTS = process.env.ONBOARDING_SHOTS;
const SUPABASE = 'https://ukchdgdnwytretvqjjqu.supabase.co';
const UID = '00000000-0000-4000-8000-0000000080aa';
const json = (body, status = 200) => ({ status, contentType: 'application/json', body: JSON.stringify(body) });
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const exp = Math.floor(Date.now() / 1000) + 3600;
const JWT = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: UID, role: 'authenticated', aud: 'authenticated', exp, email: 'v5@example.test' })}.sig`;
const USER = { id: UID, aud: 'authenticated', role: 'authenticated', email: 'v5@example.test', app_metadata: { provider: 'email' }, user_metadata: {}, created_at: '2026-10-01T00:00:00Z' };
const SESSION = { access_token: JWT, token_type: 'bearer', expires_in: 3600, expires_at: exp, refresh_token: 'r-80', user: USER };
const PROFILE = {
  id: UID, role: 'participant', locale: 'en', theme: 'light', prefs_saved: true, display_name: 'V5 Test', handle: 'v5test',
  organizer_mode_enabled: false, can_manage_admins: false, muted_notification_kinds: [], interests: [], social_links: [],
  auto_email_documents: false, policy_accepted_at: '2026-10-01T00:00:00Z',
};
// Two free music events and one gallery opening, all upcoming: music has 2 (fewer than 3, so "close matches").
const inDays = (d) => new Date(Date.now() + d * 864e5).toISOString();
const EVENTS = [
  { id: 'e5000000-0000-4000-8000-000000000001', name: 'Listening night', cat_key: 'music', starts_at: inDays(2) },
  { id: 'e5000000-0000-4000-8000-000000000002', name: 'Rooftop set', cat_key: 'music', starts_at: inDays(3) },
  { id: 'e5000000-0000-4000-8000-000000000003', name: 'Print show', cat_key: 'gallery', starts_at: inDays(4) },
].map(e => ({ ...e, status: 'live', visibility: 'public', price_vnd: 0, capacity: 20, seats_remaining: 10, area: 'Quận 1', country_code: 'VN', state_province: 'Hồ Chí Minh' }));

test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

/** @param {import('@playwright/test').Page} page */
async function mockSupabase(page, { flags, calls }) {
  await page.route(`${SUPABASE}/**`, async (r) => {
    const url = new URL(r.request().url());
    const p = url.pathname;
    const accept = r.request().headers().accept || '';
    if (p.endsWith('/auth/v1/token')) return r.fulfill(json(SESSION));
    if (p.endsWith('/auth/v1/user')) return r.fulfill(json(USER));
    if (p.startsWith('/auth/v1/')) return r.fulfill({ status: 204, body: '' });
    if (p.startsWith('/rest/v1/rpc/')) {
      const fn = p.split('/').pop();
      calls.push(fn);
      if (fn === 'get_feature_flags') return r.fulfill(json(flags));
      if (fn === 'account_gate_status') return r.fulfill(json({ ready: true }));
      if (fn === 'get_my_event_preferences') return r.fulfill(json({ success: true, preferences: null, needs_settings_step: false, needs_preferences_step: false }));
      if (fn === 'complete_preferences_onboarding' || fn === 'save_my_event_preferences') return r.fulfill(json({ success: true, preferences_version: 1 }));
      if (fn === 'complete_settings_onboarding') return r.fulfill(json({ success: true }));
      if (fn === 'set_my_digest_opt_in') return r.fulfill(json({ success: true, digest_opt_in: true }));
      if (fn === 'set_organizer_mode') return r.fulfill(json({ success: true, organizer_mode_enabled: true }));
      return r.fulfill(json(null));
    }
    if (p.startsWith('/rest/v1/profiles')) return r.fulfill(json(accept.includes('vnd.pgrst.object') ? PROFILE : [PROFILE]));
    if (p.startsWith('/rest/v1/events')) return r.fulfill(json(EVENTS));
    if (p.startsWith('/rest/v1/')) return r.fulfill(accept.includes('vnd.pgrst.object') ? json(null, 406) : json([]));
    return r.fulfill({ status: 404, body: '' });
  });
  await page.addInitScript((f) => { try { localStorage.setItem('banbe_feature_flags_v1', JSON.stringify(f)); } catch { /* */ } }, flags);
}

/** @param {import('@playwright/test').Page} page */
async function signIn(page) {
  await page.goto('/');
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('lang-en').isVisible().catch(() => false)) { await page.getByTestId('lang-en').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('onboarding-continue').isVisible().catch(() => false)) { await page.getByTestId('onboarding-continue').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('welcome-login').isVisible().catch(() => false)) break;
    await page.waitForTimeout(300);
  }
  await page.getByTestId('welcome-login').click();
  await page.getByTestId('login-method-password').click();
  await page.getByTestId('login-email').fill('v5@example.test');
  await page.getByTestId('login-password').fill('not-a-real-password');
  await page.getByTestId('login-submit').click();
}

// Let entrance animations settle so a review shot shows the resting screen.
const shot = async (page, name) => { if (SHOTS) { await page.waitForTimeout(900); await page.screenshot({ path: `${SHOTS}/${name}.png` }); } };
const WRITES = /^(set_|save_|complete_)/;

test('Home opens on the photo hero: tabs, a card rail ending in See all, honest empty tabs', async ({ page }) => {
  const calls = [];
  await mockSupabase(page, { flags: {}, calls }); // no simple_shell key: the shell is on by default
  page.on('pageerror', e => console.log('PAGEERR', e.message));
  await signIn(page);

  const hero = page.getByTestId('home-photo-hero');
  await expect(hero).toBeVisible({ timeout: 20000 });
  await expect(hero).toHaveAttribute('data-tab', 'foryou');
  // No preferences: For You falls back to the soonest events (the mocked ones plus the bundled catalogue), max 5.
  const cards = page.getByTestId('home-hero-rail').locator('[data-testid^="home-hero-card-"]');
  await expect(cards).toHaveCount(5);
  await expect(page.getByTestId('home-hero-see-all')).toBeVisible();
  await shot(page, 'home-hero');
  if (SHOTS) { await page.evaluate(() => { const sc = [...document.querySelectorAll('*')].find(e => e.scrollHeight > e.clientHeight + 200 && getComputedStyle(e).overflowY !== 'visible'); if (sc) sc.scrollTop = 640; }); await page.waitForTimeout(500); await page.screenshot({ path: `${SHOTS}/home-scrolled.png` }); await page.evaluate(() => { const sc = [...document.querySelectorAll('*')].find(e => e.scrollHeight > e.clientHeight + 200 && getComputedStyle(e).overflowY !== 'visible'); if (sc) sc.scrollTop = 0; }); }

  // Everything is 2+ days out, so Tonight is honestly empty.
  await page.getByTestId('home-hero-tab-tonight').click();
  await expect(page.getByTestId('home-hero-empty')).toBeVisible();
  await expect(page.getByTestId('home-hero-tab-tonight')).toHaveAttribute('aria-selected', 'true');

  // A card opens the real event page.
  await page.getByTestId('home-hero-tab-foryou').click();
  await cards.first().click();
  await expect(page.locator('[data-screen-label="Event"]')).toBeVisible({ timeout: 8000 });
  // Browsing wrote nothing.
  expect(calls.filter(fn => WRITES.test(fn))).toEqual([]);
});
