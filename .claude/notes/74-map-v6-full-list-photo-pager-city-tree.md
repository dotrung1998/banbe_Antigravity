# 74 — Map v6: city in the area tree + one tap, full-height list with photo cards, peek → full, a useful peek strip

Status: IMPLEMENTED (web + iOS), not committed. No migration, no DB change. Builds on notes 72 and 73; everything
there still holds unless changed below.
Plan: owner device review of Map v5, 2026-11-01 (four screenshots), plan `idempotent-hugging-nygaard.md`; mockup
published as the "banbe Map v6" artifact (Area picker · Bottom strip · Search · Top Large · Top Compact · Home card ·
How the list moves) before the build.

## What changed (web)
1. **City level in the location tree** (`src/lib/locationTree.js`). VN path is now
   `loc:VN` → `|s:<state>` (if any) → `|c:<city vi name>` → `|a:<area>` → `|n:<neighborhood>`. The city is
   `cityFor(ev, cities)` (`src/lib/mapDiscovery.js`, `src/data/cities.json`: city / province column, else the smallest
   city box around the event's lat/lng), so HCMC rows with no `state_province` now sit under "TP. Hồ Chí Minh". The
   node value is the cities.json `vi` name; `locationNodeLabel` / `locationShortLabel` show the `en` name in English
   ("Quận 1, Ho Chi Minh City"); the tree search finds both. Skipped when the state already names the city
   ("Thành phố Hà Nội" has no "Hà Nội" under it) and an area equal to the city is skipped too. US unchanged (raw
   `city` column). Rows with no city and no position keep the old path (`loc:VN|a:Quận 1`), honestly.
   - `eventLocationFields` now also reads `lat`/`lng`; every caller already passed events that carry them (Home
     discovery items, the static catalogue, `shapeRealEvent` rows, Map rows).
   - `foldName` is exported from `mapDiscovery.js` (name comparison without "Thành phố"/accents).
   - Legacy ids: `migrateLegacyAreaKey(key, tree)` → `resolveCitylessId` maps an id without the city
     (`loc:VN|a:Quận 1`, also `q1`) to the ONE node with the same path plus a city; unchanged when the id exists or
     two cities would fit. BanBeContext's `curAreaKey` passes `locationTree`.
   - `cityOfNode(id)`: the cities.json city a VN city node stands for (used by the Map, below).
2. **One tap in the area picker** (`src/screens/sheets/AreaSheet.jsx`, embedded and not). Each tree row is
   `[chevron button | name button]`: the name (`area-node:<id>`, unchanged id) picks the node (= everything inside;
   non-embedded closes, embedded keeps "pick moves the selection, Done closes"); only the chevron
   (`area-chevron:<id>`, its own 44 px button, `aria-expanded`) expands. The "All in X" rows (`area-node-all-in:…`)
   are gone; "All areas" (`area-node-all`) stays. A country with a single city opens that city on open. The Map-only
   Cities section is unchanged. On the Map, a picked city node with no mapped events flies to the city's own box
   (`flyToCity`, ≥ CITY_ZOOM + 0.5) instead of leaving the camera.
3. **Full height + Large / Compact** (`src/lib/mapLayout.js`, `MapExplore.jsx`). `SHEET_SNAPS` is now
   `{ tall: 0.11 (fallback only), mid: 0.58, peek: 0.80 }`; `snapFractions(containerH, topControlsBottom)` gives the
   real values: tall = measured `topControlsBottom + TALL_GAP (8)`, peek = `peekFraction` (≤ 0.80, lowered on short
   screens so the 150 px strip always fits; iPhone SE 0.775). The reference rect uses `peekFraction`, so results still
   never depend on the detent. Dock shows at tall (v5). At tall the header gets a radiogroup (`map-layout-large`,
   `map-layout-compact`, Home's cards / list icons): Large = Home's `DiscoveryCard` with the photo pager (tap =
   `selectEvent`, testid `map-list-item-<id>` with `role="button"`, so list-selection selectors work in both
   layouts), Compact = the v5 dense rows. Default Large; the choice lives in a module variable
   (`sessionListLayout`: this session only, survives Event Detail / reopening the Map, never stored, separate from
   Home's `banbe_home_layout_v1`) and in the restore snapshot (`listLayout`). The selected row stays first. Mid
   rows unchanged.
4. **Photos** (`src/state/BanBeContext.jsx`, `src/lib/eventPhotoUrls.js`). `photoUrlsByEvent(ids, max = 6,
   { publicOnly = true })` = ONE batched `.in('event_id', ids)` query on `event_photos` (sort_order), grouped by the
   pure `groupPhotoRows` (private-bucket paths dropped by default), resolved like the first-photo path.
   `firstPhotoUrlByEvent` is now a wrapper (`publicOnly: false`, first URL) so its callers behave as before.
   `loadDiscoveryEvents` uses the new one; `shapeRealEvent` gives every row `photoUrls` (`cardPhotoList`: cover
   first, de-duplicated, max 6; non-public events cover only). Home items get `imgs`; demo catalogue events page
   through their bundled `gallery` (local `/photos/…`, the same photos Event Detail shows, no extra network).
   Map rows get `imgs` the same way (`fetchLiveEvents`).
5. **`src/components/PhotoPager.jsx`**: CSS scroll-snap track with `data-hscroll="true"` (App.jsx's root tab swipe
   ignores it), `overscroll-behavior-x: contain`, hidden scrollbar (`.bb-pager-track` in `index.css`), dots +
   "2/6" counter (bottom right), ‹ › buttons on hover / focus, ArrowLeft / ArrowRight, track aria "Photo 2 of 6",
   mouse drag on desktop (snaps; past 30 px = next photo), Reduce Motion = no smooth scroll. Only the visible photo
   and the next one are `eager`, the rest `loading="lazy"`, all `decoding="async"` (notes 22 / 40). A tap (no drag)
   calls `onOpen`; a drag never does. One photo = a plain image (still `photo-pager-<id>`, no dots/counter/arrows).
   testids: `photo-pager-<id>` (`data-index`), `photo-pager-counter-<id>`, `photo-pager-next-<id>`,
   `photo-pager-prev-<id>`. Used by Home's `DiscoveryCard` (plain, filled and polaroid) and the Map's Large cards;
   `DiscoveryRow` (list) unchanged. `DiscoveryCard` gained `testId`, `gutter`, `role`, `current` props for the Map;
   its Enter key now only fires on the card itself (not on keys inside the pager).
6. **Sheet movement**: pure `snapAfterDrag(startSnap, deltaPx, containerH, velocityPxPerMs, fractions)`: from peek
   an upward drag > 40 px (`PEEK_PULL_PX`) or a flick faster than 0.5 px/ms → tall; otherwise the nearest snap
   (unchanged). `onHandlePointerUp` tracks a smoothed release velocity (a pause > 120 ms before release = no flick)
   and handles `pointercancel`. Kept: mid + user pan → peek, tall stays, tap on the peek strip → mid.
7. **Peek strip** (row 2, `map-peek-strip`, `data-hscroll`): dark round search button (`map-peek-search`, aria
   "Search"), For You (only with saved preferences), Tonight / Weekend (`map-peek-chip-tonight|weekend`), the top 3
   categories in this map area with counts (`map-peek-chip-cat-<key>`), All filters (`map-peek-all-filters`, Home's
   filter sheet in map mode). A chip applies its filter and opens the list to mid (For You is not in `filters`, so
   the chip sets mid itself). Row 1 (`map-peek-summary`) is 36 px now and carries "+N outside" when nothing is
   filtered.
8. **Search from peek**: `map-peek-search` → focus the input SYNCHRONOUSLY in the click (iOS Safari keyboard rule,
   see the comment at `setSearchInputRef`) and lift the sheet to TALL (the keyboard covers the lower half). The
   input is therefore mounted at every snap: at peek and behind the folded summary line it is a 1 px, opacity 0,
   `tabIndex=-1` box (never display:none / visibility:hidden). While focused and empty the list area shows
   `map-search-suggest`: Recent (`map-search-recent`, `map-search-recent-<i>`; localStorage
   `banbe_map_recent_searches_v1`, max 5, every access in try/catch, `src/lib/mapRecentSearches.js`; saved on Enter
   or when a non-empty query leads to selecting an event or a city), Cities (`map-search-cities`,
   `map-search-city-<id>` with counts, tap = `goCity`), Quick filters (`map-search-quick`: For You, Tonight, Weekend,
   Seats left, All filters). Cancel (`map-search-cancel`) = blur + back to the snap the search came from. Buttons in
   the panel and Cancel keep `mousedown` from blurring the input first. Typing behaves as v5.

## Tests
- Unit: `tests/unit/location-tree.test.mjs` (+6: city level, Hà Nội not repeated, city column + area = city skip,
  US unchanged, en labels / search, legacy id migration incl. ambiguous), `tests/unit/mapLayout.test.mjs` (+4:
  measured full height, peek → full, nearest elsewhere, peek fits short screens), new
  `tests/unit/eventPhotoUrls.test.mjs`, new `tests/unit/mapRecentSearches.test.mjs`.
- e2e (written, NOT run in this pass): `tests/map-viewport.spec.js` +5 Map v6 tests (tree city + chevron + one-tap
  pick commits once; peek strip + chip → mid; pull up from peek → tall + Large + Compact rows + session memory; peek
  search → tall + focused input + recent / cities + Cancel → peek; Large card pager next + drag + wheel never leave
  the Map), new `tests/photo-pager.spec.js` (Home cards pager: next button, sideways drag + wheel keep Home, list
  layout has no pager). No `event_photos` mock needed: the demo catalogue events (live in production) page through
  their 6-photo bundled gallery.

## Known gaps / risks
- The tree only has cities that loaded events fall into; a city with no events at all is not a tree node (the Map's
  Cities section and search still offer it).
- `tests/root-tab-swipe.spec.js` swipes Home at y ≈ 300 to switch tabs; if a card photo sits there for a signed-in
  account the swipe now (correctly) moves the photos instead. That spec was already stale for Simple Shell (no Map
  tab).
- At full height the map attribution sits in the 8 px gap under the Close row (still visible, as required).
- `tests/map-explore.spec.js` is still the stale pre-note-72 spec.

## iOS
- Tree: `LocationHierarchy` VN path country → state → city (`ci:<vi name>`) → area → neighborhood; `EventLocation`
  carries lat/lng (Map rows, `CatalogEvent`, Home live rows pass them); bundled catalogue events count as HCMC.
  `migrateSelection(_:roots:)` (run in `AppState.area` didSet) maps `c:VN|a:Quận 1` to the node with a city;
  `legacyKey` ignores the city level (`area.thaodien` still works). `cityFor` caches folded names.
- One tap in `LocationPickerList` + `NativeLocationPicker` (`area.node.<id>` name, `area.chevron.<id>`). Home's header
  area control is a native `Menu` and still uses "All in X" submenus (can't do name-picks/chevron-expands).
- Full = `.height(fullHeight)` (screen − top inset − controls row); snapshots still store 0.72. Detents are
  `[peek, full]` at peek, `[peek, mid, full]` otherwise. `AppState.mapListLayout` (session, default large):
  `map.layout.large/compact`; large card `map.card.<id>`.
- Photos: `photoURLsByEvent(ids, max: 6, coverOnly:)` (one query; extras public bucket only), `mapEventPhotoURLs`,
  `eventGalleryURLs`, `DiscoveryCardModel.imgs` via `AppState.cardImages`. `Views/PhotoPager.swift`
  (`photoPager.<id>`, `photoPager.counter.<id>`, `rootSwipeExclusion`), used on Map large cards and Home cards.
- Peek 152 pt: row 1 count + summary/Clear, row 2 `map.peek.search`, chips `map.peek.chip.<key>`,
  `map.peek.allFilters`; "+N outside" dropped at peek. Search → full + focus, suggestions `map.search.suggestions`
  (recent `banbe.map.recentSearches.v1`, `map.search.city.<id>`, `map.search.quick.*`), `map.search.cancel` keeps the
  typed text and restores the detent.
- DEBUG fixtures: `shell.map` pads each event to ≥ 3 catalogue photos; `shell.home` gives `fx-near`/`fx-later` 3 each.
- Tests: `LocationHierarchyTests` (new), `MapViewportUITests` (+4), `HomePhotoPagerUITests` (new).
- Found by the final test run and fixed: (1) iOS crash on every launch that mounts the Map (also as Home's swipe
  neighbour): the static `fullHeight` read the key window's safe area during SwiftUI's first body pass and re-entered
  `tallDetent`'s lazy init. `fullHeight` now uses screen height + an estimated top inset (62 pt Face ID ≥ 800 pt,
  20 pt home button), so the full sheet top can be a few points off on an unusual device. (2) Home replaces root-swipe
  exclusion zones with the ones reported through `RootGestureExclusionZonePreferenceKey`; `PhotoPager` now reports
  through it too (otherwise a photo swipe on Home switched tabs). (3) Web pager: a mouse drag counts from the photo
  shown, not from scrollLeft mid smooth-scroll.
- Stale suites, not caused by v6 (need a rewrite): iOS `NavigationUITests` (expects Home first; signed-out launch opens
  Welcome since notes 44/48/49; `header.account` no longer exists), web specs using `setupToHome` (helpers.js: no
  Welcome step) and `home-quick-controls.spec.js` (Simple Shell Home controls).

## 2026-11-05: Map design options prototype (decision pending)

`docs/prototypes/map-options.html` (self-contained, offline SVG map of HCMC, 16 demo events from `src/data/events.js`, app tokens)
simulates five Map designs on an iPhone for the owner to choose from: A current v6 sheet, B card carousel synced with pins, C
time-first (day + start-time scrubber, time pins, out-of-window pins fade), D list-first with a Map toggle (NN/g recommends list as the
mobile default), E neighbourhood-first (district count bubbles → pins + list). Published as a private artifact. Not wired into the app.
