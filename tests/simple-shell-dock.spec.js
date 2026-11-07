// @ts-check
import { test, expect } from '@playwright/test';

// Simple Shell follow-up (note 66, item 3): the dock bubble no longer snaps back over the centre "+". A drag released
// over "+" opens the "+" sheet (the same open a tap uses) and the current tab stays selected; a drag across "+" to a
// tab still lands on that tab. Guest browsing (note 49) with `simple_shell` mocked ON (tests/rewards-switch.spec.js
// pattern), so no account is needed. A guest can only rest on Home among the dock tabs (the others ask to sign in),
// so the drags start on Home.
test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

const json = (body) => ({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });

/** @param {import('@playwright/test').Page} page */
async function openGuestShellHome(page) {
  await page.route('**/rest/v1/rpc/get_feature_flags', (r) => r.fulfill(json({ simple_shell: true })));
  await page.goto('/');
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('lang-en').isVisible().catch(() => false)) { await page.getByTestId('lang-en').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('onboarding-continue').isVisible().catch(() => false)) { await page.getByTestId('onboarding-continue').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('welcome-explore').isVisible().catch(() => false)) { await page.getByTestId('welcome-explore').click(); break; }
    if (await page.locator('[data-screen-label="Home"]').isVisible().catch(() => false)) break;
    await page.waitForTimeout(400);
  }
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 20000 });
  await expect(page.getByTestId('dock-create-button')).toBeVisible({ timeout: 10000 });
}

/** Press on `from`, move in steps to `to` (x only, the bar's middle line), optionally release. */
async function dragAcross(page, from, to, { release = true, steps = 10 } = {}) {
  const bar = await page.getByTestId('bottom-tab-bar').boundingBox();
  const y = bar.y + bar.height / 2;
  await page.mouse.move(from, y);
  await page.mouse.down();
  for (let i = 1; i <= steps; i++) await page.mouse.move(from + (to - from) * (i / steps), y);
  if (release) await page.mouse.up();
}
const centreX = (b) => b.x + b.width / 2;

test.describe('Simple Shell dock', () => {
  test('a tap on "+" opens the sheet; Escape closes it', async ({ page }) => {
    await openGuestShellHome(page);
    await page.getByTestId('dock-create-button').click();
    await expect(page.getByTestId('dock-create-menu')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.getByTestId('dock-create-menu')).toHaveCount(0);
    await expect(page.getByTestId('tab-home')).toHaveAttribute('aria-selected', 'true');
  });

  test('regression: a drag released over "+" opens the sheet and Home stays selected', async ({ page }) => {
    await openGuestShellHome(page);
    const home = await page.getByTestId('tab-home').boundingBox();
    const plus = await page.getByTestId('dock-create-button').boundingBox();
    await dragAcross(page, centreX(home), centreX(plus), { release: false });
    // Mid-drag over "+": the "+" looks pressed and no tab is highlighted.
    await expect(page.getByTestId('dock-create-button')).toHaveAttribute('data-pressed', 'true');
    await expect(page.locator('[data-testid^="tab-"][aria-selected="true"]')).toHaveCount(0);
    await page.mouse.up();

    await expect(page.getByTestId('dock-create-menu')).toBeVisible();
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
    await expect(page.getByTestId('tab-home')).toHaveAttribute('aria-selected', 'true');
    await expect(page.getByTestId('dock-create-button')).not.toHaveAttribute('data-pressed', 'true');
    await page.getByTestId('dock-create-backdrop').click({ position: { x: 20, y: 40 } });
    await expect(page.getByTestId('dock-create-menu')).toHaveCount(0);
    await expect(page.getByTestId('tab-home')).toHaveAttribute('aria-selected', 'true');
  });

  test('a drag from Home across "+" to Messages lands on Messages, not the sheet', async ({ page }) => {
    await openGuestShellHome(page);
    const home = await page.getByTestId('tab-home').boundingBox();
    const inbox = await page.getByTestId('tab-inbox').boundingBox();
    await dragAcross(page, centreX(home), centreX(inbox));
    await expect(page.getByTestId('dock-create-menu')).toHaveCount(0);
    // A guest opening Messages is asked to log in first (note 49); a signed-in account lands on Inbox.
    await expect(page.locator('[data-screen-label="Login"], [data-screen-label="Inbox"]')).toBeVisible({ timeout: 5000 });
  });
});
