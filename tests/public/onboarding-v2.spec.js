// @ts-check
import { test, expect } from '@playwright/test';

// Note 63: the admin switch `onboarding_v2` picks the public onboarding. get_feature_flags is answered at the
// network edge; nothing else is mocked and nothing is written anywhere.
//   V1 = still Welcome + 4 text pages (welcome-story-points);
//   V2 = animated Welcome entrance + per-section swipeable demo deck (hiw-deck), Next/Skip, CTAs on the last page.
const json = (body) => ({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
const SHOTS = process.env.HIW_SHOTS; // optional folder for review screenshots
test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

async function openWelcome(page, flags) {
  await page.route('**/rest/v1/rpc/get_feature_flags', (r) => r.fulfill(json(flags)));
  // Seed the device cache too, so the very first paint already follows the switch (as on a returning device).
  await page.addInitScript((f) => { try { localStorage.setItem('banbe_feature_flags_v1', JSON.stringify(f)); } catch { /* */ } }, flags);
  await page.goto('/');
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('lang-en').isVisible().catch(() => false)) { await page.getByTestId('lang-en').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('onboarding-continue').isVisible().catch(() => false)) { await page.getByTestId('onboarding-continue').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('welcome-title').isVisible().catch(() => false)) break;
    await page.waitForTimeout(300);
  }
  await expect(page.getByTestId('welcome-title')).toBeVisible();
}

test('Version 1 (switch off): still welcome, text pages', async ({ page }) => {
  await openWelcome(page, { onboarding_v2: false });
  await expect(page.getByTestId('welcome-illustration')).toHaveAttribute('data-animated', 'false');
  await page.getByTestId('welcome-story').click();
  await expect(page.getByTestId('welcome-story-points')).toBeVisible();
  await expect(page.getByTestId('hiw-deck')).toHaveCount(0);
});

test('Version 2 (switch on): animated entrance, swipeable deck, Next through 4 sections, CTAs at the end', async ({ page }) => {
  await openWelcome(page, { onboarding_v2: true });
  await expect(page.getByTestId('welcome-illustration')).toHaveAttribute('data-animated', 'true');
  if (SHOTS) { await page.waitForTimeout(350); await page.screenshot({ path: `${SHOTS}/welcome-mid.png` }); }
  await page.waitForTimeout(2200); // entrance done
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/welcome-end.png` });

  await page.getByTestId('welcome-story').click();
  const deck = page.getByTestId('hiw-deck');
  await expect(deck).toBeVisible();
  await expect(page.getByTestId('hiw-card-0')).toHaveAttribute('data-active', 'true');
  const caption0 = await page.getByTestId('hiw-caption').innerText();

  // Keyboard swipe moves the focus card and the caption follows.
  await deck.focus();
  await page.keyboard.press('ArrowRight');
  await expect(page.getByTestId('hiw-card-1')).toHaveAttribute('data-active', 'true');
  await expect(page.getByTestId('hiw-caption')).not.toHaveText(caption0);
  // Neighbours are dimmed.
  const op = await page.getByTestId('hiw-card-0').evaluate((n) => Number(getComputedStyle(n).opacity));
  expect(op).toBeLessThan(0.7);
  if (SHOTS) { await page.waitForTimeout(1200); await page.screenshot({ path: `${SHOTS}/story-1.png` }); }

  for (let s = 2; s <= 4; s++) {
    await page.getByTestId('welcome-story-next').click();
    await expect(page.getByTestId('welcome-story-progress')).toHaveText(`${s}/4`);
    await expect(page.getByTestId('hiw-card-0')).toHaveAttribute('data-active', 'true');
    if (SHOTS) { await page.waitForTimeout(1500); await page.screenshot({ path: `${SHOTS}/story-${s}.png` }); }
  }
  await expect(page.getByTestId('welcome-story-next')).toHaveCount(0);
  await expect(page.getByTestId('welcome-explore')).toBeVisible();
});

test('Version 2: the demo controls respond (ticket count changes the total)', async ({ page }) => {
  await openWelcome(page, { onboarding_v2: true });
  await page.getByTestId('welcome-story').click();
  await page.getByTestId('welcome-story-next').click();
  const card = page.getByTestId('hiw-card-0');
  const before = await card.innerText();
  await page.getByTestId('hiw-tickets-3').click();
  await expect(page.getByTestId('hiw-tickets-3')).toHaveAttribute('aria-pressed', 'true');
  expect(await card.innerText()).not.toEqual(before);
});

test('Version 2: Skip closes the story back to Welcome', async ({ page }) => {
  await openWelcome(page, { onboarding_v2: true });
  await page.getByTestId('welcome-story').click();
  await page.getByTestId('welcome-story-skip').click();
  await expect(page.getByTestId('welcome-title')).toBeVisible();
  // Coming back from the story does not replay the entrance.
  await expect(page.getByTestId('welcome-illustration')).toHaveAttribute('data-animated', 'false');
});

test('Version 2: last screen of the last section bounces a finish hint; finishing shows the thank-you with the CTAs', async ({ page }) => {
  await openWelcome(page, { onboarding_v2: true });
  await page.getByTestId('welcome-story').click();
  for (let s = 2; s <= 4; s++) await page.getByTestId('welcome-story-next').click();
  const deck = page.getByTestId('hiw-deck');
  await deck.focus();
  for (let i = 1; i <= 6; i++) {
    await page.keyboard.press('ArrowRight');
    await expect(page.getByTestId(`hiw-card-${i}`)).toHaveAttribute('data-active', 'true');
  }
  await expect(page.getByTestId('hiw-card-6')).toHaveAttribute('data-active', 'true');
  await expect(page.getByTestId('hiw-finish-hint')).toBeVisible();
  await expect(page.getByTestId('hiw-next-section-hint')).toHaveCount(0);
  if (SHOTS) { await page.waitForTimeout(800); await page.screenshot({ path: `${SHOTS}/finish-hint.png` }); }
  await page.getByTestId('hiw-finish-hint').click({ force: true }); // it never stops bouncing
  await expect(page.getByTestId('hiw-thanks')).toBeVisible();
  await expect(page.getByTestId('welcome-explore')).toBeVisible();
  if (SHOTS) { await page.waitForTimeout(1200); await page.screenshot({ path: `${SHOTS}/thanks.png` }); }
});
