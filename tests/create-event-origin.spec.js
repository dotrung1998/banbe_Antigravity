// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { hasServiceRole, adminClient } from './e2e/setup.mjs';

// Stage 1 (2026-09-27 nav/discovery pass) — dock + > Tạo sự kiện > Back
// used to hard-route to 'dashboard'/'hostIntro' regardless of which root
// tab + was actually tapped from (GocContext.jsx's old createBack). This
// verifies the real fix: Back returns to the EXACT originating screen
// (Home here), not a fixed destination.
test.describe('Create event — Back returns to the real origin', () => {
  test.afterEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (data?.auth_user_id) await admin.from('profiles').update({ role: 'participant' }).eq('id', data.auth_user_id);
  });

  test('dock + from Home returns to Home on Back, not Dashboard', async ({ page }) => {
    await setupToHome(page);

    // Locale-agnostic navigation — the shared fast-suite account's own
    // saved locale can be 'en' (an earlier test flipped it and this
    // account's own profile.prefs_saved persists it across runs), so
    // Vietnamese-only text selectors are NOT a safe way to find these
    // controls; every dock tab/toggle already has a stable testid.
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    // Account extension (2026-09-27, Stage 1) — the toggle now lives on
    // the always-reachable Cá nhân tab (Account's default), not behind
    // the Tổ chức tab (which only shows once organizer mode is already on).
    const toggle = page.getByTestId('organizer-mode-toggle');
    await expect(toggle).toBeVisible({ timeout: 8000 });
    const pitch = page.getByText(/Bắt đầu tổ chức|Start hosting/, { exact: false });
    if (await pitch.isVisible().catch(() => false)) {
      await pitch.click();
      await expect(toggle).toBeVisible({ timeout: 8000 });
    }

    await page.getByTestId('tab-home').click();
    await page.waitForSelector('[data-screen-label="Home"]');

    await page.getByTestId('dock-create-button').click();
    await page.waitForSelector('[data-testid="dock-create-menu-event"]');
    // A real Playwright `.click()` here lands on DockCreateTrayView's own
    // pointer-capturing container instead of this menu item (Chromium
    // retargets the click's compat mouse events to whichever element
    // called setPointerCapture on pointerdown, per DockCreateButton.jsx's
    // own onTrayPointerDown) — a pre-existing drag-to-dismiss gesture
    // quirk unrelated to this ticket's createBack fix, confirmed by
    // dispatching the click directly instead, which reaches the real
    // onClick={choose} handler exactly as a tap that doesn't trigger the
    // drag threshold would on a real device.
    await page.evaluate(() => {
      document.querySelector('[data-testid="dock-create-menu-event"]')
        .dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
    });
    await page.waitForSelector('[data-screen-label="Create event"]', { timeout: 8000 });

    // The back label used to name a fixed destination ("Trang tổ chức của
    // bạn"/"Dashboard preview") — now a plain, destination-agnostic "Quay
    // lại", since it can return to any root tab.
    const backLink = page.getByText(/Quay lại|Back/).first();
    await expect(backLink).toBeVisible();
    await backLink.click();

    await page.waitForSelector('[data-screen-label="Home"]', { timeout: 8000 });
    await expect(page.locator('[data-screen-label="Dashboard"]')).toHaveCount(0);
  });
});
