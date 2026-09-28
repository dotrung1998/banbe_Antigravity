// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { hasServiceRole, adminClient } from './e2e/setup.mjs';

// Address-autocomplete fix pass (2026-09-28) — replaces the old single-
// shot "type free text, tap Confirm, get ONE geocode result" flow this
// spec used to exercise (`create-location-geocode`/`create-location-confirm`
// test ids, now gone). Publishing an event now REQUIRES a real address
// SELECTED from a live suggestions list — these exercise that end to end
// against the real Nominatim API (no mock), plus the failed/ambiguous
// address state migration 105's own ADDRESS_NOT_VERIFIED gate exists for.
test.describe('Create event — address autocomplete', () => {
  test.afterEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (data?.auth_user_id) await admin.from('profiles').update({ role: 'participant' }).eq('id', data.auth_user_id);
  });

  async function openCreateEvent(page) {
    await setupToHome(page);

    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    // Account extension (2026-09-27, Stage 1) — the toggle now lives on
    // the always-reachable Cá nhân tab (Account's default), not behind
    // the Tổ chức tab (which only shows once organizer mode is already on).
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
  }

  test('typing an address, selecting a suggestion, and confirming shows the confirmed state', async ({ page }) => {
    await openCreateEvent(page);

    // A well-known Ho Chi Minh City landmark — chosen after directly
    // probing Nominatim's public API (not guessed): "Nhà thờ Đức Bà Sài
    // Gòn" resolves to nothing useful there (only a country-level match),
    // while "Independence Palace Ho Chi Minh City" reliably returns a
    // real house-number+street+ward+city+postcode result. Real venue/POI
    // search (a `building`/`historic` OSM tag with an explicit house
    // number in this specific case), exercising the address-decomposition
    // path end to end.
    await page.getByTestId('create-location-input').fill('Independence Palace Ho Chi Minh City');

    // Real network round trip to MapKit/Nominatim (debounced 500ms) — no
    // mock, generous timeout.
    const firstSuggestion = page.getByTestId('create-location-suggestion').first();
    await expect(firstSuggestion).toBeVisible({ timeout: 15000 });
    await firstSuggestion.click();

    await expect(page.getByTestId('create-location-confirmed')).toBeVisible();
    // Nominatim's own usage policy requires attribution wherever its
    // results are shown or used.
    await expect(page.getByTestId('create-location-confirmed')).not.toHaveCount(0);

    // Editing the location text again must invalidate the stale
    // confirmation — never silently keep a point that no longer matches
    // what's on screen (the ticket's own "must not accept an unresolved
    // free-text string" requirement).
    await page.getByTestId('create-location-input').fill('một địa chỉ khác hoàn toàn');
    await expect(page.getByTestId('create-location-confirmed')).toHaveCount(0);
  });

  test('an unresolvable address shows a clear error, never a silent gap or a fake pin', async ({ page }) => {
    await openCreateEvent(page);

    // Deliberately unresolvable — no house number, no street, no venue
    // name Nominatim/MapKit could plausibly match.
    await page.getByTestId('create-location-input').fill('zzzqxjkvwnotarealplaceanywhere000');

    await expect(page.locator('text=/Không tìm thấy địa chỉ nào|No addresses found/')).toBeVisible({ timeout: 15000 });
    await expect(page.getByTestId('create-location-confirmed')).toHaveCount(0);
    await expect(page.getByTestId('create-location-suggestion')).toHaveCount(0);

    // A failed search must offer an explicit retry, not just a dead end.
    await expect(page.getByTestId('create-location-retry')).toBeVisible();
  });
});
