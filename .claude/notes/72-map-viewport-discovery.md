# 72 — Map redesign: layout A, viewport-driven discovery, shared filters (phases 1–3)

Status: IMPLEMENTED (web + iOS), tests green; phase 4 (price pins, clustering, same-coordinate stacks) NOT started.
No migration. Run `xcodegen generate` after pulling (new Swift files).

## What the Map is now
- **Layout A** (map first, card peek): opens at **mid** on both platforms; cards at mid, denser rows at tall.
  Content surfaces are opaque (iOS `.presentationBackground(paper)`, solid chips/search/card); glass only on map
  controls and the dock.
- **Results = committed area + one filter predicate.** Pins, list and the "N sự kiện trong vùng bản đồ" count are
  the same list. Pure core: `src/lib/mapDiscovery.js` ⇄ `Lib/MapDiscovery.swift`, fixture
  `tests/fixtures/map-discovery.json`.
  - Area = the map's **reference rect**: full map minus the top controls minus the **peek** sheet (+ attribution
    strip). Same at every detent, so moving the sheet never changes results.
  - Camera moves carry a reason. `user/initial/destination/recenter/nearest/cluster` commit once after settle
    (250 ms coalescing); `reveal` (selection / sheet follow) and `restore` never do. A layout reason stays in force
    ~1.5 s because a reveal can end in two `moveend`s (flyTo interrupted by the padding ease) — the root cause of a
    "selecting a pin re-searched" bug found while testing.
  - Selection lives only while its event is a result (reverses the old "selection survives filters" rule, by the
    owner's spec); reveals keep the current zoom.
- **Data:** the whole public live set (cap 500, `count: exact`; production had 5 on 2026-10-31), filtered locally —
  panning makes no request. Above the cap the Map says "Showing N of M". Refresh every 60 s (was 5 s) + on
  foreground/visibility; failures keep the last rows with Retry. "Tìm ở đây" is gone.
- **First open:** picked area's events → events ≤ 50 km of a located viewer → densest city (25 km), fitted above the
  mid sheet (`fitCamera`). Never GPS alone, never all inventory. Restore keeps camera, area, filters, detent,
  selection and rows (no loading frame).
- **Rows/card:** venue date · time (`whenLabel` / `discoveryWhenLabel`, same source as Event Detail), price "/ vé",
  seat pill only from real fill (`get_public_event_fill`, migration 186 — live); distance only ≤ 50 km. Card has
  **Directions** (same link as Event Detail: `mapsUrl` / `CatalogEvent.mapsURL(lat:lng:)`).
- **Filters (phase 3):** the Map holds Home's filter object and runs `applyDiscoveryFilters` / `HomeDiscovery.apply`.
  - Venue-time windows: `dateWindowInZone` (both platforms, fixture `tests/fixtures/date-windows-venue.json`).
    Tonight = 17:00 → 04:00 venue time (00:00–04:00 = night in progress); Weekend = Fri 17:00 → Mon 00:00; windows
    never start before now (no end times, so no "happening now"). Home items now carry `tz` too (VN unchanged).
  - Chips: categories (Home's defs + line icons + counts in the area, fixed order, A–Z sheet) · Vùng bản đồ ▾ ·
    Tối nay · Cuối tuần · Còn chỗ · Bộ lọc. The sheet is Home's `HomeFilterSheet` in **map mode** (draft; Close
    discards; Apply atomic; "Show N" over the area's events; Location/Sort/Category hidden; price per ticket).
  - Area picker = a **destination** (fits that area's mapped events, keeps filters); panning shows "Map area" and
    never changes Home's area. For You is no longer narrowed by the picked area on Map.
  - Home → Map: `goMapExplore({ source, filters, query, forYou })` (web) / `goMapExploreFromHome()` (iOS); the
    dock passes nothing. "+N matching events outside this area" explains a lower Map count.

## Tests
- Web unit: `tests/unit/mapDiscovery.test.mjs`, `tests/unit/dateWindowsVenue.test.mjs` (suite 689/689).
- Web e2e: `tests/map-viewport.spec.js` (12 tests, guest mode, all 3 browsers). Test hooks:
  `window.__mapExploreCommits`, `window.__mapExploreArea`.
- iOS: `MapDiscoveryTests`, `DateWindowsVenueTests`, `MapViewportUITests` (DEBUG fixture `-uiFixture shell.map`).

## Known gaps
- `tests/map-explore.spec.js` and `MapExploreSelectionUITests` are stale (Search here, filter-moves-camera, selection
  kept through filters) and blocked by the shared test account's date-of-birth gate — need rewriting.
- iOS: Apple Maps legal label still partly under the sheet. On-device smoothness unchecked.
- Demo seed rows have `starts_at` that disagrees with `event_time` (Map and Event Detail show e.g. 02:00); data issue.
- An area with no mapped events can't be flown to (no area geometry exists).
