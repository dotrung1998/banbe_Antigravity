// Event Detail V8 tabs (note 75): which tabs show and which one is active for a scroll position. Pure logic, mirrored by
// apps/ios/BanbeApp/Lib/EventDetailTabs.swift through tests/fixtures/event-detail-tabs.json (tests:
// tests/unit/eventDetailTabs.test.mjs and apps/ios/BanbeAppTests/EventDetailTabsTests.swift) — change both together.

/** Section ids in page order. */
export const TAB_IDS = ['overview', 'menu', 'host', 'photos', 'safe'];

/** The tabs to show: Overview always; the others only when their section has content (never a tab to an empty one). */
export function visibleTabs({ hasMenu = false, hasHost = false, hasPhotos = false, hasProtection = false } = {}) {
  const on = { overview: true, menu: hasMenu, host: hasHost, photos: hasPhotos, safe: hasProtection };
  return TAB_IDS.filter(id => on[id]);
}

/**
 * Index of the active tab. `tops[i]` = the scroll offset at which section i sits right under the nav bar;
 * `lead` = how far ahead of that a section takes over. Sections near the end that can never scroll that far get their
 * thresholds spread evenly over the scroll that is left, so each one is still selected on the way down; at the very
 * bottom the last tab is always active (V8 `spy`).
 */
export function activeTab(tops = [], scrollTop = 0, maxScroll = 0, lead = 0) {
  const n = tops.length;
  if (!n) return -1;
  const a = tops.map(o => Math.max(0, o - lead));
  let last = 0;
  a.forEach((v, i) => { if (v <= maxScroll - 4) last = i; });
  const un = n - 1 - last;
  for (let k = 1; k <= un; k++) a[last + k] = a[last] + (Math.max(maxScroll, a[last]) - a[last]) * k / un;
  let act = 0;
  a.forEach((v, i) => { if (scrollTop >= v - 1) act = i; });
  if (maxScroll > 0 && scrollTop >= maxScroll - 2) act = n - 1;
  return act;
}
