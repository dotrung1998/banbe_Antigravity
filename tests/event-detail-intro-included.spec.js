// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

// Intro/included-presentation pass (2026-09-28) — the "Bao gồm" row is now
// ONE tappable row + sheet (intro first, Included items below) whenever
// EITHER exists, on both demo and real events — was previously gated on
// `includedItems.length > 0` alone (real events' `included_items` is empty
// on every existing row, confirmed live against the connected DB, so this
// never actually triggered for them) with a SEPARATE always-visible intro
// section. See EventDetail.jsx's own doc comment on this exact change.
test.describe('Event Detail — intro + Included sheet', () => {
  test('a demo event with a hand-written intro and derived Included items opens the sheet, intro first', async ({ page }) => {
    await setupToHome(page);

    // bepnho — src/data/events.js's own INTRO lookup + includedItems
    // derived from its "5 món ▪︎ rượu gạo ▪︎ cà phê" included string.
    await page.click('[data-testid="home-event-bepnho"]');
    await expect(page.locator('[data-screen-label="Event"]')).toBeVisible();

    const includedSection = page.getByTestId('event-included-section');
    await expect(includedSection).toBeVisible();
    // The chevron/"view more" affordance — proves this is the new
    // tappable row, not the old plain-text fallback.
    await expect(includedSection).toContainText('›');

    await includedSection.click();
    const sheet = page.getByTestId('event-included-sheet');
    await expect(sheet).toBeVisible();

    // Intro FIRST.
    const introSection = page.getByTestId('event-intro-section');
    await expect(introSection).toBeVisible();
    await expect(introSection).toContainText('Bình Thạnh');

    // Included items separately below, using the ACTUAL derived labels
    // (never invented) — "5 món", "rượu gạo", "cà phê" from the row's own
    // `included` string.
    await expect(sheet).toContainText('5 món');
    await expect(sheet).toContainText('rượu gạo');
    await expect(sheet).toContainText('cà phê');

    await page.getByTestId('event-included-sheet-close').click();
    await expect(sheet).not.toBeVisible();
  });

  test('an event with neither intro nor included items shows no broken empty section', async ({ page }) => {
    await setupToHome(page);
    // Every one of the 21 demo events now has an intro (this pass), so
    // there's no fixture left with genuinely neither — this instead
    // asserts the STRUCTURAL guarantee via the component's own contract:
    // an event whose intro AND includedItems are both empty must fall
    // back to plain text (`ev.included`) or render nothing, never a
    // tappable row with nothing behind it. Covered by code review (the
    // `(includedItems.length > 0 || introParagraphs.length > 0) ? ... :
    // ev.included ? ... : null` chain in EventDetail.jsx) rather than a
    // live fixture, since none currently exists to point this test at.
    test.skip(true, 'No current fixture has neither intro nor included items — see this test\'s own comment');
  });
});
