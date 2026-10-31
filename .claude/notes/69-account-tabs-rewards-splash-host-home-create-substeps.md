# 69 — Account tabs by mode, Rewards visibility, dark splash, Hosting Home, Create long fields / two categories / sub-steps

Date: 2026-10-31. Platform: **iOS and web** (web parity added the same day, see "Web" below).
Plan: `~/.claude/plans/please-make-plan-to-quizzical-pike.md`. Commits: babef0d, 8744a62, 20cc64b, 99dcd85, + the Phase 5 commit.

## 1. Account (Views/AccountView.swift, Lib/AccountTabs.swift)
- Tabs come back but follow Hosting mode (`AccountTabs.tabs`): off + not admin → no tabs; off + admin → Personal · Admin;
  on → Host · Personal (+ Admin). `app.accountTab` defaults to "host" and resolves to the first tab that exists.
  Turning Hosting on (applyOrganizerMode) selects Host. Tab bar = `GlassSegmentedControl`, a fixed sibling under the header.
- "More" is gone: labelled groups via `rowGroup` (Activity, Share & invite, App on Personal; Hosting tools on Host;
  Administration on Admin = the old `admin` AccountGroup rows inline). The group id goes on the HEADING only — on the
  container it replaced every row's accessibility identifier (that broke UI tests).
- Profile card: name up to 2 lines, Rename moved under it, whole card opens the public profile (`onTapGesture` on the
  card, Rename is a real Button and wins).
- Back position: root cause was that `.scrollPosition(id:)` only sees direct children with an id (rows inside one
  More card were invisible) and restores CENTRED. Now exact offsets per tab (`accountScrollOffsetByTab`, same
  mechanism as Home's `homeScrollOffsetY`). UI test `testAccountBackKeepsScrollPosition` (±12pt).
- Host/Admin tabs get `BottomTabBar.contentClearance + 16` bottom padding (they don't end with Sign out).

## 2. Rewards "can't be found"
Root cause in the owner's screenshot: "Rewards & badges" OFF, "Rewards v2" ON. v2 requires Rewards
(`rewardsV2Enabled = rewardsEnabled && v2`) but its row said "Visible to everyone". Admin switches now have `requires:`;
a switch that is on while its parent is off says "No effect yet" (honey) with a "Turn on …" button, and turning it on
asks "Also turn on …?". Simple Shell Home › Going out shows the streak/coins capsule next to the search bar (it only
existed in the old Home header).

## 3. Splash (public/logomotion/logomotion2309.html, LogomotionView, Splash.jsx)
`?tint=#rrggbb` → an SVG `feColorMatrix` on the canvas mapping darkness to the tint (black → tint, white → black). A
`source-in` fill was tried first: it turned the sprites' faint light edges into a visible gold frame. The square mark
next to the wordmark IS in the original artwork. iOS sends `palette.logo` only when it is a light colour (dark theme);
web sends the amber `#f6c453` when `resolvedTheme === 'dark'`. Headless WebKit can't load the sprites over file://
(serve `public/` over HTTP to test).

## 4. Home › Hosting (Views/SimpleShellHomeViews.swift `HostHomeSections`)
KPIs ("This month") load on Home via `fetchAccountKpis(scope: "host")` when no host report is in hand. Icon shortcut row
(guests, refunds, story, surveys, profile, reports; Create only when a hero event shows) with `.rootSwipeExclusion` so a
drag scrolls the row instead of switching screens. "Coming up" list. Plan card is one line ("Copy "<last event>" ·
about 5 min"). Pending / Needs fixing tiles open the dashboard with Submitted expanded (`dashboardOpenSubmitted`).

## 5. Create event
- **Migration 207** (`…207_second_category_intro_style.sql`, rollback in `supabase/rollbacks/`): `details.cat2`,
  `intro_font` (sans|serif|rounded|mono), `intro_color` (ink|ink2|clay|honey|alert); `set_event_details` accepts both
  types' fields (`SAME_CATEGORY` if cat2 = cat_key). Stored inside `events.details` as plain strings so every deployed
  client keeps loading events. **NOT APPLIED anywhere but the throwaway harness** (`CONTAINER=banbe-pg3
  supabase/_localtest/retention_suites_run.sh`: all 200 migrations + details suite E6 pass; rollback checked).
  Before 207 is applied, iOS falls back to saving the first type's facts only (INVALID_DETAILS / FIELD_NOT_FOR_TYPE).
  The intro style rides on the details save, so it is only saved while `event_type_profiles` is on.
- **Two categories** (Lib/EventTypes.swift): `combined`, `owner(of:keys:)` (draft value lives under the type that owns
  the field; shared alcohol/min_age under the first), `mergedDraft`, `publishDetails`, `eventProfile(catKey:details:)`,
  `secondCategory`. Event Detail, search and Home (`cat2Key` now filled from details) read the second category.
- **Long fields**: `BanbeField(lines:onExpand:)`, `LongText.minBoxHeight` = 2× the one-line box; `LongTextSheet`
  (Done, Clear all in the TOP bar — a bottom toolbar hides under the keyboard — confirmed by a dialog, count in a
  bottom inset above the keyboard). Intro style: `IntroStylePicker`, live in the field, applied in Event Detail's
  About sheet. Intro style kept in the draft map under `createDetails["_style"]`.
- **Sub-steps** (Lib/CreateSubSteps.swift, `SubStepBar`): Basics = Name · Story · Greeting · Categories · Details
  (Included + all type facts); Tickets = Price · Seats · Privacy · Who can book. Back/Next walk parts first; going back
  into a step opens its last part; "take me to this field" opens the part first. The outcome estimate shows under
  both Price and Seats.

## Tests
New: AccountTabsTests, EventTypesCombinedTests, CreateSubStepsTests, Shell `testAccountBackKeepsScrollPosition`,
`testHostHomeQuickActionsAndSubmittedTiles`, EventTypes `testLongFieldsExpandClearAndTwoCategories`. Updated create /
account UI tests to open the right part or tab.
Known failing and NOT caused by this work: `GiftTicketPDFTests.testPDFLinksPointAtRealDestinations` (wallet-pass /
calendar links) and `DiscoveryFixtureUITests.testHomeDiscovery{Light,Dark}` ("category tiles include Pop-up", which
contradicts EventTypesUITests' "a category with no events is not in the row").

## Web (parity, same behaviour)
- Account.jsx: `src/lib/accountTabs.js` (+ unit test), tablist in the sticky header, `RowGroup` labelled groups, whole
  card opens the profile (Rename / story ring stop the click), name clamps to 2 lines, Host/Admin end with 40px room.
  `accountTab` defaults to 'host' and is set when Hosting turns on. Web already restored Account's exact scroll per
  screen (App.jsx scrollPositions), so no change was needed for Back.
- AdminFeatures.jsx: `requires`, "No effect yet", "Also turn on …?" dialog. Real bug fixed on the way:
  `setFeatureFlag` built the new flags from its render's copy, so two flips in a row ("Turn on both") could undo the
  first locally; it now updates from the latest state.
- Home.jsx: the capsule is `renderRewardCapsule()`, shown beside the Simple Shell search bar.
- HostHome.jsx: `loadHostHomeKpis` (BanBeContext), icon shortcuts with `data-hscroll` (the web root swipe skips it),
  Coming up, one-line plan card, per-status tile buttons; Dashboard reads `dashboardOpenSubmitted` once.
- Create: `eventTypes.js` combinedProfile / detailOwner / mergedDraft / publishDetails / secondCategory /
  eventProfile / introStyle (+ unit tests mirroring Swift), `src/lib/createSubSteps.js` (+ tests), `src/lib/introStyle.js`;
  CreateEvent.jsx LongField / ExpandButton / LongTextSheet / IntroStylePicker / SubStepBar; save with the same pre-207
  fallback; edit-load splits cat2 / style back; Event Detail intro style + combined facts; search and Home cards read cat2.
- `tests/note69-web-parity.spec.js` (10 tests, Chromium + WebKit) renders signed-in layouts through the dev-only
  `window.__banbeDevSet` on top of guest browsing, because `setupToHome` (shared test account) is stuck on the
  language screen. RPCs it needs are answered with `page.route`.

## Not done
- No real-device check of any of this. Migration 207 not applied.
