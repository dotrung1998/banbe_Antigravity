# 79 — Map "E+": neighbourhood bubbles, day + hour window, List · N overlay (2026-11-06)

Status: IMPLEMENTED (web + iOS), committed locally, NOT pushed. Web: Playwright + unit tests green. iOS: builds, UI tests green except one skip (below). NOT checked on a real iPhone, in dark mode on iOS, with VoiceOver, Dynamic Type XXXL or iOS Reduce Motion. SUPERSEDES the bottom-sheet parts of notes 72–74 (peek/mid/tall snaps, handle, peek strip, selection-in-sheet, Tonight/Weekend chips). Design reference: `docs/prototypes/map-options-v5.html`, tab "E+ Theo khu · giờ".

## Owner decisions (2026-11-05)
- Replace the Map outright: no switch, no migration.
- Days: Today · Tomorrow · next weekend day · Next week (Mon–Sun) · All days (off).
- Slider 10:00 → 02:00, 1-hour steps. iOS list is an in-hierarchy overlay, not a system `.sheet`.
- Default is All days (nothing dimmed at first); the mockup starts at Today 19:00. One-line flip in `defaultWindow` use.

## Layout
- Full-screen map, opens on one bubble per neighbourhood with an event count. Zoom: city (< 9), area (9–13), pins (≥ `AREA_ZOOM` 13). Tap a bubble/chip → fly in + area panel (46%, not draggable); zoom out below 12.5 closes it. Panel hides the dock (`dockVisible`).
- Bottom stack: area chips, time bar (58 pt slot always reserved), "List · N" + locate. Reference rect never depends on zoom, panel, list or window.
- List: no handle, top = measured bottom of the shared search/chip row, veil fades with the pull; close by pull from scroll-top (>110 px or flick), "Map" pill, Esc (web), escape gesture (iOS). Rows render only while open.
- A pin or row opens Event Detail directly; Back restores camera/area/window/list.

## Data (no migration)
- Area = event's own `area` text (fallback `neighborhood`), folded; "district N" = "quận N"; none → "other". Centroid/bounds client-side; bubbles of one city closer than 56 px merge.
- Service day: calendar day in the event's own `tz`, 00:00–03:59 counts as the previous day. `inWindow`: from inclusive, to exclusive, today 2 h grace. Seats from `get_public_event_fill`.
- Hit set is a client Set per knob step; markers restyled in place, never rebuilt, no network per drag.

## Tokens
Existing only. NOT in repo and not added: `--me`, `--land/--water/--park/--road/--maplabel`, `--desk/--bezel`. Constants `MAP_DIM`, `LIST_PULL` in `mapLayout.js` ⇄ `Lib/MapLayout.swift`.

## Files
- Shared logic (fixture twins): `src/lib/mapTimeWindow.js` ⇄ `Lib/MapTimeWindow.swift`; `mapDiscovery.js` ⇄ `MapDiscovery.swift`; `mapLayout.js` ⇄ `MapLayout.swift`.
- Web: `screens/MapExplore.jsx`, `components/map/MapTimeBar.jsx`, `MapListSheet.jsx`, `GlassMenu` (`alignLeft`, `above`, `checked`).
- iOS: `Views/MapExploreView.swift`, `Views/Map/{MapAreaViews,MapTopControls,MapTimeBar,MapListOverlay}.swift`, `Views/RangeSlider.swift` (also used by `PriceRangeSlider`). `HomeFilterSheet` hides the date section in map mode on both. Home's date hands over via `windowFromHomeDate`.
- Pull on iOS uses the List's own `UIScrollView` pan (`ListTopPullProbe`), no SwiftUI DragGesture (note 06).

## Tests
- Web: `tests/map-viewport.spec.js`, `tests/map-list-sheet.spec.js`, unit `mapTimeWindow/mapDiscovery/mapLayout`.
- iOS: `MapViewportUITests` (fixture `shell.map`; DEBUG hooks `map.debug.zoom`, `map.debug.pinchPad`), `MapEPlusUITests`, `MapListSpikeUITests`, `MapDiscoveryTests`, `MapTimeWindowTests`.

## Known gaps
- iOS knobs report as "Other" to XCUITest, so tests drag; VoiceOver adjustable action untested.
- `testFilterSheetCloseDiscardsAndApplyCommits` now skips (no free event in live data), apply path unverified.
- iOS opening an area panel flies without committing an area (web commits once via `.cluster`); iOS "All areas" commits once.
- `AREA_ZOOM = 13` is a tuning guess. Basemap tiles looked blank in some headless shots.
- Old map specs from note 72 are stale where they assume the sheet.
