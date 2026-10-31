# 71 — Calm Pass: Hosting Home guided empty states + iOS "This month" fix (phases 0–1)

Numbered 71 because another session committed its own note 70 (Event Detail story-first, e50596e) the same day. Migration 208's comment still says "note 70" (already applied, so left as is).

Direction picked 2026-10-31 from the UI direction explorer: **Calm Pass** (keep ink/paper/clay) plus two add-ons,
polaroid event cards and guided empty states. Full plan: `~/.claude/plans/mode-plan-only-no-immutable-sun.md`.
All four phases are done (2026-10-31). Migration 208 is APPLIED on production (checked read-only 2026-10-31:
`polaroid_cards` defined, enabled = false).

## Root cause of the blank Hosting Home (owner's screenshot: 2 Pending, 0 Live)
1. **iOS bug.** `HostHomeSections` fetched `get_account_kpis` with scope "host" while `reportsScope` was still
   "personal". `fetchAccountKpis` discarded the result (scope guard) and never reset `reportsLoading`, so the Home
   `.task` guard (`!reportsLoading`) blocked every retry. The note 69 "load This month on Home" never worked on iOS.
   Fix: `AppState.loadHostHomeKpis(organizerID:)` commits the scope first (same as web `loadHostHomeKpis`), and
   `kpiResultDisposition` separates "superseded by a newer request" (leave loading) from "scope changed" (clear it).
2. **"Coming up" vanished when empty.** Only live future events were listed; pending ones never count.
3. **Wrong label.** "This month" was really the Reports range (default last 30 days); web said "Reports".

## What changed (web + iOS)
- Shared rule `src/lib/hostHomeEmpty.js` ⇄ `apps/ios/BanbeApp/Lib/HostHomeEmpty.swift`, fixture
  `tests/fixtures/host-home-empty.json`:
  - `comingUpEmptyVariant`: needsFix > pending > quiet; null when the list shows, or when a hero shows and nothing waits.
  - `kpiSectionState`: hidden / tiles / loading / error / empty. Stale tiles stay through a reload or failed refresh.
  - `kpiRangeHeading`: "Last 7/30/90 days" or "Your chosen dates", following the Reports range picker.
- New section-level component: web `src/components/ui/InlineEmpty.jsx`, iOS `InlineEmptyState` in
  `EmptyStateViews.swift`. Dashed outline, one bold line, one sentence, at most one 44pt `block` capsule action.
- Coming up variants: needsFix / pending → open the dashboard with Submitted expanded. Quiet → Share host page
  (`https://banbe.app/org/<id>`), because the plan card already offers Create.
- Numbers: skeleton while loading, Retry on error, an honest "No bookings in this period" when empty.
- Test IDs: `home-host-upcoming-empty-{needsFix|pending|quiet}`, `home-host-upcoming-empty-action`,
  `home-host-kpis-{loading|error|empty|retry}`, `home-host-reports` (iOS: dotted equivalents). Existing
  `home-host-kpis` / `home-host-kpi-<key>` / `home-host-upcoming` are kept.
- No token, migration or feature-flag change. Not behind a switch (it only adds content where there was none).

## Verified
- `npm run test:unit`: 674 pass.
- `HostHomeEmptyTests` (shared fixture + scope regression), `HomeModeTests`, `ReportsPresentationTests`: 30 pass on the
  iPhone 17 Pro simulator.
- `tests/host-home-empty.spec.js` (quiet + KPI error, mocked 2 pending, dark) plus `note69-web-parity` and
  `simple-shell-home`: 51 pass on chromium, firefox and webkit.

## NOT verified
- Not checked visually on iOS or web in either theme, and no iOS UI test for the host fixture yet.
- The iOS "This month" fix has not been seen loading against production on a real device.
- Run `xcodegen generate` after pulling (new Lib + test files).

## Phase 2: goer empty states (web + iOS)
- Search no results: See all events, Clear search, and the real category chips (`search-empty-all|clear|cat-<key>`,
  iOS `search.empty.*`). Ink2 instead of opacity for the hint.
- Inbox: an empty inbox is a guided `EmptyState` / `MotivatingEmptyState` (`inbox-empty`, action `inbox-empty-find` →
  Home). A search with no hits (`inbox-empty-search`, new copy "No conversations match.") and an empty archive
  (`inbox-empty-archived`) stay plain lines. Before, a search with no hits said "No conversations yet".
- For You + other filters leaving nothing: own state `home-empty-foryou` (See all turns For You off and clears
  filters; Edit my picks opens Event preferences). The generic `home-empty` is unchanged otherwise.
- iOS Account Tickets tile: "Nothing upcoming" at 0 (was "0 upcoming"), matching web.

## Phase 3: polaroid cards behind `polaroid_cards` (migration 208, seeded OFF, applied 2026-10-31)
- Migration `20261231000208_208_polaroid_cards_switch.sql` + rollback. Registered in web `featureFlags.js`
  (FLAG_KEYS + OFF_UNLESS_SET), `featureFlagCategories.js` (App layout), `AdminFeatures.jsx`; iOS `FeatureFlags.swift`,
  `FeatureFlagCategories.swift`, `AdminFeaturesView.swift`, `AppState.polaroidCardsEnabled`.
- Tokens: `mat` (light #FBF8F1 = surface1, dark #24211C = surface2), `matShadow` (light only), `matSlot` (the empty
  photo slot: light #EEE8DA, dark #0F0E0B). matSlot exists because the old placeholder fill equals the dark mat and
  the inset vanished in dark (seen in the simulator screenshot, then fixed).
- `DiscoveryCard` (web prop `polaroid`, iOS `app.polaroidCardsEnabled`): 8pt inset, photo radius 8, hairline,
  caption inside the frame. No rotation, tape or stickers. Wins over Simple Shell `filled`. List rows unchanged.
- **Contrast finding:** light clay text on `block` (#EEE8DA) is 4.33:1, below AA. A clay ≥ 4.5 guard now covers
  paper / surface1 / mat only (`clayOn`); clay must not be used as text on block fills.

## Verified (phases 2–3)
- `npm run test:unit`: 675 pass (new: clay guard, mat/matSlot parity, slot ≠ mat).
- `tests/goer-empty-states.spec.js` (Search, Inbox, polaroid off/on light/dark): pass on chromium, firefox, webkit.
- iOS: DesignTokens, HostHomeEmpty, FeatureFlags, HomeDiscovery unit tests pass; new UI tests
  `testPolaroidCardsLight/Dark/LargestText` and `testHostHomeNeverEndsBlank` pass, screenshots reviewed.
- **Not caused by this work, found while testing:** (1) at accessibility XXXL text the iOS Home header and category row
  overflow the screen edges; (2) `DiscoveryFixtureUITests.testHomeDiscovery*` fail on "category tiles include Pop-up"
  (Pop-up has no events, so it sits under Show all); (3) 8 web specs (`home-foryou-pinned`, `home-quick-controls`,
  `home-scroll-restore`) and 4 in `account-groups-and-search` / `inbox-unread` fail identically on unchanged HEAD.
- Not checked: iOS Search / Inbox / For You empty states visually; web polaroid visually.

## Phase 4: accessibility hardening (web + iOS)
- **Event Detail controls over the cover photo failed contrast.** White glyph/label on the theme clay at 0.72 was
  2.31:1 (light) and 1.65:1 (dark, because dark clay is the light #D8926C) on a bright photo. Now a fixed deep clay,
  the same in both themes: web `--bb-photo-control-rgb` (126,69,41) at 0.9 with the sheen capped at 0.12, iOS
  `BanbeTheme.photoControl` / `photoControlAlpha`. Worst case over white / black / grey / warm photos >= 4.55:1.
  Fixture `photoControl` in `design-tokens.json`, checked by both token tests.
- **Web Reduce Transparency.** Every glass recipe in `theme.js` (field, card, bar, dock, ink button, photo pill) and
  the Event Detail controls read fill and blur through `var(--bb-rt-*, <today's glass>)`. `index.css` sets those
  variables only under `@media (prefers-reduced-transparency: reduce)` on `[data-bb-theme]` (so they resolve in the
  right theme): blur none, opaque surface-2 / paper / ink-deep / deep clay. Inline `backdropFilter` written outside the
  recipes (other screens) is NOT covered yet.
- **iOS Reduce Transparency** on the Event Detail controls: no material, fully opaque fill. The dock already follows
  the system setting through glassEffect/Material.
- **Largest text (iOS).** `HomeModeSwitch` had `.fixedSize()`, so at accessibility sizes it grew past the screen and
  pushed the whole Home column off both edges. At accessibility sizes it now takes the given width (two equal segments,
  label scales down to fit); default sizes unchanged. Hosting shortcut labels truncated to "K…"; at accessibility
  sizes the tile is 132pt and the full title wraps.
- Tests: `tests/a11y-transparency-contrast.spec.js` (dock opaque under emulated reduce in both themes, Chromium only
  via CDP; deep-clay controls in all browsers), `DesignTokensTests.testPhotoControlKeepsContrastOverAnyPhoto`,
  `DiscoveryFixtureUITests.testHostHomeVietnameseLargestText` (no sideways overflow, screenshot reviewed). Unit 676 pass;
  `SimpleShellDockUITests` still pass.
- Still open: the plan card's title and "Tạo sự kiện" button use fixed font sizes (do not grow with Dynamic Type);
  web has no automated largest-text pass.
