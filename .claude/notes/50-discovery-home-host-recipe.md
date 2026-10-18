# 50 — Discovery-first Home + "Recipe for success" event creation

Status: IMPLEMENTED (web, committed); iOS UNFINISHED, committed as WIP, never built (see "iOS" below). Migration 186 NOT applied anywhere
remote (tested on a throwaway Postgres 16). Source: UX Peak, "The Same App Designed By An $80K vs $250K UX/UI
Designer" (transcript supplied by the owner, 2026-10-18).

## Lessons taken from the video (and where they landed)
- **First screen must be worth scrolling for** (not "fit the most above the fold"). Home's first event card now
  starts at y≈601 of 844 for a guest (measured with Playwright, 390×844).
- **Hierarchy you can scan:** the card name steps up (18pt), the price gets the weight, and the meta line drops
  back. **Details go under the photo**, never on it (staff variant): host photos vary too much for overlaid
  text. Only small badges sit on the photo (date, Save, Almost full / Sold out / Cancelled / You're going).
- **One shape language:** `RADIUS` in `src/theme.js` (card 14, tile 14, thumb 12, pill 999). Category tiles are
  rounded squares, not circles; story bubbles keep their own convention.
- **Custom icon set** for categories (line glyphs, quiet tint) so the row doesn't compete with the photos.
- **Visible filters + Filter/Sort buttons + count + cards/list toggle** ("when no default suits everyone, give
  people control").
- **Filter sheet = level D:**
  - a sheet over the results, with everything in one scroll;
  - pills instead of steppers, and every pill shows its count before it's tapped, computed with the other
    filters applied;
  - a histogram behind the price, plus a context line ("median X · N of M events");
  - a CTA with the exact count; when nothing matches, it names the single filter to relax;
  - "Price for 2" is the budget-in-the-user's-terms idea (display only).
- **Requirements are soft:** when there are fewer than 3 results, Home shows one-tap "+N events with …" hints.
- **Event creation reuses the same ideas:**
  - Quick picks show their outcome before they're chosen ("This Sat · fills 85%", "200k₫ · below typical").
  - Price, seats and the outcome estimate share one step.
  - Price is turned into an outcome: "~18 guests · ~9M₫ if it fills like similar events (~60%), before any fees".
  - At most one insight line per field, with the detail behind "Why?" (the video's "busier" caveat).

## Decisions
1. **"Your events" strip removed.**
   - Schedule and Account → Saved/Going already own a user's events.
   - The one valuable part, the note-37 reminder (24h before → 12h after a confirmed ticket), is now a slim
     "Next up" banner (`NextUpBanner`, testid `home-event-reminder`). `src/lib/eventReminder.js` is unchanged.
2. **Status chips removed from Home** (Upcoming/Saved/Attending/Not confirmed/Sold out).
   - They filter *your* events, not discovery.
   - Their state fields (`filterSaved`…) still exist in context, but Home no longer reads them.
   - For You stays pinned (notes 34/36).
3. **Location pill + language + light/dark in one plain-text row** (follow-up 2026-10-18; the language/theme
   capsules had been removed from Home and the owner asked for them back). `Near Everywhere ▾`, then `VN`/`EN` and
   `Dark`/`Light`, in the same icon + text style, right beside the pill (web testids `home-area-toggle`,
   `home-lang-toggle`, `home-theme-toggle`; iOS `header.area`, `header.lang`, `header.theme`). Each shows what a tap
   switches TO. The long area name truncates before the toggles do.
4. **Search is its own screen** (`/search`, `src/screens/Search.jsx`), not "open Map".
   - It uses the same matcher as Map (`src/lib/search.js`).
   - Results are grouped Events · Hosts · Areas, each with a count.
   - Recent searches are stored in this browser only (max 8).
   - Trending comes from Banbe Pulse daily.
   - "See on map" carries the query.
   - Guests can use it (`GUEST_BROWSE_SCREENS` += 'search').
5. **No host questionnaire.**
   - Hosts already enter every benchmarking attribute (category, city, price, seats, day/time).
   - Instead there is one optional per-event pill question, "What matters most for this event?":
     fill_seats / regular_crowd / try_idea / small_premium.
   - It weights the recipe: premium relaxes the price band, and fill_seats is stricter on seats.
   - It is stored in the host-only `event_host_meta` and never shown to guests.

## Follow-up fixes (2026-10-18, from on-device testing)
1. **iOS For You chip** was ~8pt shorter than the other chips: it now uses the same 36pt height and 13pt type.
2. **Sort has its own pop-up** with ONLY the sort options (✓ on the current one): a native `Menu` on iOS, `SortMenu.jsx`
   (anchored like AreaMenu) on web. The sort button turns "on" while a non-default sort is chosen, and the Filters
   badge now counts filters only. "Nearest" without location says so and asks for it. The sheet still has a Sort
   section; both write the same `homeSort`.
3. **Category is one value.** The main row and the filter sheet both edit `homeFilters.cats`, so a category picked on
   Home is already ticked in the sheet. The feed is no longer pre-filtered by category (web `s.filter`, iOS
   `app.filter` are gone), which is what made the sheet show every other category as 0 and disabled. `pickFilter(key)`
   now sets `cats` (`all` -> `[]`). The weekend rail follows the same cats.
4. **Location picker over the filter sheet.** It no longer closes the sheet: it slides up over it (iOS nested sheet via
   `LocationPickerSheet(doneMode: true)`, web `AreaSheet embedded`), a pick only moves the selection (the counts behind
   update), and **Done** (also backdrop / Esc on web) slides it back down. The draft survives. Outside the filter sheet
   the picker behaves as before (a pick closes it).

## Migration 186 (`20261224000186_186_discovery_fill_and_host_benchmarks.sql`, rollback in supabase/rollbacks)
- **`get_public_event_fill(text[])`** (anon + authenticated)
  - Real booked seats per LIVE PUBLIC event, counted with `booking_holds_seat()`, the same rule `hold_seats`
    enforces.
  - **Finding:** `events.seats_remaining` is written once at insert and never decremented, so every "N left"
    that read it was stale. Web `shapeRealEvent.soldOut` still reads it (not changed here; follow-up).
- **`get_host_benchmarks(cat, city)`** (authenticated)
  - Pool: public, not-cancelled live/ended events, from 180 days back to 60 days ahead.
  - Falls back category+city → category → all.
  - **k-anonymity:** every slice (the sample, each weekday×slot cell, the well-filled vs other groups, each
    keyword) needs ≥5 events from ≥3 organizers, else it comes back NULL.
  - Returns:
    - price p25/median/p75 + a 10-bucket histogram
    - median fill / capacity / booked
    - weekday×slot fill
    - well-filled (≥80%) vs others: photos, intro share, included share, lead days
    - top keywords used by ≥2 organizers
  - VOLATILE because it fills a temp table.
- **`get_audience_demand(cat)`** (authenticated): the count of `profile_event_preferences` interested in the
  category, floored to 10, NULL below 10. No city (preferences have none), so it is platform-wide.
- **`event_host_meta`**: RLS on, no grants; read and written only through `set_event_host_goal` /
  `get_event_host_goal`, owner-scoped.
- **Verified on Postgres 16** with a minimal schema and seed:
  - fill ignores expired holds and cancelled bookings, and excludes invite/cancelled events
  - the fallback cascade picks the right level
  - demand rounding works
  - anon is denied benchmarks/demand/table; authenticated is denied the table
  - a non-owner can't set or read a goal
- **To apply:** `supabase db push`. Until then the web degrades silently: no fill badges, and the recipe shows
  tips only (the console logs one 404 for `get_public_event_fill`).

## Web files
- **New:**
  - `src/lib/homeDiscovery.js` + `tests/unit/homeDiscovery.test.mjs` (11 tests)
  - `src/lib/eventRecipe.js` + `tests/unit/eventRecipe.test.mjs` (12 tests)
  - `src/lib/useHostBenchmarks.js`
  - `src/components/home/HomeDiscoveryParts.jsx`
  - `src/screens/sheets/HomeFilterSheet.jsx` (portals into `.bb-screen`, because Home's root keeps a transform)
  - `src/screens/sheets/RecipeSheet.jsx`
  - `src/screens/Search.jsx`
- **Changed:**
  - `src/screens/Home.jsx` (discovery layer + new render order; the dead floating-search scroll code is removed)
  - `src/screens/CreateEvent.jsx`:
    - recipe meter, goal pills, keyword suggestions, demand line
    - slot-fill and lead hints, price market and positions, seats insight, outcome
    - the Review checklist; `PickTile` `sub`, `Insight`, `PriceMarket`
  - `src/state/BanBeContext.jsx`:
    - `homeFilters`/`homeSort`/`homeFilterSheetOpen`/`eventFill`/`searchQuery`/`createHostGoal`
    - `openSearch`, `setHomeFilters`
    - fill loaded after `loadDiscoveryEvents`; goal saved after submit
  - `src/data/events.js` (`catalogStartMs`: the demo catalogue's simulated TODAY is shifted to real today, so date
    chips, badges and Search agree with "in N days")
  - `src/lib/routes.js`, `src/App.jsx`, `src/lib/guestAccess.js` (+ its unit test), `src/theme.js` (`RADIUS`),
    `src/index.css` (`.bb-range` dual slider), `src/lib/smartDefaults.js` (unused `FIRST_EVENT_SEATS` removed)
- **Specs updated** (not run green — see below): `tests/account-groups-and-search.spec.js` (search bar → /search,
  back/forward, See on map), `tests/home-foryou-pinned.spec.js` (first visible quick chip).

## Verified / not verified
- `npm run test:unit`: 302 pass, 0 fail. `vite build` OK.
- **Guest Home / filter sheet / list mode / Search:** screenshots at 390×844 against the live dev server. No page
  errors; the only 404 is `get_public_event_fill` (186 not applied).
- **Create flow:** the shared test account is stopped at the server DOB gate (note 49), so it was checked in an
  esbuild harness that bundles the REAL `CreateEvent.jsx` with a stubbed context and Supabase, fed with the exact
  jsonb 186 returned on Postgres. Both the data and cold-start paths rendered with no errors. The cold start
  showed no numbers and the full-house estimate.
- **Playwright `tests/home-quick-controls.spec.js`** (guest, so no DOB gate): 4 tests x chromium/firefox/webkit = 12 pass.
- **NOT run:** the rest of the Playwright e2e suite (DOB gate); dark mode screenshots for web; real benchmarks (none until
  186 is applied and enough events exist; expect cold-start tips for a while — by design).

## Known limitations / follow-ups
- Demo catalogue items have no fill data, so Almost-full / going badges only appear on real events once 186 is live.
- `shapeRealEvent.soldOut` still derives from the stale `seats_remaining` (Event Detail, Map list); switch it to
  `eventFill` in a follow-up.
- Benchmarks use Vietnam time for weekday/slot (all launch markets); US events land in VN slots.
- `get_host_benchmarks` returns the same aggregates to any signed-in user (not only hosts). It's aggregate-only
  and k-gated, but restricting it to accounts with an organizer row is a possible hardening.

## iOS
STATE: builds, and `BanbeAppTests` HomeDiscovery/EventRecipe (23) + `DiscoveryFixtureUITests` (14, incl. sort menu, category
preselect, nested location picker, For You chip alignment) pass on an iPhone 17e simulator. Earlier text below describes
the stop-point and is kept for history; it was committed as WIP and has since been built and tested.

HISTORY: NOT DONE. A port was started and then stopped partway (2026-10-18). Its changes were committed as-is (WIP commit,
at the owner's request) for the owner to review or finish:
- New: Lib/HomeDiscovery.swift, Lib/EventRecipe.swift, State/AppState+Discovery.swift, Views/HomeDiscoveryViews.swift,
  Views/HomeFilterSheet.swift, Views/RecipeSheet.swift, Views/SearchView.swift, BanbeAppTests/HomeDiscoveryTests.swift,
  BanbeAppTests/EventRecipeTests.swift, BanbeAppUITests/DiscoveryFixtureUITests.swift.
- Modified: HomeView, AppState, AppState+Data, OnboardingViews, RootView, CatalogEvent, MapExploreView, BanbeTheme,
  FormControls, Search, SmartDefaults, Analytics, UITestFixtures, and two UI test files.
- Never built and no tests run. RootView is touched: the note-47 Home mount-count test must pass before it ships.
- The web files above are the spec. Mirror the unit tests 1:1 (same fixtures, Vietnam UTC+7 fixed offset).
