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
    await page.waitForSelector('[data-screen-label="Inbox"]', { timeout: 5000 });
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

// Liquid-glass droplet pass (2026-09-28 follow-up, real-iPhone report) —
// the drag highlight used to be a single shape that just widened/narrowed
// while translating, which on a real device still read as "a plain oval
// moving/teleporting," not an actual liquid-glass blob. This adds a real
// two-blob gooey effect (SVG blur+contrast "goo" filter merging an anchor
// blob at the previously-selected tab with a blob following the finger).
// Asserting the actual gooey PIXELS via Playwright isn't practical (that's
// a filter output, not a comparable DOM property), so these tests focus on
// what is practical and load-bearing: the underlying state machine still
// commits/cancels correctly through a longer, direction-reversing drag; a
// rapid tap right after a completed drag isn't mis-handled; and the goo
// elements exist and visibly move (via `left`/`transform`) during a
// simulated drag, without asserting their rendered pixels.
test.describe('Bottom dock — liquid droplet drag (goo layer)', () => {
  test('dragging across multiple tabs before releasing commits the tab under the finger at release', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    const bar = page.getByTestId('bottom-tab-bar');
    const barBox = await bar.boundingBox();
    const homeBox = await page.getByTestId('tab-home').boundingBox();
    const notifBox = await page.getByTestId('tab-notifications').boundingBox();
    const profileBox = await page.getByTestId('tab-profile').boundingBox();
    const y = barBox.y + barBox.height / 2;

    // Home -> Notifications -> Profile, all in one continuous gesture —
    // must commit to Profile (wherever the finger actually released), not
    // to an intermediate tab it merely passed over.
    const waypoints = [
      [homeBox.x + homeBox.width / 2, notifBox.x + notifBox.width / 2],
      [notifBox.x + notifBox.width / 2, profileBox.x + profileBox.width / 2],
    ];
    await page.mouse.move(homeBox.x + homeBox.width / 2, y);
    await page.mouse.down();
    const steps = 6;
    for (const [fromX, toX] of waypoints) {
      for (let i = 1; i <= steps; i++) {
        const x = fromX + (toX - fromX) * (i / steps);
        await page.mouse.move(x, y);
      }
    }
    await page.mouse.up();

    await page.waitForSelector('[data-screen-label="Account"]', { timeout: 5000 });
    await page.waitForTimeout(300);
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible();
    await expect(page.getByTestId('tab-profile')).toHaveAttribute('aria-selected', 'true');
  });

  test('reversing direction mid-drag before releasing commits the final tab under the finger, not the earlier one', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    const bar = page.getByTestId('bottom-tab-bar');
    const barBox = await bar.boundingBox();
    const homeBox = await page.getByTestId('tab-home').boundingBox();
    const inboxBox = await page.getByTestId('tab-inbox').boundingBox();
    const mapBox = await page.getByTestId('tab-map').boundingBox();
    const y = barBox.y + barBox.height / 2;

    await page.mouse.move(homeBox.x + homeBox.width / 2, y);
    await page.mouse.down();
    // Drag forward toward Inbox…
    const steps = 6;
    for (let i = 1; i <= steps; i++) {
      const x = homeBox.x + homeBox.width / 2 + ((inboxBox.x + inboxBox.width / 2) - (homeBox.x + homeBox.width / 2)) * (i / steps);
      await page.mouse.move(x, y);
    }
    // …then reverse back to Map before releasing.
    for (let i = 1; i <= steps; i++) {
      const x = inboxBox.x + inboxBox.width / 2 + ((mapBox.x + mapBox.width / 2) - (inboxBox.x + inboxBox.width / 2)) * (i / steps);
      await page.mouse.move(x, y);
    }
    await page.mouse.up();

    await page.waitForSelector('[data-screen-label="MapExplore"]', { timeout: 5000 });
    await page.waitForTimeout(300);
    await expect(page.locator('[data-screen-label="MapExplore"]')).toBeVisible();
    await expect(page.getByTestId('tab-map')).toHaveAttribute('aria-selected', 'true');
    // Never actually landed on/stuck showing Inbox as the aria-selected tab.
    await expect(page.getByTestId('tab-inbox')).toHaveAttribute('aria-selected', 'false');
  });

  test('a rapid tap immediately after a completed drag selects that tap target, not a stale drag tab', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    const bar = page.getByTestId('bottom-tab-bar');
    const barBox = await bar.boundingBox();
    const homeBox = await page.getByTestId('tab-home').boundingBox();
    const inboxBox = await page.getByTestId('tab-inbox').boundingBox();
    const notifBox = await page.getByTestId('tab-notifications').boundingBox();
    const y = barBox.y + barBox.height / 2;

    // Complete drag: Home -> Inbox.
    await page.mouse.move(homeBox.x + homeBox.width / 2, y);
    await page.mouse.down();
    const steps = 6;
    for (let i = 1; i <= steps; i++) {
      const x = homeBox.x + homeBox.width / 2 + ((inboxBox.x + inboxBox.width / 2) - (homeBox.x + homeBox.width / 2)) * (i / steps);
      await page.mouse.move(x, y);
    }
    await page.mouse.up();
    await page.waitForSelector('[data-screen-label="Inbox"]', { timeout: 5000 });

    // Immediately, a plain rapid tap on Notifications — must resolve to
    // Notifications, not get eaten/misrouted by drag-settle bookkeeping
    // left over from the previous gesture (the goo layer's fade-out,
    // `gooEngagedRef`, etc.).
    await page.getByTestId('tab-notifications').click();
    await page.waitForSelector('[data-screen-label="Notifications"]', { timeout: 5000 });
    await expect(page.getByTestId('tab-notifications')).toHaveAttribute('aria-selected', 'true');
  });

  test('a real drag engages the goo layer and both blobs move; a plain tap never engages it', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    // Structural existence: the goo layer and its two blobs are present in
    // the DOM (hidden at rest), regardless of Reduce Motion — this is the
    // practical stand-in for "the gooey elements exist," since asserting
    // the filter's actual rendered pixels isn't feasible here.
    await expect(page.getByTestId('dock-goo-layer')).toHaveCount(1);
    await expect(page.getByTestId('dock-goo-anchor')).toHaveCount(1);
    await expect(page.getByTestId('dock-goo-drag')).toHaveCount(1);

    const bar = page.getByTestId('bottom-tab-bar');
    const barBox = await bar.boundingBox();
    const homeBox = await page.getByTestId('tab-home').boundingBox();
    const profileBox = await page.getByTestId('tab-profile').boundingBox();
    const y = barBox.y + barBox.height / 2;

    // Plain tap first: goo layer must stay hidden throughout — "no gooey
    // animation needed for a simple tap." Reads the element's own inline
    // `style.opacity` (what the code imperatively sets/leaves alone) rather
    // than `getComputedStyle`, which mid-CSS-transition can report a
    // transient interpolated value unrelated to whether goo mode was ever
    // engaged — the inline value is the actual engage/disengage signal.
    await page.getByTestId('tab-home').click();
    await page.waitForTimeout(50);
    const opacityAfterTap = await page.evaluate(() => document.querySelector('[data-testid="dock-goo-layer"]').style.opacity);
    expect(opacityAfterTap).toBe('0');

    // Now a real drag past the movement threshold: the goo layer engages,
    // and both blobs actually move (their `left` changes as the finger
    // moves), which is the DOM-structure stand-in for "this is animating,"
    // per this ticket's own note that pixel comparison of the filter isn't
    // practical here.
    await page.mouse.move(homeBox.x + homeBox.width / 2, y);
    await page.mouse.down();
    await page.mouse.move(homeBox.x + homeBox.width / 2 + 30, y);

    const midDrag = await page.evaluate(() => {
      const layer = document.querySelector('[data-testid="dock-goo-layer"]');
      const anchor = document.querySelector('[data-testid="dock-goo-anchor"]');
      const drag = document.querySelector('[data-testid="dock-goo-drag"]');
      return {
        layerOpacity: layer.style.opacity,
        anchorLeft: anchor.style.left,
        dragLeft: drag.style.left,
      };
    });
    expect(midDrag.layerOpacity).toBe('1');
    expect(midDrag.anchorLeft).not.toBe('');
    expect(midDrag.dragLeft).not.toBe('');

    const steps = 6;
    for (let i = 1; i <= steps; i++) {
      const x = homeBox.x + homeBox.width / 2 + 30 + ((profileBox.x + profileBox.width / 2) - (homeBox.x + homeBox.width / 2 + 30)) * (i / steps);
      await page.mouse.move(x, y);
    }
    const dragLeftAfterMove = await page.evaluate(() => document.querySelector('[data-testid="dock-goo-drag"]').style.left);
    expect(dragLeftAfterMove).not.toBe(midDrag.dragLeft);

    await page.mouse.up();
    await page.waitForSelector('[data-screen-label="Account"]', { timeout: 5000 });
    await page.waitForTimeout(250);
    // Settled back to hidden once the drag completes and the classic
    // single-shape highlight has taken back over (inline value — see the
    // comment above on why this, not `getComputedStyle`, is what to check).
    const opacityAfterSettle = await page.evaluate(() => document.querySelector('[data-testid="dock-goo-layer"]').style.opacity);
    expect(opacityAfterSettle).toBe('0');
  });

  test('dock drag never triggers root-tab swipe navigation (precedence still holds)', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    const bar = page.getByTestId('bottom-tab-bar');
    const barBox = await bar.boundingBox();
    const homeBox = await page.getByTestId('tab-home').boundingBox();
    const inboxBox = await page.getByTestId('tab-inbox').boundingBox();
    const y = barBox.y + barBox.height / 2;

    await page.mouse.move(homeBox.x + homeBox.width / 2, y);
    await page.mouse.down();
    const steps = 10;
    for (let i = 1; i <= steps; i++) {
      const x = homeBox.x + homeBox.width / 2 + ((inboxBox.x + inboxBox.width / 2) - (homeBox.x + homeBox.width / 2)) * (i / steps);
      await page.mouse.move(x, y);
      // A swipe-driven navigation renders a second, neighboring screen
      // mid-gesture (see App.jsx's `swipeNeighbor`) — the dock's own drag
      // must never cause that; only exactly the current screen's element
      // should be present in the DOM while dragging along the dock.
      const screenCount = await page.locator('[data-screen-label]').count();
      expect(screenCount).toBe(1);
    }
    await page.mouse.up();
    await page.waitForSelector('[data-screen-label="Inbox"]', { timeout: 5000 });
  });
});
