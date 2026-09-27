// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { hasServiceRole, adminClient } from './e2e/setup.mjs';

// Stage 3 (2026-09-27 nav/discovery pass) — Map's own pin audit found
// create_event_draft never accepted or stored coordinates at all (real,
// non-demo events had lat=NULL/lng=NULL, confirmed live), so an approved
// real event from any host could never show a map pin. This exercises the
// real UI fix end to end: typing a location, geocoding it (a real
// Nominatim call, not mocked), and explicitly confirming before submit.
test.describe('Create event — explicit location confirmation', () => {
  test.afterEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (data?.auth_user_id) await admin.from('profiles').update({ role: 'participant' }).eq('id', data.auth_user_id);
  });

  test('typing a location, geocoding, and confirming shows the confirmed state', async ({ page }) => {
    await setupToHome(page);

    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    await page.getByTestId('account-tab-host').click();
    const toggle = page.getByTestId('organizer-mode-toggle');
    await expect(toggle).toBeVisible({ timeout: 8000 });
    // Turn organizer mode on (idempotent — the pitch button only shows
    // when this account has never hosted; if it's already a host, the
    // toggle itself is what's there instead) so the dock's own "+" shows.
    const pitch = page.getByText(/Bắt đầu tổ chức|Start hosting/, { exact: false });
    if (await pitch.isVisible().catch(() => false)) {
      await pitch.click();
      await expect(toggle).toBeVisible({ timeout: 8000 });
    }
    await page.getByTestId('tab-home').click();
    await page.waitForSelector('[data-screen-label="Home"]');

    await page.getByTestId('dock-create-button').click();
    await page.waitForSelector('[data-testid="dock-create-menu-event"]');
    // Same real-click-vs-pointer-capture workaround as
    // create-event-origin.spec.js — see that test's own comment.
    await page.evaluate(() => {
      document.querySelector('[data-testid="dock-create-menu-event"]')
        .dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
    });
    await page.waitForSelector('[data-screen-label="Create event"]', { timeout: 8000 });

    await page.getByTestId('create-location-input').fill('Quận 1');
    await expect(page.getByTestId('create-location-geocode')).toBeVisible();
    await page.getByTestId('create-location-geocode').click();

    // A real network round trip to Nominatim — generous timeout, no mock.
    await expect(page.getByTestId('create-location-confirm')).toBeVisible({ timeout: 15000 });
    await page.getByTestId('create-location-confirm').click();

    await expect(page.getByTestId('create-location-confirmed')).toBeVisible();

    // Editing the location text again must invalidate the stale
    // confirmation — never silently keep a point that no longer matches
    // what's on screen.
    await page.getByTestId('create-location-input').fill('Quận 1 sửa lại');
    await expect(page.getByTestId('create-location-confirmed')).toHaveCount(0);
    await expect(page.getByTestId('create-location-geocode')).toBeVisible();
  });
});
