// @ts-check
// Unified discovery (note 99, switch unified_discovery on top of simple_shell + home_v23): the web Map shares Home's
// type / time / filters / query, its time is one chip with a popover, a pin opens a carousel then a preview card, and
// zoom is a "− +" capsule. Guest browsing, fully mocked Supabase (the basemap itself still loads from the network).
import { test, expect } from '@playwright/test';

const SUPABASE = 'https://ukchdgdnwytretvqjjqu.supabase.co';
const json = (body, status = 200) => ({ status, contentType: 'application/json', body: JSON.stringify(body) });
const inDays = (d, h = 19) => { const t = new Date(Date.now() + d * 864e5); t.setUTCHours(h - 7, 0, 0, 0); return t.toISOString(); };
// Two neighbourhoods about 1 km apart inside District 1 / 3 so the first framing is the area level.
const SPOTS = [
  { area: 'Quận 1', lat: 10.7769, lng: 106.7009 }, { area: 'Quận 1', lat: 10.7735, lng: 106.7045 },
  { area: 'Quận 1', lat: 10.7800, lng: 106.6975 }, { area: 'Quận 3', lat: 10.7840, lng: 106.6870 },
  { area: 'Quận 3', lat: 10.7870, lng: 106.6830 },
];
const CATS = ['music', 'supper', 'gallery', 'music', 'supper'];
const EVENTS = SPOTS.map((p, i) => ({
  id: `e9900000-0000-4000-8000-00000000000${i + 1}`, key: null, name: i === 0 ? 'Unified jazz night' : `Unified test ${i + 1}`,
  cat_key: CATS[i], cat_label: null, starts_at: inDays(i + 1), price_vnd: i === 1 ? 0 : 150000, seats_remaining: 20, capacity: 20,
  status: 'live', visibility: 'public', cover_image: null, details: {}, keywords: [], description: 'A test evening with music and friends.', intro: null,
  country_code: 'VN', state_province: 'Hồ Chí Minh', neighborhood: null, city: 'Hồ Chí Minh', tz: 'Asia/Ho_Chi_Minh', currency: 'VND',
  organizer_id: 'org_ud_1', organizers: { name: 'Nhà Test' }, ...p,
}));
const FLAGS = { simple_shell: true, home_v23: true, unified_discovery: true };

test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

/** @param {import('@playwright/test').Page} page */
async function mockSupabase(page, flags = FLAGS) {
  await page.route(`${SUPABASE}/**`, async (r) => {
    const url = new URL(r.request().url());
    const p = url.pathname;
    const accept = r.request().headers().accept || '';
    if (p.startsWith('/auth/v1/')) return r.fulfill({ status: 204, body: '' });
    if (p.startsWith('/rest/v1/rpc/')) {
      const fn = p.split('/').pop();
      if (fn === 'get_feature_flags') return r.fulfill(json(flags));
      return r.fulfill(json(null));
    }
    if (p.startsWith('/rest/v1/events')) {
      return r.fulfill({ status: 200, contentType: 'application/json', headers: { 'content-range': `0-${EVENTS.length - 1}/${EVENTS.length}` }, body: JSON.stringify(EVENTS) });
    }
    if (p.startsWith('/rest/v1/')) return r.fulfill(accept.includes('vnd.pgrst.object') ? json(null, 406) : json([]));
    return r.fulfill({ status: 404, body: '' });
  });
  await page.addInitScript((f) => { try { localStorage.setItem('banbe_feature_flags_v1', JSON.stringify(f)); localStorage.setItem('banbe.guestOnboarding.v1', '1'); } catch { /* */ } }, FLAGS);
}

/** @param {import('@playwright/test').Page} page */
async function openMap(page, flags = FLAGS) {
  await mockSupabase(page, flags);
  await page.goto('/map');
  const map = page.locator('[data-screen-label="MapExplore"]');
  for (let i = 0; i < 40; i++) {
    if (await map.isVisible().catch(() => false)) break;
    for (const id of ['lang-en', 'onboarding-continue', 'welcome-explore']) {
      if (await page.getByTestId(id).isVisible().catch(() => false)) { await page.getByTestId(id).click(); await page.waitForTimeout(300); }
    }
    if (await page.locator('[data-screen-label="Home"]').isVisible().catch(() => false)) { await page.goto('/map'); }
    await page.waitForTimeout(300);
  }
  await expect(map).toBeVisible({ timeout: 20000 });
  if (flags.unified_discovery) await expect(map).toHaveAttribute('data-ud', 'true');
  await page.waitForFunction(() => !!window.__mapExploreMapForTests && (window.__mapExploreCommits || 0) >= 1, null, { timeout: 20000 });
  await page.waitForTimeout(600);
}

/** Zoom in with the capsule until single pins show. */
async function zoomToPins(page) {
  for (let i = 0; i < 6; i++) {
    if (await page.locator('[data-testid^="map-pin-"]').count()) return;
    await page.getByTestId('map-zoom-in').click();
    await page.waitForTimeout(900);
  }
  await expect(page.locator('[data-testid^="map-pin-"]').first()).toBeVisible();
}

test('time is one chip whose popover keeps the day choices and the hour knobs, and writes the shared date', async ({ page }) => {
  await openMap(page);
  await expect(page.getByTestId('map-time-bar')).toHaveCount(0); // the 58 px row is gone
  const chip = page.getByTestId('map-time-chip');
  await expect(chip).toBeVisible();
  await expect(chip).toHaveAttribute('aria-pressed', 'false');
  await chip.click();
  const pop = page.getByTestId('map-time-popover');
  await expect(pop).toBeVisible();
  for (const k of ['today', 'tomorrow', 'weekend', 'nextWeek', 'all']) await expect(page.getByTestId(`map-time-day-${k}`)).toBeVisible();
  await expect(page.getByTestId('map-time-range')).toHaveAttribute('data-on', 'false');
  // A pick closes it and the chip turns pressed with the day + hours.
  await page.getByTestId('map-time-day-tomorrow').click();
  await expect(pop).toBeHidden();
  await expect(chip).toHaveAttribute('aria-pressed', 'true');
  await expect(chip).toContainText(/(Tomorrow|Mai) · 17–02/);
  // Reopen: the knobs are live; a keyboard step moves the start hour.
  await chip.click();
  await expect(page.getByTestId('map-time-range')).toHaveAttribute('data-on', 'true');
  await page.getByTestId('map-time-knob-from').focus();
  await page.keyboard.press('ArrowRight');
  await expect(page.getByTestId('map-time-knob-from')).toHaveAttribute('aria-valuenow', '18');
  // Esc closes it; an outside tap does too.
  await page.keyboard.press('Escape');
  await expect(pop).toBeHidden();
  await expect(chip).toContainText('18–02');
  await chip.click();
  await expect(pop).toBeVisible();
  await page.mouse.click(200, 500);
  await expect(pop).toBeHidden();
});

test('zoom capsule replaces the map control; area bubbles carry type glyphs', async ({ page }) => {
  await openMap(page);
  await expect(page.locator('.maplibregl-ctrl-zoom-in')).toBeHidden();
  const bubble = page.locator('[data-testid^="map-areabubble-"]').first();
  if (process.env.MAP_SHOTS) { await bubble.waitFor(); await page.screenshot({ path: `${process.env.MAP_SHOTS}/map-areas.png` }); }
  await expect(bubble).toBeVisible();
  await expect(bubble.getByTestId('map-areabubble-cats').first()).toBeVisible();
  const z0 = await page.evaluate(() => window.__mapExploreMapForTests.getZoom());
  await page.getByTestId('map-zoom-in').click();
  await page.waitForTimeout(900);
  const z1 = await page.evaluate(() => window.__mapExploreMapForTests.getZoom());
  expect(z1).toBeGreaterThan(z0 + 0.5);
  await page.getByTestId('map-zoom-out').click();
  await page.waitForTimeout(900);
  const z2 = await page.evaluate(() => window.__mapExploreMapForTests.getZoom());
  expect(z2).toBeLessThan(z1 - 0.5);
  // At the minimum zoom − is disabled.
  await page.evaluate(() => window.__mapExploreMapForTests.jumpTo({ zoom: window.__mapExploreMapForTests.getMinZoom() }));
  await expect(page.getByTestId('map-zoom-out')).toBeDisabled({ timeout: 5000 });
});

test('pin → carousel → preview → See details opens Event Detail and Back restores the preview', async ({ page }) => {
  await openMap(page);
  await zoomToPins(page);
  const id = (await page.locator('[data-testid^="map-pin-"]').first().getAttribute('data-testid')).replace('map-pin-', '');
  // A selected pin is redrawn (pulled out of any cluster), so it is found by its own id each time.
  const pin = page.getByTestId(`map-pin-${id}`);
  await pin.click();
  await expect(pin).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId(`map-pinname-${id}`)).toBeVisible();
  await expect(page.getByTestId('map-carousel')).toBeVisible();
  if (process.env.MAP_SHOTS) { await page.waitForTimeout(900); await page.screenshot({ path: `${process.env.MAP_SHOTS}/map-carousel.png` }); }
  await expect(page.getByTestId(`map-mcard-${id}`)).toHaveAttribute('aria-pressed', 'true');
  await page.getByTestId(`map-mcard-${id}`).click();
  const preview = page.getByTestId('map-preview');
  await expect(preview).toBeVisible();
  await expect(page.getByTestId('map-carousel')).toHaveCount(0);
  await expect(page.getByTestId('map-preview-details')).toBeVisible();
  if (process.env.MAP_SHOTS) { await page.waitForTimeout(900); await page.screenshot({ path: `${process.env.MAP_SHOTS}/map-preview.png` }); }
  const ev = EVENTS.find(e => e.id === id);
  if (ev.price_vnd > 0) await expect(page.getByTestId('map-preview-reserve')).toBeVisible();
  else await expect(page.getByTestId('map-preview-reserve')).toHaveCount(0);
  // ‹ List goes back to the carousel; Esc then closes it.
  await page.getByTestId('map-preview-back').click();
  await expect(page.getByTestId('map-carousel')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByTestId('map-carousel')).toHaveCount(0);
  // Again, then See details.
  await pin.click();
  await page.getByTestId(`map-mcard-${id}`).click();
  await page.getByTestId('map-preview-details').click();
  // Event Detail opens on that event (it may cover the Map rather than replace it).
  await expect(page.getByRole('heading', { level: 1, name: ev.name })).toBeVisible({ timeout: 10000 });
  await expect(page).not.toHaveURL(/\/map$/);
  await page.goBack();
  await expect(page.locator('[data-screen-label="MapExplore"]')).toBeVisible({ timeout: 15000 });
  await expect(page.getByTestId('map-preview')).toBeVisible({ timeout: 10000 });
  await expect(page.getByTestId('map-preview')).toHaveAttribute('data-event', id);
});

test('the type and the time picked on the Map are still there after Home and back (shared state)', async ({ page }) => {
  await openMap(page);
  await page.getByTestId('map-cat-music').click();
  await expect(page.getByTestId('map-cat-music')).toHaveAttribute('aria-selected', 'true');
  await page.getByTestId('map-time-chip').click();
  await page.getByTestId('map-time-day-today').click();
  // The badge counts only what Filters owns: the type (1), not the time.
  await expect(page.getByTestId('map-chip-filters')).toContainText('1');
  await page.getByTestId('map-back').click();
  await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 10000 });
  // A fresh open from the dock (no return snapshot) still shows the shared type and day: they live in Home's state.
  await page.getByTestId('home-map-button').click();
  await expect(page.locator('[data-screen-label="MapExplore"]')).toBeVisible({ timeout: 15000 });
  await expect(page.getByTestId('map-cat-music')).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByTestId('map-time-chip')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('map-time-chip')).toContainText(/Today|Hôm nay/);
});

test('switch off: the Map is as before (time bar row, map zoom control, a pin opens Event Detail)', async ({ page }) => {
  await openMap(page, { simple_shell: true, home_v23: true, unified_discovery: false });
  const map = page.locator('[data-screen-label="MapExplore"]');
  await expect(map).not.toHaveAttribute('data-ud', 'true');
  await expect(page.getByTestId('map-time-bar')).toBeVisible();
  await expect(page.getByTestId('map-time-chip')).toHaveCount(0);
  await expect(page.getByTestId('map-zoom')).toHaveCount(0);
  await expect(page.locator('.maplibregl-ctrl-zoom-in')).toBeVisible();
  await expect(page.getByTestId('map-areabubble-cats')).toHaveCount(0);
  for (let i = 0; i < 6 && !(await page.locator('[data-testid^="map-pin-"]').count()); i++) {
    await page.locator('.maplibregl-ctrl-zoom-in').click();
    await page.waitForTimeout(900);
  }
  // (Pins can sit close together, so this only checks that the tap went to an Event Detail, not which one.)
  await page.locator('[data-testid^="map-pin-"]').first().click();
  await expect(page.getByTestId('map-carousel')).toHaveCount(0);
  await expect(page.getByRole('heading', { level: 1, name: /Unified/ })).toBeVisible({ timeout: 10000 });
});
