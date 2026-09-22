// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

// BUG 2 (07-notifications.md, 2026-09-22 second follow-up) — event distance
// km must reflect a real, live computed distance when location is actually
// available, and must show NO km at all (never the catalogue's static
// placeholder) whenever it isn't. `stripKm()`'s `km == null` branch used to
// `return str` UNCHANGED — the baked-in placeholder number stayed on
// screen looking exactly like a live value any time `located` was true but
// a real position genuinely wasn't available.

const KM_PATTERN = /\d+[.,]\d+\s*km/;

test.describe('Event distance (km) reflects real location permission/coords, not a static placeholder', () => {
  test('location denied: no km value is shown at all', async ({ page }) => {
    await setupToHome(page);
    await page.click('[data-testid="home-event-jazzgac"]');
    await expect(page.locator('[data-screen-label="Event"]')).toBeVisible();
    const body = await page.locator('body').innerText();
    expect(body).not.toMatch(KM_PATTERN);
  });

  test('location granted with a real position: a live km value is shown and changes with the test location', async ({ page, context }) => {
    await context.grantPermissions(['geolocation']);
    await context.setGeolocation({ latitude: 10.7769, longitude: 106.7009 }); // ~District 1
    await setupToHome(page);

    // Grant location from Home's own area sheet (the app's real allow
    // path — sets `located: true` and requests a fresh position) BEFORE
    // navigating to Event Detail.
    await page.getByText(/banbe ▪︎ Sài Gòn/).click();
    await page.getByText('Dùng vị trí của tôi để xem khoảng cách').click();
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();

    await page.click('[data-testid="home-event-jazzgac"]');
    await expect(page.locator('[data-screen-label="Event"]')).toBeVisible();

    const bodyNear = await page.locator('body').innerText();
    expect(bodyNear).toMatch(KM_PATTERN);
    const kmNear = bodyNear.match(KM_PATTERN)[0];

    // Move the simulated position far away — the SAME event's live distance
    // must change (proves it's a real computed value, not the catalogue's
    // frozen placeholder, which would stay identical either way).
    await context.setGeolocation({ latitude: 21.0278, longitude: 105.8342 }); // Hanoi
    await page.evaluate(() => new Promise((resolve) => navigator.geolocation.getCurrentPosition(resolve, resolve)));
    await page.reload();
    await page.click('[data-testid="home-event-jazzgac"]');
    await expect(page.locator('[data-screen-label="Event"]')).toBeVisible();
    await expect(async () => {
      const bodyFar = await page.locator('body').innerText();
      expect(bodyFar).toMatch(KM_PATTERN);
      expect(bodyFar.match(KM_PATTERN)[0]).not.toBe(kmNear);
    }).toPass({ timeout: 8000 });
  });
});
