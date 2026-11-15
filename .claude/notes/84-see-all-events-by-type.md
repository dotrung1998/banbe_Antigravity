# 84 · See-all screen: Events | By type switch (web + iOS)

Status (2026-11-15): IMPLEMENTED (web + iOS). Web committed and pushed to main (`e21cc32`). iOS edited in the same commit
but NOT built or run (no Xcode on the machine that made the change). No migration. Switch: the existing `home_v23` (the
Browse screen only exists under it, note 81), so nothing new to seed.

## Problem
See all (`/see-all/<tab>`) is one screen with the tab's type chips, so Browse by type was reachable only from Home's own
"Browse by type" section. There was no way to move between "the events in this scope" and "the types in this scope".

## Web (`src/screens/Browse.jsx`, `src/screens/Home.jsx`, `src/state/BanBeContext.jsx`)
- A two-option switch, **Events | By type** (VI: **Sự kiện | Theo loại**), sits directly under the sticky header row and
  shares the type chips' look through one `chipLook(on)` helper (selected = ink fill, unselected = hairline).
  Test ids: `browse-view-switch`, `browse-view-events`, `browse-view-types`. `aria-label` is "Cách xem" / "View", so the
  two tablists on the page stay distinguishable. Copy follows note 57 (no dash or semicolon between ideas).
- **By type** replaces the chips + count row + Pager with a 3-column grid of the same tiles Home uses
  (`CategoryGlyph` at 28, type name, "N events"). Tiles are `chips` (every type with `typeCounts(items) > 0`, most first),
  so the grid is the very same set the list is drawn from: no new fetching and no second filter path (note 50/81).
  Test ids: `browse-type-grid`, `browse-grid-<key>`, `browse-grid-count-<key>`. An empty scope shows
  `browse-type-grid-empty` ("Chưa có gì ở đây." / "Nothing here yet.").
- A tile runs `onType(key)` **and** `onView('events')`, the same step the type chips take, so it lands on the scoped
  list for that type (e.g. `/browse/fashion`). **Events** returns to the same scoped list with its search and filters
  intact.
- State: `browseView: 'events'` next to `browseType` / `browseScope` / `browseQuery` / `browseFilters`. `openBrowse` sets
  `browseView: same ? prev.browseView : 'events'`, so a fresh See all / Browse open lands on the list and browser
  back/forward into the same list keeps whichever view was open.
- **Not in the URL on purpose.** `/browse[/<type>]` and `/see-all/<tab>[/<type>]` keep their list meaning, so
  `screenToPath` / `pathToRoute` are untouched (`tests/unit/routesBrowse.test.mjs` still holds).
- The header's "N events · area" line counts the scope total in By type (the tiles carry per-type counts) and the
  filtered list length in Events. The screen root exposes `data-view` for debugging and checks.
- Known wrinkle, deliberate: an active search query is kept when switching to By type, but grid counts follow the type
  chips' existing rule (scope-wide, ignoring search and filters), so a searched user sees scope counts in the grid while
  the nav title still shows the query. Changing that would have meant a second counting rule for the same chips.

## iOS (`apps/ios/BanbeApp/Views/BrowseView.swift`, `State/AppState.swift`)
- `@Published var browseShowTypes = false` beside `browseType` / `browseScope` / `browseQuery` / `browseFilters`, reset
  to the list in `openBrowse`. No new models: the grid reads `EventTypes.categoryDefs()`, `BrowseRules.typeCounts` and
  `CategoryGlyph.symbol`, the same inputs the chips use.
- `viewSwitch` is fixed under `nav` (outside the ScrollView, like the web sticky row), `viewChip` carries the chip
  styling, and `typeGrid` draws the 3-column `LazyVGrid` of tiles (`browse.typeGrid`, `browse.grid.<key>`); an empty
  scope shows `browse.typeGrid.empty`. Identifiers: `browse.viewSwitch`, `browse.view.events`, `browse.view.types`.
- The header count uses `headCount` (scope size in the grid, list length otherwise). A tile sets `browseType` and drops
  back to the list, matching the chips.
- No iOS file was added, so `xcodegen generate` was not needed for this change.

## Checks
- `npm run test:unit` 1013/1013. `vite build` green.
- Public Playwright, Browse/Home specs (`browse-v23`, `home-hero`, `home-live-line`, `home-nextup-v23`,
  `home-v23-pager`): 14 passed, 8 failed. **All 8 fail identically on the untouched baseline** (stashed the three web
  files and re-ran), so they are pre-existing in this environment, not caused by this change: search `fill()` not
  reaching React state, a headless-shell renderer crash, and Shortlist/empty-tab assertions.
- The new switch itself, checked with a throwaway mocked-Supabase script against a local dev server: defaults to Events,
  By type hides the chips and the pager and shows the tiles with counts, a tile returns to the filtered list
  (`/browse/fashion`), and `/see-all/weekend` → By type → Events keeps `scope=weekend` in both views. For You showed 17
  rows and 4 tiles summing 19, which is expected because an event can carry a second category (note 69). Tonight and
  Weekend were empty in that fixture, and grid and list agreed (0 events, empty grid, empty list).

## Not done
- iOS was not compiled, not run, and not looked at. The Swift changes need an Xcode build and an on-device or simulator
  pass before they can be called verified.
- No screenshots, so neither platform's switch or grid has had a visual review.
- The search-query-versus-scope-counts wrinkle above is left as it is.
