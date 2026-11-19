# 100 — Home parity: Near you rule, Happening-now time, footer, scroll on type pick (2026-11-19)

Owner screenshots: same account, web vs iOS Home showed different events and different bottoms.

## Fixes
1. **"7.0189…h ago" on the Happening-now card (web).** `hoursSince()` (`src/lib/countdown.js`) returned a float that
   `agoLabel` printed raw; now floored (also guarded in `agoLabel`). The catalogue branch of `savedList` in `Home.jsx`
   set a reminder without checking `endedHoursAgo`/`cancelled`, so a card could be "Happening now" + "ended N h ago";
   now a reminder needs both clear and its status is the start weekday/date ▪ time (as iOS). iOS was already right.
2. **iOS Home bottom = web:** map card → "banbe · pick an evening…" → "Help Shape Upcoming Events" (display 20,
   collapsed). The tagline paragraph and "Your host page ›" are gone on iOS; the host link is also gone from web Home.
3. **Type tile tap scrolls "Near you" to the top** under the folded bar (web `pickTypeAndAlign` in `Home.jsx`, offset
   58 + 8 inside the scroll viewport; iOS `alignNearYouAfterPick()` bumps `nearYouScrollToken`). Unified-discovery
   grid only. Reduce Motion = instant.
4. **Near you differed (web 15 / iOS 7, Music 3 vs 0, map count 4 vs 16).** One rule now, `nearYou` + `isOpenItem` in
   `src/lib/unifiedDiscovery.js` ⇄ `Lib/UnifiedDiscovery.swift`, fixture `tests/fixtures/unified-discovery.json` →
   `nearYou`: open events (not cancelled, end not passed, else start + 12 h), Home filters (+ tab time with unified
   discovery), soonest first, "See on the map · N" = list count. Root causes: iOS used the For You ranking as the list;
   web kept the For You order under "soonest first"; iOS had no end-time check; iOS map/type counts used another set;
   iOS showed demo-catalogue dates when the live row was missing (`discoveryStart` now uses the real discovery row);
   web For You skipped id == slug rows; web `loadHomeLiveEvents` did not select `end_time`/`end_open`.

## Verified
Web `vite build` green, `test:unit` 1043/1043. iOS `build-for-testing` green (simulator), UnifiedDiscoveryTests /
V23RulesTests / HomeDiscoveryTests 28/28. Not run: Playwright, either app side by side on live data, a device.
No migration.
