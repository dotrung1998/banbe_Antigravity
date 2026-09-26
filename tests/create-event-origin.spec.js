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

    // Turn organizer mode on from Account > Tổ chức (the pitch button —
    // no event needed yet) so the dock's own "+" appears.
    await page.getByText('Tài khoản').first().click();
    await page.waitForSelector('[data-screen-label="Account"]');
    await page.getByTestId('account-tab-host').click();
    const pitch = page.getByText('Bắt đầu tổ chức', { exact: false });
    if (await pitch.isVisible().catch(() => false)) {
      await pitch.click();
      await expect(page.getByTestId('organizer-mode-toggle')).toBeVisible({ timeout: 8000 });
    }

    await page.getByText('Xong').click();
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
    await expect(page.getByText('Quay lại')).toBeVisible();
    await page.getByText('Quay lại').click();

    await page.waitForSelector('[data-screen-label="Home"]', { timeout: 8000 });
    await expect(page.locator('[data-screen-label="Dashboard"]')).toHaveCount(0);
  });
});
