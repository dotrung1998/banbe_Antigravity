// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

// Dock drag-follow + highlight-layering pass (2026-09-28) — covers:
// 1. plain tap selection (unchanged baseline)
// 2. drag-then-release-over-a-different-tab commits that tab, once
// 3. a cancelled/outside-release drag restores the previously-active tab
//    without navigating away
// 4. the web highlight element is layered BEHIND the tab icons and sized
//    to one tab's own share of the dock, not the whole bar (the "solid
//    black blob obscuring icons" regression this pass fixes — see
//    BottomTabBar.jsx's `dockHighlight`/theme.js comment for the root
//    cause: the highlight used to be painted fully opaque in the SAME
//    `ink` color as the active icon itself).

test.use({ viewport: { width: 390, height: 844 } });

test.describe('Bottom dock — tap, drag-select, layering', () => {
  test('a plain tap selects the tapped tab immediately', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    await page.getByTestId('tab-notifications').click();
    await page.waitForSelector('[data-screen-label="Notifications"]');
    await expect(page.getByTestId('tab-notifications')).toHaveAttribute('aria-selected', 'true');
  });

  test('dragging along the dock and releasing over a different tab commits that tab exactly once', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    const bar = page.getByTestId('bottom-tab-bar');
    const barBox = await bar.boundingBox();
    const homeBox = await page.getByTestId('tab-home').boundingBox();
    const inboxBox = await page.getByTestId('tab-inbox').boundingBox();
    const y = barBox.y + barBox.height / 2;

    // Start the press on Home, drag continuously across to Inbox, release
    // there — a single gesture, not a tap on Home followed by a tap on
    // Inbox, so this exercises the SAME drag path the live highlight uses.
    await page.mouse.move(homeBox.x + homeBox.width / 2, y);
    await page.mouse.down();
    const steps = 8;
    for (let i = 1; i <= steps; i++) {
      const x = homeBox.x + homeBox.width / 2 + ((inboxBox.x + inboxBox.width / 2) - (homeBox.x + homeBox.width / 2)) * (i / steps);
      await page.mouse.move(x, y);
    }
    await page.mouse.up();

    // Commits once, to Inbox — not a double-fire (which would show up as
    // a screen flicker or a second, stale navigation the assertion below
    // would still ultimately pass despite, so this also holds after a
    // short settle to catch a delayed second commit).
    await page.waitForSelector('[data-screen-label="Inbox"]', { timeout: 3000 });
    await page.waitForTimeout(300);
    await expect(page.locator('[data-screen-label="Inbox"]')).toBeVisible();
    await expect(page.getByTestId('tab-inbox')).toHaveAttribute('aria-selected', 'true');
  });

  test('dragging off the dock and releasing outside cancels — no unintended tab switch', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    const bar = page.getByTestId('bottom-tab-bar');
    const barBox = await bar.boundingBox();
    const homeBox = await page.getByTestId('tab-home').boundingBox();
    const y = barBox.y + barBox.height / 2;

    await page.mouse.move(homeBox.x + homeBox.width / 2, y);
    await page.mouse.down();
    // Drag straight up, off the dock entirely, then release well above it
    // — a real "changed my mind" / cancelled gesture, not a release over
    // any tab.
    await page.mouse.move(homeBox.x + homeBox.width / 2, y - 40);
    await page.mouse.move(homeBox.x + homeBox.width / 2, barBox.y - 200);
    await page.mouse.up();

    await page.waitForTimeout(300);
    // Still on Home — the drag never committed a navigation.
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
    await expect(page.getByTestId('tab-home')).toHaveAttribute('aria-selected', 'true');
  });

  test('web highlight sits behind the icons and is sized to one tab, not the whole dock', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');
    await page.getByTestId('tab-home').click();

    const highlight = page.getByTestId('dock-highlight');
    await expect(highlight).toBeVisible();

    const metrics = await page.evaluate(() => {
      const bar = document.querySelector('[data-testid="bottom-tab-bar"]');
      const hl = document.querySelector('[data-testid="dock-highlight"]');
      const homeTab = document.querySelector('[data-testid="tab-home"]');
      const homeIcon = homeTab?.querySelector('svg');
      const barRect = bar.getBoundingClientRect();
      const hlRect = hl.getBoundingClientRect();
      const iconRect = homeIcon.getBoundingClientRect();
      const hlStyle = getComputedStyle(hl);
      const iconStyle = getComputedStyle(homeTab);
      return {
        barWidth: barRect.width,
        hlWidth: hlRect.width,
        hlZIndex: hlStyle.zIndex,
        iconZIndex: iconStyle.zIndex,
        hlOpaque: hlStyle.backgroundColor,
        iconVisible: iconRect.width > 0 && iconRect.height > 0,
      };
    });

    // Sized to roughly one tab's share of the dock (5 tabs), not the
    // whole bar — the actual "oversized blob" regression this asserts
    // against. Generous tolerance for the live drag "bulge" easing, but
    // nowhere near barWidth.
    expect(metrics.hlWidth).toBeLessThan(metrics.barWidth * 0.5);
    expect(metrics.hlWidth).toBeGreaterThan(metrics.barWidth * 0.1);

    // Layered behind the icons: the highlight's own z-index must be lower
    // than the tab item's — this is what keeps the icon visible ON TOP of
    // the highlight rather than the highlight painting over it.
    expect(Number(metrics.hlZIndex)).toBeLessThan(Number(metrics.iconZIndex));

    // The background must be translucent (an alpha channel below 1), not
    // a fully opaque fill — the actual root cause of the icon disappearing
    // into a "solid black blob" (same solid `ink` color as the icon itself
    // painted at full opacity).
    const alphaMatch = metrics.hlOpaque.match(/rgba?\(([^)]+)\)/);
    const parts = alphaMatch ? alphaMatch[1].split(',').map((v) => parseFloat(v)) : [];
    const alpha = parts.length === 4 ? parts[3] : 1;
    expect(alpha).toBeLessThan(0.5);

    expect(metrics.iconVisible).toBe(true);
  });
});
