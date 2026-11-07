// @ts-check
import { test, expect } from '@playwright/test';
import { guestToHome } from './helpers.js';

// Calm Pass phase 2: goer screens never end in a dead end. Same dev-state harness as host-home-empty.spec.js.
test.use({ storageState: { cookies: [], origins: [] }, viewport: { width: 390, height: 844 } });

const devSet = (page, patch) => page.evaluate((p) => window.__banbeDevSet(p), patch);
const USER = { id: '00000000-0000-4000-8000-000000000071', name: 'Goer Test', email: 'g@example.com', handle: 'goertest' };

test('Search with no results offers See all, Clear search and the categories', async ({ page }) => {
  await guestToHome(page);
  await page.getByTestId('home-search-bar').click();
  await page.getByTestId('search-input').fill('zzzznonexistenteventzzzz');
  await expect(page.getByTestId('search-empty')).toBeVisible();
  await expect(page.locator('[data-testid^="search-empty-cat-"]').first()).toBeVisible();
  for (const id of ['search-empty-all', 'search-empty-clear']) {
    expect((await page.getByTestId(id).boundingBox()).height).toBeGreaterThanOrEqual(44);
  }
  await page.getByTestId('search-empty-clear').click();
  await expect(page.getByTestId('search-input')).toHaveValue('');
  await expect(page.getByTestId('search-empty')).toHaveCount(0);
});

test('an empty inbox explains how a conversation starts and leads to events', async ({ page }) => {
  await guestToHome(page);
  await devSet(page, { user: USER, accountType: 'participant', threads: [], disputeChats: [], inboxView: 'all', screen: 'inbox' });
  await expect(page.getByTestId('inbox-empty')).toBeVisible();
  await page.getByTestId('inbox-empty-find').click();
  await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
});

// Calm Pass phase 3 (migration 208): Home event cards as polaroids, cards view only, behind `polaroid_cards`.
test.describe('polaroid cards', () => {
  const cards = (page) => page.locator('[data-testid^="home-event-"]');

  test('off by default: the cards are unchanged', async ({ page }) => {
    await guestToHome(page);
    await expect(cards(page).first()).toBeVisible();
    await expect(page.locator('[data-polaroid="true"]')).toHaveCount(0);
  });

  for (const theme of ['light', 'dark']) {
    test(`on (${theme}): the photo is inset in a mat, Save and the caption stay`, async ({ page }) => {
      await guestToHome(page);
      await devSet(page, { featureFlags: { polaroid_cards: true }, theme });
      await expect(page.locator('.bb-stage')).toHaveAttribute('data-bb-theme', theme);
      const card = cards(page).first();
      const frame = card.locator('[data-polaroid="true"]');
      await expect(frame).toBeVisible();
      await expect(frame).toHaveCSS('padding-top', '8px');
      await expect(card.locator('[data-testid^="home-save-"]')).toBeVisible();
      const mat = await frame.evaluate(el => getComputedStyle(el).backgroundColor);
      expect(mat).toBe(theme === 'light' ? 'rgb(251, 248, 241)' : 'rgb(36, 33, 28)');
    });
  }
});
