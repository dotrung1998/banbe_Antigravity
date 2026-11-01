# 73 — Map v5: dock on demand, category pins, selection in the sheet, sticky filters, pan → peek, cities

Status: IMPLEMENTED (web + iOS), not committed. No migration. Run `xcodegen generate` after pulling (new bundled
resource `src/data/cities.json`). Builds on note 72; everything there still holds unless changed below.
Plan: owner request 2026-11-01 (screenshots + Airbnb/Uber/Corner Maps references); mockup published as the
"banbe Map v5" artifact (five states) before the build.

## What changed
1. **Dock only at tall** (owner chose "hide fully", no mini pill). Web: MapExplore sets `mapDockHidden` in context;
   `App.jsx` `DockRow hidden` slides it down + fades, keeps it mounted, `inert` while hidden, Reduce Motion = fade
   (`index.css`). iOS: `BottomTabBarOverlay.setSheetOpen("mapExplore.dock", …)`. Leaving the Map always gives it back.
   The list's bottom inset only reserves dock room at tall. Pure rule: `dockShown(snap)` (`src/lib/mapLayout.js`).
2. **Pins = category line icon + price** (same glyphs as the category row: `categoryGlyphMarkup` in
   `HomeDiscoveryParts.jsx`; iOS uses the category chip SF Symbols). Name under the pin at zoom ≥ 15 or when
   selected (web testid `map-pinname-<id>`, NOT `map-pin-…`, so pin counting stays right).
   **Selection lives in the sheet**: the floating card is gone (`selectedCard`, card slot in `computeMapLayout`,
   `snapForSelection` removed). Selecting → sheet to mid, list scrolls to top, first item is the selected row
   (web `map-selected-row`, iOS `map.selectedRow`) with Directions · View details · Share and the ‹ 1/3 › stack
   switcher; the event is not listed twice; "N more in this map area" under it. Inner web testids kept
   (`map-card-title/when/price/seats/close/cta/directions/stack*`) + new `map-card-share` (BanBeContext `shareEvent`).
3. **Sticky filters**: search + chips sit outside the scrolling list; once the list is scrolled (> 24 px) or an event
   is selected they fold into ONE line (`map-filter-summary`: summary text, count badge, Clear). Tap = open again
   until the next scroll/selection. Nothing filtered → the line is the search placeholder.
4. **Pan → peek**: only the user's own pan/zoom drops mid → peek (`snapAfterUserPan`; tall stays tall). MapLibre:
   `originalEvent`; MapKit JS: a start with no fresh programmatic reason. Peek strip (`map-peek-summary`): count line +
   the same summary + Clear + "+N outside". Tap = mid. Web peek is 0.84 of the height (was 0.86) to fit it; the
   reference rect still uses the peek top, so results never change with the detent. At rest at peek the list is
   hidden (no half-cut row).
5. **Cities** (no DB change): `src/data/cities.json` (14 VN + 13 US, names/aliases/centre/bounds). Pure core in
   `mapDiscovery.js` ⇄ `MapDiscovery.swift`: `cityFor` (city/province column → smallest containing box; HCMC rows
   have no province), `searchCities` (accent-free word prefix, most events first, max 3), `cityGroups` (below
   `CITY_ZOOM` 9, 512 px basis, one bubble per city + clusterPins for the rest; counts still add up),
   `activeFilterSummary` (tokens, labelled per platform). Shared fixture keys in `tests/fixtures/map-discovery.json`.
   - Search: city rows first (`map-city-row-<id>`), Go = clear the text + `destination` fit to the city box + mid.
     Works with 0 events (closes note 72's "an area with no mapped events can't be flown to").
   - Area picker: web `AreaSheet` shows a Cities section only when opened from the Map (`mapCities` published by
     MapExplore; pick → `mapCityRequest`). Home's own area selection is never changed by a city pick.
   - Zoomed out: city bubbles (web `map-city-<id>` with `data-count`, iOS `map.cityBubble.<id>`); tap = fly there.
   - Every city fly lands at ≥ `CITY_ZOOM + 0.5` centred on the city (found by the e2e run: HCMC's box incl. Cần
     Giờ fitted to zoom 8.3, so tapping its bubble showed the same bubble again).
   - The area chip names the city while the map is framed on it (`cityDest`, saved in the restore snapshot).

## Tests
- Web unit: `tests/unit/mapDiscovery.test.mjs` (+5 Map v5 tests), `tests/unit/mapLayout.test.mjs` (rewritten).
- Web e2e: `tests/map-viewport.spec.js` updated (pan now lands at peek → `backToMid`; zoom 9 for grid clusters) +
  7 new Map v5 tests (dock, pan → peek, selection row, sticky summary, city search, city bubbles, area picker cities).
- iOS: `MapDiscoveryTests` (shared fixture), `MapViewportUITests` (+ Map v5 cases). See the iOS section below.

## Known gaps
- City boxes are approximate; a city missing from `cities.json` simply has no bubble (its events stay pins/clusters).
- `tests/map-explore.spec.js` is still the stale pre-note-72 spec (unchanged here).

## iOS specifics
- Dock: per-instance token on `BottomTabBarOverlay.setSheetOpen`, released on disappear / inactive / preview.
- Peek is `.height(132)` (snapshots still store 0.12); the reference rect uses `peekHeight`. A user camera move =
  `onMapCameraChange(.continuous)` with no fresh programmatic reason and > 0.3 s after the last settle.
- Sticky header: `ScaffoldScrollProbe` gained `onScrollMetrics`; the header only folds when enough content remains to
  stay scrolled (no flicker). Empty states are now a list row, not an overlay.
- Area picker: `LocationPickerSheet(topContent:)` (Map only) → `map.areaCity.<id>`; main cities follow the viewer's
  country (VN unless located in the US). City search rows `map.city.<id>`; all city picks go through `goToCity`.
- `fittedRegion` side padding is `markerSidePadding = 64` (was 40): the wider icon + price pins hung off the screen
  edge on first open and MapKit dropped the clipped one from the accessibility tree (UI test counted 4 of 5).
- `MapExploreState.cityContextID` keeps the city chip label across Event Detail round trips.
- `MapExploreSelectionUITests`: the stale "selection survives filters" test was deleted; the other two still sign in
  with the shared account and fail on its date-of-birth gate (pre-existing, notes 49/72).
