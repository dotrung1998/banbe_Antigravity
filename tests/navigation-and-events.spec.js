// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

test.describe('Navigation & Event Exploration', () => {
  test.beforeEach(async ({ page }) => {
    await setupToHome(page);
  });

  test('a fresh unregistered visitor sees the public feed with no "Your events" section', async ({ page }) => {
    const homeScreen = page.locator('[data-screen-label="Home"]');
    await expect(homeScreen).toBeVisible();

    // No placeholder demo activity — just the public list.
    await expect(page.getByText('Sự kiện của bạn')).toHaveCount(0);
    await expect(page.getByText('Bếp Nhỏ №12').first()).toBeVisible();
    await expect(page.getByText('ORBIT: Afterlight').first()).toBeVisible();
  });

  test('displays Home screen feed and allows event detail navigation', async ({ page }) => {
    const homeScreen = page.locator('[data-screen-label="Home"]');
    await expect(homeScreen).toBeVisible();

    // Click on "Bếp Nhỏ №12" event card in the main feed
    const eventCard = page.getByText('Bếp Nhỏ №12').first();
    await expect(eventCard).toBeVisible();
    await eventCard.click();

    // EventDetail screen has data-screen-label="Event" (not "EventDetail")
    const detailScreen = page.locator('[data-screen-label="Event"]');
    await expect(detailScreen).toBeVisible({ timeout: 3000 });
    await expect(page.getByText('Bếp Nhỏ №12').first()).toBeVisible();

    // Verify "Giữ chỗ" (Reserve) button is present
    await expect(page.getByText(/Giữ chỗ/).first()).toBeVisible();

    // Click back to Home – back button says "‹ banbe"
    await page.getByText('‹ banbe').first().click();
    await expect(homeScreen).toBeVisible({ timeout: 3000 });
  });

  test('filters events by category on Home screen', async ({ page }) => {
    // Click the "Thời trang" category filter
    const fashionFilter = page.getByText('Thời trang', { exact: true });
    await expect(fashionFilter).toBeVisible();
    await fashionFilter.click();

    // ORBIT: Afterlight is a fashion-category event
    await expect(page.getByText('ORBIT: Afterlight').first()).toBeVisible({ timeout: 3000 });
  });

  test('navigates to organizer profile from event detail', async ({ page }) => {
    // Open any event
    await page.getByText('Bếp Nhỏ №12').first().click();
    await expect(page.locator('[data-screen-label="Event"]')).toBeVisible({ timeout: 3000 });

    // Click the "Ghé … ›" organizer row
    const organizerLink = page.getByText(/Ghé.*›/).first();
    await expect(organizerLink).toBeVisible();
    await organizerLink.click();

    await expect(page.locator('[data-screen-label="Organizer"]')).toBeVisible({ timeout: 3000 });
  });

  // An organizer page has no back target of its own — its back link just
  // re-opens whichever event is currently open. So an event reached from
  // one must NOT point back at it: that used to leave event and organizer
  // bouncing off each other forever with no way to reach Home short of
  // reloading the app. Both screens are one cluster about the same
  // organizer; back leaves the whole cluster.
  test('back from an event opened via the organizer page reaches Home, never loops', async ({ page }) => {
    // Home -> Event (came from Home, so back means Home).
    await page.getByText('Bếp Nhỏ №12').first().click();
    const eventScreen = page.locator('[data-screen-label="Event"]');
    const organizerScreen = page.locator('[data-screen-label="Organizer"]');
    const homeScreen = page.locator('[data-screen-label="Home"]');
    await expect(eventScreen).toBeVisible({ timeout: 3000 });
    await expect(eventScreen.getByText('‹ banbe')).toBeVisible();

    // Event -> Organizer -> an event from the organizer's own "Sự kiện đang
    // mở" list. That list includes the event we arrived from, which is the
    // exact path that used to trap the two screens in a loop.
    await page.getByText(/Ghé.*›/).first().click();
    await expect(organizerScreen).toBeVisible({ timeout: 3000 });
    await organizerScreen.getByText('Bếp Nhỏ №12', { exact: true }).click();
    await expect(eventScreen).toBeVisible({ timeout: 3000 });

    // The back pill still points at Home, so one tap leaves the cluster.
    await expect(eventScreen.getByText('‹ banbe')).toBeVisible();
    await eventScreen.getByText('‹ banbe').click();
    await expect(homeScreen).toBeVisible({ timeout: 3000 });
    await expect(organizerScreen).toHaveCount(0);
  });

  test('the organizer page itself still goes back to the event it was opened from', async ({ page }) => {
    await page.getByText('Bếp Nhỏ №12').first().click();
    const eventScreen = page.locator('[data-screen-label="Event"]');
    await expect(eventScreen).toBeVisible({ timeout: 3000 });

    await page.getByText(/Ghé.*›/).first().click();
    const organizerScreen = page.locator('[data-screen-label="Organizer"]');
    await expect(organizerScreen).toBeVisible({ timeout: 3000 });

    // "‹ <event name>" returns to the event, and from there one more tap
    // reaches Home rather than bouncing back to the organizer.
    await organizerScreen.getByText('‹ Bếp Nhỏ №12').click();
    await expect(eventScreen).toBeVisible({ timeout: 3000 });
    await eventScreen.getByText('‹ banbe').click();
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 3000 });
  });

  test('a gallery photo opens in the viewer with its credit and tagline', async ({ page }) => {
    await page.getByText('Bếp Nhỏ №12').first().click();
    const eventScreen = page.locator('[data-screen-label="Event"]');
    await expect(eventScreen).toBeVisible({ timeout: 3000 });

    // The "Hình ảnh" strip's photos are tappable.
    await expect(page.locator('[data-screen-label="Photo viewer"]')).toHaveCount(0);
    await eventScreen.getByText('Hình ảnh').scrollIntoViewIfNeeded();
    await eventScreen.locator('div[style*="width: 148px"]').first().click();

    const viewer = page.locator('[data-screen-label="Photo viewer"]');
    await expect(viewer).toBeVisible({ timeout: 3000 });
    await expect(viewer.getByText(/^Ảnh của /)).toBeVisible();
    await expect(viewer.getByText('banbe ▪︎ bạn mới mỗi tuần')).toBeVisible();

    // Liking the photo and saving its event both stick, and neither closes
    // the viewer out from under the tap.
    await viewer.getByTestId('photo-like').click();
    await expect(viewer).toBeVisible();
    await viewer.getByTestId('photo-save-event').click();
    await expect(viewer).toBeVisible();

    // A left swipe moves to the next photo in the gallery instead of
    // closing the viewer.
    const image = viewer.getByTestId('photo-viewer-image');
    await expect(image).toHaveAttribute('data-index', '0');
    const box = await image.boundingBox();
    await page.mouse.move(box.x + box.width - 10, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + 10, box.y + box.height / 2, { steps: 8 });
    await page.mouse.up();
    await expect(viewer).toBeVisible();
    await expect(image).toHaveAttribute('data-index', '1');

    // ...and a right swipe moves back.
    await page.mouse.move(box.x + 10, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width - 10, box.y + box.height / 2, { steps: 8 });
    await page.mouse.up();
    await expect(image).toHaveAttribute('data-index', '0');

    // Tapping anywhere else (no movement) closes it, leaving the event
    // underneath.
    await viewer.click({ position: { x: 5, y: 5 } });
    await expect(viewer).toHaveCount(0);
    await expect(eventScreen).toBeVisible();

    // The save landed on the real favourites list, not just the icon.
    await page.getByText('‹ banbe').first().click();
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]').getByTestId('account-saved-card')).toContainText('1');
  });

  test('a shared "?org=" link opens that organizer and offers the app', async ({ page }) => {
    await page.goto('/?org=bepnho');
    const organizerScreen = page.locator('[data-screen-label="Organizer"]');
    await expect(organizerScreen).toBeVisible({ timeout: 5000 });
    await expect(organizerScreen.getByText('Bếp Nhỏ').first()).toBeVisible();

    // The param is consumed, so re-sharing the address doesn't carry it on.
    await expect(page).toHaveURL(/^[^?]*$/);

    // Only a shared link gets the "open in the app" offer, pointing at the
    // scheme the native app registers.
    const openInApp = organizerScreen.getByRole('link', { name: 'Mở' });
    await expect(openInApp).toBeVisible();
    await expect(openInApp).toHaveAttribute('href', 'banbe://organizer/bepnho');
  });

  test('the event address opens Google Maps and offers to show distance', async ({ page, context }) => {
    await page.getByText('Bếp Nhỏ №12').first().click();
    const eventScreen = page.locator('[data-screen-label="Event"]');
    await expect(eventScreen).toBeVisible({ timeout: 3000 });

    const addressLink = eventScreen.getByRole('link', { name: /Bình Thạnh/ });
    await expect(addressLink).toBeVisible();
    const href = await addressLink.getAttribute('href');
    expect(href).toMatch(/^https:\/\/www\.google\.com\/maps\/search\/\?api=1&query=-?\d+\.\d+,-?\d+\.\d+$/);
    expect(await addressLink.getAttribute('target')).toBe('_blank');

    // Clicking it opens Maps in a new tab...
    const [popup] = await Promise.all([
      context.waitForEvent('page'),
      addressLink.click(),
    ]);
    await popup.close();

    // ...and, since location has never been decided on this device, also
    // offers to turn on distance — without blocking the maps navigation.
    await expect(page.getByText('Cho banbe biết bạn đang ở đâu?')).toBeVisible({ timeout: 3000 });
  });

  test('shows a real computed distance once location is shared', async ({ page, context }) => {
    await context.grantPermissions(['geolocation']);
    await context.setGeolocation({ latitude: 10.8, longitude: 106.7 });

    await page.getByText('Bếp Nhỏ №12').first().click();
    const eventScreen = page.locator('[data-screen-label="Event"]');
    await expect(eventScreen).toBeVisible({ timeout: 3000 });

    // Before sharing location, the placeholder distance from the demo data
    // is hidden entirely rather than shown as if it meant something.
    await expect(eventScreen.getByText(/km/)).toHaveCount(0);

    await eventScreen.getByRole('link', { name: /Bình Thạnh/ }).click();
    await page.getByText('Dùng vị trí của tôi').click();

    // 10.8000,106.7000 to this event's coordinates is ~1.6 km by the same
    // Haversine formula the app uses — a real, computed number, not the
    // static placeholder ("2,1 km") baked into the demo data.
    await expect(eventScreen.getByText(/1,6 km từ bạn/)).toBeVisible({ timeout: 3000 });

    // The same live number replaces the old static placeholder everywhere
    // else the event's distance is shown too — not just its own detail page.
    await page.getByText('‹ banbe').first().click();
    const homeScreen = page.locator('[data-screen-label="Home"]');
    await expect(homeScreen).toBeVisible({ timeout: 3000 });
    const homeCard = homeScreen.locator('div', { hasText: 'Bếp Nhỏ №12' }).first();
    await expect(homeCard.getByText(/1,6 km/)).toBeVisible();
    await expect(homeCard.getByText('2,1 km')).toHaveCount(0);
  });
});
