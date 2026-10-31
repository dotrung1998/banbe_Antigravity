# 69 — Account tabs by mode, Rewards visibility, dark splash, Hosting Home, Create long fields / two categories / sub-steps

Date: 2026-10-31. Platform: **iOS done; web parity NOT done** (except the splash tint, which is shared).
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

## Not done
- Web parity of 1, 2 (admin `requires` + Home capsule), 4 and 5 (`src/lib/eventTypes.js` combined, CreateEvent.jsx
  long fields / style / sub-steps, Account.jsx tabs). Shared fixtures for the combined profile not added yet.
- No real-device check of any of this.
