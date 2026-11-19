# 99 — Unified discovery (Home + Map share one search) and Saved = Schedule (2026-11-18)

Status: IMPLEMENTED LOCALLY (web + iOS), NOT committed. Migration 221 written, NOT applied. Source of the design:
`docs/prototype/unified-home-map-prototype-v2.html` (owner-approved prototype, design language of the apps).

## Part 1 — Schedule reads Saved from the server (no switch, live for everyone once shipped)
Owner rule: "Lịch đọc thẳng danh sách Đã lưu từ máy chủ".
- The Schedule's source `added` IS the account's Saved list (`public.favorites`, owner-only RLS, no migration needed),
  relabelled **"Đã lưu" / "Saved"** (iOS symbol `heart`). Saving = adding to the Schedule; "Bỏ lưu" removes both.
  Bookings and hosting still outrank it (one row per event).
- Web: `scheduleSnapshot` reads `s.favorites`; `addToBanbeSchedule` / `removeFromBanbeSchedule` call `toggleFav`;
  `reloadFavorites` re-reads the table when Schedule opens (inside its 45 s throttle) so a save on another device shows.
  iOS: `scheduleSavedKeys` (= favorites when signed in), `loadScheduleData` re-runs `loadFavorites`, add/remove call
  `toggleFavorite`. `scheduleAddedKeys` (AppState.swift) is no longer read.
- The old device-local list (web `scheduleStore`, iOS `InAppCalendarStore`, note 44) is moved into `favorites` ONCE
  after the account's favorites load (upsert, ignoreDuplicates), then cleared. A failed upsert keeps it for next time.
- Every heart (both apps) shows a toast above the dock: "Đã lưu · thêm vào Lịch banbe" + date · name, or "Đã bỏ lưu ·
  gỡ khỏi Lịch banbe", with **Hoàn tác** (~4.5 s). Web `SaveToast` in App.jsx (state `saveToast`, `toggleFav(k,
  { silent: true })` for the undo); iOS `State/AppState+SaveToast.swift`, rendered in RootView.
- Copy updated: Schedule screen, EventPlanActions, Help (Personal guide "Schedule"; iOS HelpContent regenerated with
  `node scripts/gen-help-content-ios.mjs`). Tests: `tests/unit/schedule.test.mjs`, iOS `SchedulePresentationTests`,
  `Fixes45Tests`, `PublicEntryScheduleUITests` (label "Saved"), fixture `fx-added` is now a favorite.

## Part 2 — Unified discovery, behind admin switch `unified_discovery` (migration 221, seeded OFF)
Needs `home_v23` (+ `simple_shell`). Off = every screen exactly as before. Rollback:
`supabase/rollbacks/20261231000221_221_revert_unified_discovery_switch.sql`.

Owner decisions (2026-11-18): Map time = ONE chip whose popover keeps every option; Home tabs = the shared time;
Browse by type filters Home in place; ship behind a switch, default OFF. Quick-settings button stays as each app has it
(web avatar, iOS as today).

Shared state (one source of truth, both apps): time = `homeFilters.date` (tabs: For You↔any, Tonight↔today,
Weekend↔weekend; tomorrow/week show as For You); type = `homeFilters.cats`; price/seats = rest of `homeFilters`;
sort = `homeSort`; area = `area`; query = `searchQuery` (persists after Search closes). Home, Search and the Map read
and write these directly (no one-shot hand-off), so a pick anywhere shows everywhere.
Pure rules: `src/lib/unifiedDiscovery.js` ⇄ `Lib/UnifiedDiscovery.swift`, fixture `tests/fixtures/unified-discovery.json`
(tab↔date, top-5 types, picked-tile rule, type sheet order + search, area glyphs, `ownedFilterCount` = what the
Filters badge counts: type, price, seats, almost full, type chips, sort; NOT time or area).

Home: shared query narrows every list (Search's matcher); state bar (query · type · price · … · N, Map pill, × clears
query + owned filters, keeps time) only when a query or an owned filter is on; Browse by type = 5 busiest types (tap
toggles in place) + "Tất cả loại" tile → type sheet with search; a picked type that is not a tile takes over the 6th
tile ("· đổi"); map banner under the Shortlist; clay dot on the band's search circle while a query is on.
Web `src/components/home/UnifiedHomeParts.jsx`, iOS `Views/UnifiedDiscoveryViews.swift`.
Search: a "Bộ lọc" row opens HomeFilterSheet; event hits respect the shared filters (web: Home publishes
`s.unifiedKeys`, only while Search is the overlay over Home).
Map: time chip + popover (`MapTimeChip.jsx` / `Views/Map/MapUnifiedViews.swift`, same day choices + hour knobs, dim
not hide; the day writes the shared date, hours stay map-local), area bubbles list their type glyphs (max 4, +N), a pin
selects (no direct Event Detail) and shows a card carousel (`MapEventCards.jsx`), a card opens a preview with "Xem chi
tiết" for every event + "Giữ chỗ" for paid ones (hidden when sold out on web), compact "− +" zoom capsule (map's own
control hidden), Filters badge = `ownedFilterCount`. Back from Event Detail restores the preview (web snapshot).

## Tests (2026-11-18)
- Web: `vite build` green; `npm run test:unit` 1022/1022; `tests/public/home-unified.spec.js` 15/15 (chromium,
  firefox, webkit); `tests/map-unified.spec.js` 5/5 chromium (25/25 with --repeat-each=5). Existing home-v23-pager,
  home-hero, home-live-line, browse-v23: 26/27 — `browse-v23.spec.js:327` (EndCard dashed edge) fails, EndCard not
  touched here. `map-viewport` / `map-list-sheet` cannot reach Home (guestToHome helper times out on onboarding, same as
  on the base commit per note 90), so the switch-off Map is covered only by map-unified's switch-off test.
  Screenshots via `MAP_SHOTS=<dir>` / `V23_SHOTS=<dir>`.
- iOS: builds for the simulator; BanbeAppTests 633 run, 2 failures, both `GiftTicketPDFTests:91` (not touched here);
  UnifiedDiscoveryTests 8/8, SchedulePresentationTests 16/16, Fixes45Tests 9/9. UI tests NOT run. Fixture flag
  `-uiFixtureUnified YES`. Only Home was looked at on the simulator; Map, Search, type sheet and toast NOT visually
  checked on iOS. Run `xcodegen generate` after pulling (new files).

## Known gaps / open
- iOS: the clay search dot on Home's band lives in `Views/HomeShellV5Views.swift`, interleaved with the owner's
  uncommitted header rework (HeaderCircleButton + gear), so it was NOT in the note-99 commit; it lands with that work.
- "Giữ chỗ" opens Event Detail plainly (no "open ready to reserve" intent exists yet).
- Map "Tuần sau" (Mon–Sun next week) and Home's `week` (next 7 days) are written to the same shared value but mean
  slightly different windows.
- Map For You and (iOS) Map sort stay map-local.
- iOS shows the carousel only after a pin is selected; a card tap does not move the camera (moving would commit a new
  map area and change the results).
- Web Map on MapKit JS (when enabled) does not pan the selected pin into view (no projection).
- The Shortlist heading stays "Chọn lọc" (prototype said "Gần bạn", but the list is soonest-first, not nearest).

## Prototype v2 parity pass (web), 2026-11-18

Owner ran the web app with migration 221 applied and said it did not exactly mirror
`docs/prototype/unified-home-map-prototype-v2.html`; asked for all of it, dock included. Web only.

- **Home order** now follows the prototype: hero → live line → shared state bar → Browse by type →
  "Gần bạn" list → map banner → footer line. (Browse by type used to render above the live line and the
  state bar, and the Shortlist was titled "Chọn lọc".)
- **Band**: while `unified_discovery` is on, the third circle is the quick-settings gear (it opens the same
  quick sheet); the account avatar lives in the dock's slot, as in the prototype.
- **Dock** (Simple Shell): icon-only 338 × 62 pill, ink active capsule with a paper glyph, clay 52 px centre
  "+" with no label, 26 px account initials, Saved count in a clay capsule on the calendar, labels removed
  for sighted users (the aria-label keeps the name). Legacy (switch-off) dock unchanged.
- **Shortlist**: heading "Gần bạn" / "Near you" with "N sự kiện · gần nhất trước"; Browse by type always
  shows "Xem tất cả N".
- **Map**: bottom row is zoom left, "Danh sách · N" centred, locate right (target glyph, not the compass
  emoji); carousel cards 292 × 104 with an 84 px thumb; preview title 24 px light.
- Checks: `npm run build` green, `npm run test:unit` 1022/1022. Web app not visually compared in this VM
  (no browser/deps for Playwright); a device pass is still the owner's check.

## Prototype v2 parity pass 2 (web), 2026-11-18

Owner's second report after the pass above: (1) the dock did not hide completely on scroll, (2) "See all" still
opened the Browse-by-type screen, (3) the Map was still not the prototype, (4) Search was not the prototype. Web
only, still read against `docs/prototype/unified-home-map-prototype-v2.html`.

- **See all** (hero rail end card per tab): under `unified_discovery` it now scrolls the app's scroll viewport to
  `home-shortlist-section` minus 70 px (`data-act="list"` in the prototype), instead of `openBrowse()`. The
  shortlist end-card "Tất cả loại" opens the in-place `UnifiedTypeSheet`, and Home's empty-state Browse links
  (`onBrowseAll`, `onBrowseType`) filter Home / scroll instead of opening Browse. Browse is now unreachable from
  Home in this mode; its screen and the switch-off paths are unchanged.
- **Dock on the Map**: with the three unified flags on, the Map no longer renders the floating dock at all (the
  prototype has no dock there), so the `mapDockHidden` peek logic is bypassed. Legacy Simple Shell without
  `unified_discovery` keeps its dock and its Map tab.
- **Map**: `dockClear` is 0 in the unified Map (nothing to clear), the chip row is now the prototype's
  time chip + hairline + "All"/every type with its count (sorted by count, zero-count last), the For You / seats /
  price / area chips and the whole area-card row are gone, and the bottom row (zoom left, "Danh sách · N" centre,
  locate right) sits 22 px off the bottom instead of above a dock. The carousel now sits above that row (as in the
  prototype's `.map-bottom` flow) and the preview card above it too.
- **Search** (unified overlay): the sheet is now the prototype's content — "Từ Trang chủ" + "Trang chủ + Bản đồ"
  meta chips, "Gần đây" chips (hidden once a query is typed), the existing filter link, a results head
  ("N kết quả cho …" / "N sự kiện") with "Cùng kết quả với bản đồ", `EventRowV23` rows with save hearts (same rows
  the Map shows), the "Không có sự kiện nào khớp." end card with "Xoá bộ lọc", and a bottom "Xem trên bản đồ · N"
  CTA. The category, trending, host and area groups are no longer rendered in this mode. Search rows now know an
  event's `catKey` (added to both the real and demo doc builders).
- Checks: `npm run build` green, `npm run test:unit` 1022/1022. This pass WAS rendered in a headless Chromium
  against the demo catalogue (iPhone viewport): Home's See-all card scrolled to "Near you" with no Browse screen,
  the Map had no dock and no area chips and its type row showed All 18 + every type, and Search listed 19 event rows
  with the source chips, results head and "See on the map · 19" CTA. Found and fixed two rendering bugs this way: the
  type chips mapped category objects instead of keys (only "All" rendered) and the Map's locate button was at 0.16
  opacity. The dock's hide also carries `data-collapsed` + an explicit CSS opacity now, because the row's `bbIn`
  entrance animation (fill both) and Reduce Motion's pinned `translate` could leave it visibly on screen.
- Not yet re-checked on a phone; the owner's device pass is still the final visual check.

## Prototype v2 parity pass 3 (web), 2026-11-18

Owner's follow-up on pass 2: Search must open as the prototype's bottom sheet — its own grabber, in-sheet field and
an Xong button — instead of the app's shared top search bar.

- **Search (unified, web)**: under `unified_discovery` the Search panel renders inside `NativeSheet` (the app's
  `<dialog>` sheet primitive), so it rises from the bottom over a scrim with focus containment, Esc / back-gesture
  dismissal and a press-outside close. Geometry follows the prototype: top 48 px and 28 px corners, a 38 × 5
  grabber, a 48 px surface-2 field (clay icon, clay focus border, its own clear button) beside **Xong** (`Done` in
  English), the source chips pinned under the field as `.search-meta`, then recent chips / filter link / results
  head / `EventRowV23` rows / empty card in their own scroller, and the `Xem trên bản đồ · N` CTA pinned 30 px
  above the panel bottom like `.search-cta` — so it stays put at one result or nineteen.
- **Shared bar**: `PersistentSearchBar` steps aside for the unified Search sheet (it stays for the Map and for the
  pre-switch Search screen), removing the old back + field row above the sheet.
- **Switch off**: unchanged full-screen Search with the shared bar; the new content wrapper is `display: contents`
  there, so the page is laid out exactly as before.
- Checks: `npm run build` green, `npm run test:unit` 1022/1022. Rendered in this VM's cloud Chromium against the
  demo catalogue (390 px, all three switches on): dialog open, panel top 48 / 28 px corners, grabber + focused
  in-sheet field + Xong present, shared bar absent, 19 rows; the source chips stayed at y=138 while the body
  scrolled 400 px; the CTA sat 30 px above the panel bottom with 19 rows and with one (`piano`); Xong closed to
  Home and saved the query to recents. Switch-off path re-checked with the flags RPC stubbed false: no dialog,
  full-screen Search, shared bar and its input present.
- Not device-verified; the owner's phone pass is still the final visual check.

## Web Map follow-up (owner's phone pass), 2026-11-19
- **Search like Home's**: the unified Map no longer uses the shared live bar (PersistentSearchBar steps aside on the
  Map too, and MapExplore stops registering with it, which otherwise ping-ponged with the Search sheet: "Maximum update
  depth exceeded"). Its own row: glass Back, a capsule (clay magnifier, the shared query or a placeholder, ×) that opens
  the SAME Search bottom sheet over the Map (App.jsx mounts `<Search overlay />` on mapExplore when the switch is on;
  its source chip says "Từ Bản đồ", and "Xem trên bản đồ" just closes it), and the Filters button.
- **Filters button shows the type**: with a type picked it becomes an ink pill (glyph + name + sliders) with a badge for
  the OTHER owned filters; otherwise the glass sliders circle with the count. The picked type also scrolls into view
  in the chip row.
- **Filters sheet**: `HomeFilterSheet unified` (Map and Home) leads with "Loại / Type" as the compact Browse-by-type
  tiles (`UnifiedTypeGrid compact idPrefix="home-filter-type"`: 5 busiest + "Tất cả loại" opening the searchable type
  sheet, single choice, "Xem tất cả" clears) and drops the Category pills.
- **No old area list**: an area tap (bubble, area chip, stack) flies in at pin level and opens the horizontal carousel on
  that area's first event; the 46 % neighbourhood panel never opens in unified mode (a restored snapshot's panel is
  ignored too).
- **Summary away on zoom out**: leaving pin level (area or city) closes the preview card.
- **Top band**: the Map is no longer a night-strip screen (App.jsx `darkTop`), so the status strip takes the theme's
  paper instead of the dark smear over the tiles.
- Checks: build green, unit 1022/1022, `map-unified` 8 + `home-unified` 5 tests = 39/39 on chromium, firefox and
  webkit. Not re-checked on a phone (the status strip in particular only shows on a real iPhone home-screen app).

## iOS mirror of the web prototype-v2 passes (2026-11-19)

The web passes 1–3 and the Map follow-up were web-only; this pass ports what the iOS app was missing.

- **Home order**: hero → live line → shared state bar → Browse by type → "Near you" list → map banner →
  `banbe · pick an evening, meet a few people`. The Browse block is one `v23Browse(_:)` builder, rendered above the
  shortlist for both switch states.
- **Shortlist**: heading **"Gần bạn" / "Near you"**, sub `N events · soonest first` (`N of M events` when filters
  narrow it), and the empty card says "Nothing in Near you matches these filters".
- **See all**: under `unified_discovery` the rail's end card scrolls Home to the `home.nearYou` anchor
  (`nearYouScrollToken` + the existing `ScrollViewReader` proxy passed into `v23GoerFeed`); the shortlist end card's
  "Browse by type" opens the in-place `UnifiedTypeSheet` instead of Browse.
- **Dock (Simple Shell)**: 338 × 62 pill with a hairline border and one soft lift, icon-only slots, a solid ink active
  capsule with a paper glyph, 26 pt account avatar, a clay 52 pt centre "+" with no label, and the Saved count in a
  clay capsule on the calendar (`favorites.count`).
- **Map**: the dock window hides entirely at `mapExplore` when all three switches are on; `dockClear` is 0 there, so
  the bottom row (zoom · List · N · locate) sits 22 pt off the bottom and the carousel/preview ride above it; the chip
  row is the time chip + hairline + All + every type with its count (busiest first); neighbourhood chips are off and a
  preview closes when the camera leaves pin level.
- **Search (unified)**: source chips ("From Home" / "Home + Map"), recent chips while no query is typed, the Filters
  row, a results head ("N results for …" / "N events") with "Same results as the map", `EventRowV23View` rows with
  save hearts, the "Nothing matches" card with Clear filters, and the "See on the map · N" CTA.

Follow-up (same day): **Search is now the prototype's bottom sheet** under `unified_discovery` — `SearchView(unifiedSheet:)`
drawn in a `.large` sheet with 28 pt corners, its own 38 × 5 grabber (system indicator hidden), a 48 pt in-sheet field
with the clay focus border and its own clear button, and **Xong**; the shared `PersistentSearchBar` steps aside for it and
for the Map. **The Map has its own search row** in the same 44 pt slot: glass Back, a query capsule that opens the same
sheet over the Map, and a **Filters button that shows the picked type** (ink pill with glyph + name + sliders, badge for
the other filters) or the glass sliders circle with its count. `AppState.unifiedSearchOpen` is the sheet's presenter;
`openSearch` routes to it under the switch, `goHome` and "See on the map" close it, and over the Map the CTA just closes
(the map already shows the same results).

Still not mirrored: the filter sheet is not type-first; an area bubble still opens its panel (chips are gone but bubble
taps are unchanged); Home's hero empty card still opens Browse. Checked: `xcodegen generate` + `xcodebuild …
-destination 'generic/platform=iOS Simulator'` build green; no simulator run, no UI tests, nothing visually checked.
