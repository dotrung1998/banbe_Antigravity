// @ts-check
import { test, expect } from '@playwright/test';

// Note 80: onboarding v5 on the web, end to end against a fully mocked Supabase (a synthetic account, nothing
// reaches the real backend): 3 questions with live counts, More types, the never-empty For You, one choice per
// screen (writes only on Continue), the recap, and the forward-only chaptered tour with its do-it step.
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
      if (fn === 'get_my_event_preferences') return r.fulfill(json({ success: true, preferences: null, needs_settings_step: true, needs_preferences_step: true, is_new_account: true }));
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

test('v5: three questions, never-empty For You, one choice per screen, recap, then the chaptered tour', async ({ page }) => {
  const calls = [];
  await mockSupabase(page, { flags: { weekly_digest: true }, calls });
  await signIn(page);

  // Welcome.
  await expect(page.getByTestId('onboarding-welcome')).toBeVisible({ timeout: 15000 });
  await expect(page.getByText('3 questions, about a minute')).toBeVisible();
  await shot(page, 'v5-welcome');
  await page.getByTestId('onboarding-start').click();

  // 1 of 3: only types with events are tiles, each with its live count; More types searches the rest.
  await expect(page.getByTestId('onboarding-question-interests')).toBeVisible();
  await expect(page.getByTestId('onboarding-progress')).toHaveText('1 of 3');
  await expect(page.getByTestId('onboarding-next')).toBeDisabled();
  await expect(page.getByTestId('onboarding-option-music')).toContainText('2 events');
  await expect(page.getByTestId('onboarding-option-gallery')).toContainText('1 event');
  await expect(page.getByTestId('onboarding-option-supper')).toHaveCount(0);
  await page.getByTestId('onboarding-more-types').click();
  await expect(page.getByTestId('onboarding-types')).toBeVisible();
  await page.getByTestId('onboarding-types-search').fill('sup');
  await page.getByTestId('onboarding-types-supper').click();
  await page.getByTestId('onboarding-types-done').click();
  await expect(page.getByTestId('onboarding-chip-supper')).toBeVisible();
  await page.getByTestId('onboarding-chip-supper').click();
  await expect(page.getByTestId('onboarding-chip-supper')).toHaveCount(0);
  await page.getByTestId('onboarding-option-music').click();
  await expect(page.getByTestId('onboarding-feedback')).toHaveText('2 events fit so far. For You will add close picks.');
  await shot(page, 'v5-interests');
  await page.getByTestId('onboarding-next').click();

  // 2 of 3: Back keeps answers; skip.
  await expect(page.getByTestId('onboarding-question-availability')).toBeVisible();
  await page.getByTestId('onboarding-back').click();
  await expect(page.getByTestId('onboarding-option-music')).toHaveAttribute('aria-pressed', 'true');
  await page.getByTestId('onboarding-next').click();
  await page.getByTestId('onboarding-skip').click();

  // 3 of 3: budget with counts.
  await expect(page.getByTestId('onboarding-progress')).toHaveText('3 of 3');
  await page.getByTestId('onboarding-option-free').click();
  await page.getByTestId('onboarding-next').click();

  // Your For You: 2 exact music events, topped up with the gallery opening; it says so.
  await expect(page.getByTestId('onboarding-reveal')).toHaveAttribute('data-mode', 'topped', { timeout: 10000 });
  await expect(page.getByTestId('onboarding-reveal-title')).toHaveText('2 close matches, and more like them');
  await expect(page.getByTestId('onboarding-reveal-event')).toHaveCount(3);
  await shot(page, 'v5-reveal');
  expect(calls).toContain('complete_preferences_onboarding');
  await page.getByTestId('onboarding-reveal-continue').click();

  // One choice per screen: Not now writes nothing, Continue writes the real setting.
  await expect(page.getByTestId('onboarding-consent-digest')).toBeVisible();
  await expect(page.getByTestId('onboarding-progress')).toHaveText('Choice 1 of 2');
  await shot(page, 'v5-choice-digest');
  await page.getByTestId('onboarding-consent-not-now').click();
  expect(calls).not.toContain('set_my_digest_opt_in');
  await expect(page.getByTestId('onboarding-consent-hosting')).toBeVisible();
  await page.getByTestId('onboarding-consent-continue').click();

  // Recap, then the tour.
  await expect(page.getByTestId('onboarding-recap')).toBeVisible({ timeout: 10000 });
  expect(calls).toContain('complete_settings_onboarding');
  await expect(page.getByTestId('onboarding-recap-foryou-value')).toHaveText('1 type');
  await expect(page.getByTestId('onboarding-recap-digest-value')).toHaveText('Off');
  await shot(page, 'v5-recap');
  await page.getByTestId('onboarding-recap-tour').click();

  const overlay = page.getByTestId('tour-overlay');
  await expect(overlay).toBeVisible({ timeout: 8000 });
  await expect(page.getByTestId('tour-chapter')).toContainText('Chapter 1 of 3');
  await expect(page.getByTestId('tour-title')).toHaveText('Your For You picks');
  await expect(page.getByTestId('tour-back')).toHaveCount(0);
  await expect(page.getByTestId('tour-step-1')).toHaveCount(0);
  await shot(page, 'v5-tour-1');
  const before = calls.length;

  // Steps forward; a do-it step only moves on from its control.
  for (let i = 0; i < 8; i++) {
    if (await page.getByTestId('tour-break').isVisible().catch(() => false)) break;
    if (await page.getByTestId('tour-do-it').isVisible().catch(() => false)) { await shot(page, 'v5-tour-doit'); await page.getByTestId('tour-do-it').click(); }
    else await page.getByTestId('tour-next').click();
    await page.waitForTimeout(200);
  }
  await expect(page.getByTestId('tour-break')).toBeVisible();
  await expect(page.getByTestId('tour-sheet-title')).toHaveText('Next: plans and messages');
  await expect(page.getByTestId('tour-chapter-discover')).toHaveAttribute('data-state', 'done');
  await shot(page, 'v5-tour-break');
  // Nothing the tour showed was written.
  expect(calls.slice(before).filter(fn => WRITES.test(fn))).toEqual([]);
  await page.getByTestId('tour-break-stop').click();
  await expect(overlay).toHaveCount(0);
  await expect(page.locator('#root')).not.toHaveAttribute('inert', '');
  expect(await page.evaluate((uid) => !!localStorage.getItem(`banbe.tour.v3.done.${uid}`), UID)).toBe(true);
});

test('v5: skip everything ends on the recap, and Skip, go to Home never starts the tour', async ({ page }) => {
  const calls = [];
  await mockSupabase(page, { flags: {}, calls });
  await signIn(page);
  await expect(page.getByTestId('onboarding-skip-all')).toBeVisible({ timeout: 15000 });
  await page.getByTestId('onboarding-skip-all').click();
  // Only Hosting mode can be offered without the digest switch.
  await expect(page.getByTestId('onboarding-consent-hosting')).toBeVisible({ timeout: 10000 });
  await page.getByTestId('onboarding-consent-not-now').click();
  await expect(page.getByTestId('onboarding-recap')).toBeVisible({ timeout: 10000 });
  await expect(page.getByTestId('onboarding-recap-foryou-value')).toHaveText('Not set yet');
  await expect(page.getByTestId('onboarding-recap-hosting-value')).toHaveText('Off');
  expect(calls).not.toContain('set_organizer_mode');
  await page.getByTestId('onboarding-recap-home').click();
  await expect(page.getByTestId('event-onboarding-overlay')).toHaveCount(0);
  await page.waitForTimeout(1500);
  await expect(page.getByTestId('tour-overlay')).toHaveCount(0);
  expect(await page.evaluate((uid) => !!localStorage.getItem(`banbe.tour.v3.done.${uid}`), UID)).toBe(true);
});
