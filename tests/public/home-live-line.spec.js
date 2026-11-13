// @ts-check
import { test, expect } from '@playwright/test';

// Note 81, phase c: the v2.3 live line (switch home_v23). Guest, fully mocked Supabase including goc_pulse_ranked.
// Optional screenshots: V23_SHOTS=<dir>.
const SHOTS = process.env.V23_SHOTS;
const SUPABASE = 'https://ukchdgdnwytretvqjjqu.supabase.co';
const json = (body, status = 200) => ({ status, contentType: 'application/json', body: JSON.stringify(body) });
const inDays = (d, h = 19) => { const t = new Date(Date.now() + d * 864e5); t.setUTCHours(h - 7, 0, 0, 0); return t.toISOString(); };
const EVENTS = Array.from({ length: 4 }, (_, i) => ({
  id: `e8300000-0000-4000-8000-00000000000${i + 1}`, name: ['Live test supper', 'Live test jazz', 'Live test gallery', 'Live test market'][i],
  cat_key: ['supper', 'music', 'gallery', 'popup'][i], starts_at: inDays(i + 2), price_vnd: 200000, organizer_id: `org_live_${i + 1}`,
})).map(e => ({ ...e, status: 'live', visibility: 'public', capacity: 20, seats_remaining: 20, area: 'Quận 1', country_code: 'VN', state_province: 'Hồ Chí Minh', tz: 'Asia/Ho_Chi_Minh', currency: 'VND' }));
const PULSE = { success: true, period: 'daily', items: EVENTS.map((e, i) => ({ event_id: e.id, event_name: e.name, organizer_name: `Host ${i + 1}`, booking_count: i === 1 ? 3 : 0, score: 10 - i })) };
const FLAGS = { simple_shell: true, home_v23: true };

test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

/** @param {import('@playwright/test').Page} page @param {Record<string, boolean>} flags */
async function mockSupabase(page, flags = FLAGS) {
  await page.route(`${SUPABASE}/**`, async (r) => {
    const url = new URL(r.request().url());
    const p = url.pathname;
    const accept = r.request().headers().accept || '';
    if (p.startsWith('/auth/v1/')) return r.fulfill({ status: 204, body: '' });
    if (p.startsWith('/rest/v1/rpc/')) {
      const fn = p.split('/').pop();
      if (fn === 'get_feature_flags') return r.fulfill(json(flags));
      if (fn === 'goc_pulse_ranked') return r.fulfill(json(PULSE));
      return r.fulfill(json(null));
    }
    if (p.startsWith('/rest/v1/events')) return r.fulfill(json(accept.includes('vnd.pgrst.object') ? EVENTS[0] : EVENTS));
    if (p.startsWith('/rest/v1/')) return r.fulfill(accept.includes('vnd.pgrst.object') ? json(null, 406) : json([]));
    return r.fulfill({ status: 404, body: '' });
  });
  await page.addInitScript((f) => { try { localStorage.setItem('banbe_feature_flags_v1', JSON.stringify(f)); localStorage.setItem('banbe.guestOnboarding.v1', '1'); } catch { /* */ } }, flags);
}

/** @param {import('@playwright/test').Page} page */
async function guestHome(page) {
  await page.goto('/');
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('lang-en').isVisible().catch(() => false)) { await page.getByTestId('lang-en').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('onboarding-continue').isVisible().catch(() => false)) { await page.getByTestId('onboarding-continue').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('welcome-explore').isVisible().catch(() => false)) { await page.getByTestId('welcome-explore').click(); await page.waitForTimeout(300); continue; }
    if (await page.locator('[data-screen-label="Home"]').isVisible().catch(() => false)) break;
    await page.waitForTimeout(300);
  }
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 20000 });
}
const shot = async (page, name) => { if (SHOTS) { await page.waitForTimeout(700); await page.screenshot({ path: `${SHOTS}/${name}.png` }); } };

test('switch off: no live line', async ({ page }) => {
  await mockSupabase(page, { simple_shell: true });
  await guestHome(page);
  await expect(page.getByTestId('home-by-type')).toBeVisible({ timeout: 15000 });
  await expect(page.getByTestId('home-live-line')).toHaveCount(0);
});

test('ticker: seamless two copies, Live / Paused pauses it (WCAG 2.2.2)', async ({ page }) => {
  await mockSupabase(page);
  await guestHome(page);
  const line = page.getByTestId('home-live-line');
  await expect(line).toBeVisible({ timeout: 15000 });
  await expect(line).toHaveAttribute('data-mode', 'ticker');
  const run = page.getByTestId('home-live-run');
  await expect(run.locator(':scope > span')).toHaveCount(2);
  await expect(run).toContainText('3 bookings for Live test jazz today');
  await expect(run).toHaveAttribute('aria-hidden', 'true');
  const pause = page.getByTestId('home-live-pause');
  await expect(pause).toHaveAttribute('aria-label', 'Pause live updates');
  const box = await pause.boundingBox();
  expect(box.height).toBeGreaterThanOrEqual(44);
  await line.scrollIntoViewIfNeeded();
  await shot(page, 'c1-live-ticker');
  await pause.click();
  await expect(pause).toHaveAttribute('aria-pressed', 'true');
  await expect(pause).toHaveAttribute('aria-label', 'Resume live updates');
  await expect(page.getByTestId('home-live-state')).toHaveText('Paused');
  expect(await run.evaluate(el => getComputedStyle(el).animationPlayState)).toBe('paused');
  await pause.click();
  expect(await run.evaluate(el => getComputedStyle(el).animationPlayState)).toBe('running');
});

test('Live now: every update, Open goes to the event, browser Back closes the sheet', async ({ page }) => {
  await mockSupabase(page);
  await guestHome(page);
  await page.getByTestId('home-live-open').click();
  const sheet = page.getByTestId('live-now-sheet');
  await expect(sheet).toBeVisible();
  const rows = sheet.locator('[data-testid^="live-now-row-"]');
  expect(await rows.count()).toBeGreaterThanOrEqual(4);
  await shot(page, 'c2-live-now');
  await page.goBack();
  await expect(sheet).toHaveCount(0);
  await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  await page.getByTestId('home-live-open').click();
  const open = page.locator('[data-testid^="live-now-open-"]').first();
  await open.click();
  await expect(page.getByTestId('live-now-sheet')).toHaveCount(0);
  await expect(page).toHaveURL(/\/event\//);
});

test('reduced motion: one whole update at a time, ‹ n/N › steps, nothing moves on its own', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await mockSupabase(page);
  await guestHome(page);
  const line = page.getByTestId('home-live-line');
  await expect(line).toHaveAttribute('data-mode', 'reduced', { timeout: 15000 });
  const one = page.getByTestId('home-live-one');
  await expect(one).toHaveAttribute('aria-live', 'polite');
  const idx = page.getByTestId('home-live-index');
  await expect(idx).toHaveText(/^1\/\d+$/);
  const first = await one.textContent();
  await page.waitForTimeout(2500);
  expect(await one.textContent()).toBe(first);
  await expect(page.getByTestId('home-live-prev')).toBeDisabled();
  await page.getByTestId('home-live-next').click();
  await expect(idx).toHaveText(/^2\//);
  expect(await one.textContent()).not.toBe(first);
  await line.scrollIntoViewIfNeeded();
  await shot(page, 'c3-live-reduced');
  await page.getByTestId('home-live-open').click();
  await expect(page.getByTestId('live-now-row-1')).toHaveAttribute('data-here', 'true');
  await expect(page.getByTestId('live-now-row-1')).toContainText('showing on Home');
});
