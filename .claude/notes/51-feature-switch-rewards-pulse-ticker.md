# 51 — Admin feature switch (Rewards & badges) + compact Banbe Pulse ticker

Status: IMPLEMENTED LOCALLY (web + iOS), NOT committed. Migration 187 NOT applied anywhere remote (tested on a

**Production check 2026-10-22 (`supabase migration list --linked`, note 58): 187, 188, 189 and 190 ARE applied on production. Statements below saying otherwise are outdated. Local-only (not on production): 182, 183, 184, 185.**
throwaway Postgres 16). Rewards stays hidden until 187 is applied AND an admin enables it (see "Seed" below).

## 1. Admin switch: hide Rewards & badges everywhere

Why: Rewards & badges (note 36, migration 165) needs more development; a platform admin must be able to hide it for
everyone (web + iOS, signed in and signed out) without a release, and turn it back on the same way.

- **Server (`20261225000187_187_feature_flags_rewards_switch.sql`, rollback in supabase/rollbacks):**
  - `app_feature_flags(key, enabled, updated_by, updated_at)`: RLS on, no client grants. `key` has a CHECK listing the
    known flags (today only `rewards`); adding one is a migration edit plus the three client lists below.
  - `get_feature_flags()` — anon + authenticated. Returns `{ "rewards": false }`.
  - `admin_set_feature_flag(key, enabled)` — authenticated, but only a platform admin passes `is_platform_admin()` +
    `account_gate_ok()` (decided server-side); unknown keys → `INVALID_VALUE`; every flip is written to
    `app_feature_flags_audit` (service_role only).
  - **Seed: `rewards = OFF`.** Applying 187 hides Rewards for everyone. Turn it on in Account > Admin > Review &
    moderation > **Feature switches** (web + iOS). Only the UI is hidden and nothing is deleted; while hidden the apps
    stop calling the reward endpoints, so client-driven streak days (saving an event) are not recorded, while coins and
    badges the server awards on its own (host-confirmed attendance) keep accruing.
  - Verified on Postgres 16: anon reads flags but cannot call the setter or touch either table; a non-admin gets
    `NOT_AUTHORIZED`; unknown key / NULL → `INVALID_VALUE`; admin on/off round-trips and writes 2 audit rows.
- **Client rule (`src/lib/featureFlags.js`, `Lib/FeatureFlags.swift`, mirrored unit tests):**
  a MISSING key means "on" (only an explicit `false` hides); non-booleans and unknown keys are ignored; the last answer
  is cached on the device (localStorage / UserDefaults) so a cold start offline keeps the last-known value. Before any
  answer (first run, or 187 not applied yet) everything shows, which is the behaviour from before flags existed.
- **Loading:** web `loadFeatureFlags` on start, on sign-in/out and when the tab becomes visible (≥ 20s apart); iOS
  `loadFeatureFlags` in `BanbeApp.swift` on start and every return to the foreground (throttled 20s). Best-effort: an
  error or a missing function leaves the last-known flags untouched.
- **Everything that hides when `rewardsEnabled` is false** (single derived value, web `rewardsEnabled` from the
  context, iOS `AppState.rewardsEnabled`):
  - Home streak/coins capsule;
  - Account > "Rewards & badges" row and its Account-search entry;
  - the reward keychain designs (the picker group, and its unlock lookups);
  - the Rewards screen itself (a deep link `/profile/rewards`, or the flag flipping while it is open, leaves through Back's
    own target and renders nothing);
  - no calls to `get_my_reward_summary` / `get_my_rewards` / `record_active_day` (web test asserts zero requests).
  Turning it off clears the loaded numbers; turning it on loads the summary.
- **Admin screen:** web `src/screens/AdminFeatures.jsx` (`/admin/features`), iOS `Views/AdminFeaturesView.swift`
  (`Screen.adminFeatures`). One row per flag with a shared glass switch (`src/components/ui/GlassSwitch.jsx`,
  `Views/GlassSwitch.swift`, extracted from the migration-181 master switch). The switch moves only after the server
  accepted the change; a refusal leaves it where it was and shows why (`NOT_AUTHORIZED`, `NOT_DEPLOYED` = apply 187,
  `NETWORK`).

## 2. Banbe Pulse: a ticker instead of a tile

Why: the Pulse tile sat in the story row, took ~100px, and left a tall empty band when there were no stories; the
teaser speech bubble over it needed a lot of fragile positioning code.

- **One slim line (38px)** under the search bar (web) / first item of the feed (iOS, so it scrolls away with the page):
  `✦ Pulse` chip (the old ring's gradient) + today's top events (daily `goc_pulse_ranked`, at most 5, ranked 1..N)
  scrolling like a news ticker + chevron. Tap = open the Pulse viewer, exactly like the old tile. No ranking yet: a static
  "See what's trending this week" line, still tappable (never an empty box).
- **Motion:** web CSS marquee over two identical copies (seamless); iOS `TimelineView` offset = elapsed × speed wrapped
  over one copy (no state animation to stack or jump). Speed is proportional to text length (`pulseTicker` lib, floor 14s),
  paused on hover/focus (web) and while the app is not active (iOS), and a single static ellipsised line under reduced
  motion on both. The looped copy is hidden from assistive tech; the button's label lists the events once.
- **Story row:** shown ONLY when there are stories (compact 52px rings), so no stories = no row and no band.
- **Removed:** the teaser speech bubble and its whole machinery. Web: `PulseTeaserBubble` and its tests in
  `tests/pulse-viewer.spec.js`. iOS: `PulseTeaserBubbleView.swift`, its RootView mount, the `pulseTeaser*` state in
  AppState, `PulseTeaserGeometryUITests.swift`, the ring glyph and its layout constants. The Pulse viewer is unchanged.
- Home now loads the daily ranking itself (it was the teaser that did before), for guests too (the RPC is public).
- Pure logic with mirrored unit tests: `src/lib/pulseTicker.js` / `Lib/PulseTicker.swift`.

## Mistake worth remembering (web)
While replacing the story row in `Home.jsx` I cut from its marker to the "Section 5 surveys" marker, but the surveys now
sit BELOW the feed, so the cut also deleted the categories, quick row, feed and weekend rail. The build still passed
(valid JSX). The guest Playwright specs caught it; restored from the last commit and the later edits re-applied. When
removing a block, bound it by its own closing tag, and run the Home specs after.

## iOS notes
- The Xcode project is generated (`apps/ios/project.yml`, `BanbeApp.xcodeproj` is gitignored): **run `xcodegen generate`
  in `apps/ios` after pulling** (files were added and deleted).
- UI-test fixtures are now hermetic: `AuthViewModel.init` does not restore a real session in fixture mode. A real login
  left in the simulator by an earlier run raised the account gate over the fixture mid-test.
- `loadPulse` returns early in fixture mode (like the other loaders): a live ranking from the network replaced the seeded
  one and made the ticker tests flaky.
- New fixture flags: `-uiFixturePulse YES`, `-uiFixtureRewards off`, `-uiFixtureForYou YES`; fixture `shell.adminFeatures`.
  In a fixture the admin switch flips locally (never the network).

## Verified
- Web: `npm run test:unit` 309 pass; `vite build` OK; Playwright `tests/rewards-switch.spec.js` (flag on / missing /
  off, no reward requests when off, admin flips the flag and Home follows, a server refusal), `tests/home-pulse-ticker.spec.js`,
  `tests/home-quick-controls.spec.js`: 45 pass on Chromium, Firefox and WebKit. The server is mocked at the network edge
  (the shared account is stopped by the DOB gate and is not an admin).
- iOS: `xcodegen generate` + build OK; unit tests 288 run, 1 fails (`GiftTicketPDFTests.testPDFLinksPointAtRealDestinations`:
  it flags `www.banbe.app` links as invented; pre-existing, from the domain switch in note 41, unrelated). Fixture UI tests in
  `DiscoveryFixtureUITests` (ticker position/size/label/tap, static invitation, rewards hidden, admin switch) pass.
- iOS full UI suite (108 tests, 2026-10-19): 47 fail, and they fail the same way WITHOUT these changes. The classes that
  fail were re-run on the untouched pre-session commit 20498bb (same simulator, same keychain) and the failing sets match,
  apart from one renamed test (below) and one flaky Schedule test. Causes, none of them new:
  - stale identifiers removed long ago (commit 64f2719): `header.account` (11), `header.mapExplore` (2), `tab.inbox` (2);
  - tests that sign in with the shared account, which the server's DOB gate stops (login screen, "did not navigate", tab-bar
    and ScreenshotCatalog tests);
  - `card.bepnho` matching several elements (also at baseline; the Home cards/rows now carry `card.<key>` on the photo only);
  - Schedule accessibility audits, one Dynamic Type warning, and a date-relative Discover label.
  `MapExploreSelectionUITests.testHomeSearchBarOpensSearchWithKeyboardFocused` is the discovery-port rename of
  `testHomeSearchFabOpensMapWithKeyboardFocused`; both need the real login, so it cannot pass here.
  The fixture suites (DiscoveryFixtureUITests, ShellFixtureUITests incl. the note-47 Home mount counts) are the reliable ones.
  Follow-up worth doing: delete or update the stale tests so the suite is green and can guard regressions.
- NOT verified: on a real device; the admin switch against the real server (migration 187 not applied).
