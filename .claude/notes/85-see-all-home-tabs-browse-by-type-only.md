# 85 · See all carries Home's tabs; Browse by type is types only

Status (2026-11-15): IMPLEMENTED (web + iOS). iOS built for the simulator (Debug, scheme `BanbeApp`, green). Web NOT
built and no spec run (no shell on this machine). No migration. Same switch as note 81 (`home_v23`). SUPERSEDES the
Events | By type switch of note 84.

## Problem

Note 84 put an Events | By type switch on the See-all screen. Two things were wrong with it:

1. **It duplicated Browse by type.** Home already owns "Browse by type" as its own entry (grid of types + Find a type +
   "See all N"). The switch put the same idea a second time inside See all, one pill row above the type chips, in the
   type chips' own look: three chip rows saying overlapping things.
2. **It answered a question nobody asked.** See all is opened from a Home tab (For You / Tonight / Weekend), and once
   inside there was no way to move to another tab. The reader had to go back to Home and tap again, which is the actual
   friction the screen had.

## The screens now (same route family, told apart by the URL)

- **`/see-all/<tab>`** — the tab's list. Home's three tabs sit right under the nav, in Home's own words, order and
  rhythm (17px text over a 2px rule, the open one in ink, the others at 55%), so the tab changes in place at any scroll
  position. Under them the host deck, the type chips, the count + Filters row and the four-a-page list, as note 81.
- **`/browse`** — Browse by type, TYPES ONLY: every type of the whole catalogue as one 3-column grid of counts and
  nothing else (no chips row, no filters button, no list). A 14px line under the title says what to do, then "N events ·
  area". A tile opens `/browse/<type>`; that list's "All" chip, and the end card's "All types", return to the grid.
- **`/browse/<type>`** and **`/see-all/<tab>/<type>`** — the type's list, unchanged from note 81.
- **Search** on the grid is the one thing that opens it into a list: the matches across every type. Clearing it (× or
  "Clear search") returns to the grid. This also fixes the "Find a type" tile on Home, which always opened a list of
  everything instead of the types it promised.
- **Back** steps up, not out: from a type's list under `/browse` (the grid is its parent) it returns to the grid; from
  the grid, and from any tab screen, it returns Home. The button is labelled for where it goes ("All types" / "Back to
  Home"). On the web the browser's own Back still follows history.
- The title lives in the content, once: the tab row on a tab screen, the 30px title on the grid. The nav row is
  therefore bare (back, search, map) and only fills in what the content does not say: the picked type ("Music", "Tonight
  · Fashion") and a search (`"jazz" · Music`). No kicker, no second title, no repeated count line.

## Web (`src/screens/Browse.jsx`, `src/screens/Home.jsx`, `src/state/BanBeContext.jsx`)

- `Browse` lost `view` / `onView` and the `VIEWS` switch, and gained `onScope(tab)`. `browseView` is gone from the
  context (`openBrowse` no longer writes it); the URL alone says which screen is open.
- Mode is derived, not stored: `index = scope === 'all' && effType === 'all' && !query.trim()`. `data-mode="index|list"`
  on the screen root, `data-scope` / `data-type` as before.
- Scope tabs: `browse-scope-tabs` (tablist, `aria-label` "Trang chủ" / "Home"), one button per tab
  `browse-scope-<key>`; they live inside the sticky header, `data-hscroll` so the root tab swipe ignores them.
- `Home.jsx` `browseScopeTo(tab)` switches tab in one state write: `browseScope = tab`, search and Browse's own filters
  reset to a fresh open (the same reset `openBrowse` takes), and the type survives only where the tab still has events of
  it (`typeCounts(tabItems(tab))`, imported as `browseTypeCounts` — Home already has a local `typeCounts`).
- `pickType('all')` on `/browse` returns to the grid and starts it clean (search + filters cleared), so a tile never
  inherits filters the grid never showed. Same for the end card's `type:all`, and for the header's Back (`goBack`), which
  takes that same step before falling back to `onBack` (Home).
- Type tiles and the grid's `browse-type-grid`, `browse-grid-<key>`, `browse-grid-count-<key>`, `browse-type-grid-empty`
  keep their note-84 ids; `browse-title` now exists on the grid only.
- The tab screens drop the old kicker + 30px title + header count line: the tab row is the title, the count row below
  carries the number, so nothing is said twice.

## iOS (`apps/ios/BanbeApp/Views/BrowseView.swift`, `State/AppState.swift`, `Views/AppState` state block)

- `@Published var browseShowTypes` removed; `browseView`-style state is gone here too (the scope says it).
- `AppState.browseBaseItems(scope:now:)` is the one place the scope's items are built (For You ranked else soonest,
  Tonight / Weekend by date, `all` = the catalogue), `browseEntries(now:)` reads it, and
  `browseTypeCounts(scope:now:)` counts types in any scope (chips, tiles, the scope switch's keep-or-drop rule).
- `browseSwitchScope(_:)` (tab switch: scope, clean search + filters, type kept only when the new tab has it) and
  `browsePickType(_:)` ("All" on `/browse` → grid, clean).
- `scopeTabs` sits between `nav` and the ScrollView (never scrolls away), `nav(_:hairline:)` moves the header's rule to
  the tabs when they show, `typeIndexHead(_:)` is the grid's title block, `backFromBrowse()` steps up to the grid from a
  type's list (label `backLabel` says which way it goes), and `navTitle` is empty unless a type is picked or a search runs.
- Identifiers: `browse.scopeTabs`, `browse.scope.<tab>`, `browse.scopeCount` (grid only), `browse.title` (grid only).
  `browse.viewSwitch` / `browse.view.events` / `browse.view.types` are gone.
- No iOS file was added, so `xcodegen generate` was not needed.

## Checks

- **iOS:** `xcode_build` (Debug, scheme `BanbeApp`, simulator) — green after the change. Not looked at on a device or
  simulator, so the tab row's weight, the rule and the grid's spacing have had no visual review.
- **Web:** NOT built and NOT tested here (no shell). The pure rules are untouched (`src/lib/browse.js`), so
  `tests/unit/browse.test.mjs` and `routesBrowse.test.mjs` still describe the same functions and URLs.
  `tests/public/browse-v23.spec.js` was updated for the new screen: the deep-link test asserts `data-mode="list"` and the
  nav title and that Back steps up to the grid before Home, and two new tests cover (a) `/browse` being types only with a
  tile opening its list and "All" returning to the grid, and (b) See all switching tab in place with the URL following.
  **These have not been run.**

## Open / not done

- Nothing has been run on the web: the three Playwright cases above plus a `vite build` are the first things to run.
- A visual pass on both platforms: the tab row at 17px next to the 14px chips, the grid with 14+ types, and the empty
  Tonight tab (the tab row should still read as the way out, since the empty card offers no tab list of its own).
- The web scroll margin of the count row (`scrollMarginTop: 108`) is a guess at the header's height now that the tabs
  are inside it; the end card's "another type" jump scrolls to that row.
