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

## iOS parity + smoothness pass (2026-11-19, after review)

A review of 63e5f0c / 82ab4a1 / 1f456f8 against the web found gaps and jank; fixed (iOS only, all parity changes gated
on `unified_discovery`, switch-off unchanged):

- **Home**: `HomeFilterSheet` leads with "Loại / Type" (compact `UnifiedBrowseSection`, `home.filter.type.*`, "Tất cả loại"
  opens `UnifiedTypeSheet`, single choice into `draft.cats`) and drops the Category pills; Browse by type's "Xem tất cả N"
  shows whenever there are events (web parity); the hero empty card's "Browse all events" scrolls to Near you
  (`onBrowseAll` → `nearYouScrollToken`) instead of opening Browse; the band's gear shows only under the switch, else the
  account avatar (`home.avatarButton`) as before 1f456f8.
- **Map**: an area bubble flies to pin level and selects its first event (carousel), a stack tap selects + centres, the
  neighbourhood panel never opens (restored snapshot panels ignored); a merged bubble zooms to `areaZoom - 0.15` so it
  splits (`udZoomToAreas`, web 52d562b); carousel cards 292 × 104 with an 84 pt thumb, preview title 24 light; locate is
  SF `scope`; the picked type chip is centred and the old scroll-to-start handlers skip unified mode.
- **Search sheet**: "Từ Bản đồ" when opened over the Map; source chips pinned under the field and the "Xem trên bản đồ"
  CTA pinned 30 pt above the bottom; `LazyVStack` rows; host/area hits skipped in unified mode.
- **Smoothness**: the sheet's field edits local text and writes `app.searchQuery` debounced 150 ms (flushed on Xong,
  submit, clear, chips, disappear), so typing no longer re-renders Home/Map per keystroke; focus is set 350 ms after
  presentation; the dock hides from `RootView` `.onChange(of: unifiedSearchOpen)` (`setSheetOpen("search.sheet")`) before
  the slide-up; the sheet is hosted on RootView's root ZStack; the Map's results pipeline is memoised in
  `MapResultsCache` (key: events, For You order, query, filters, committed bounds, fill, minute; per-row search docs;
  one-pass category counts) and the redundant `mapSearchText` / second `searchQuery` mirroring is gone in unified mode.
- Checked: `xcodegen generate` + `xcodebuild -destination 'generic/platform=iOS Simulator'` green. NOT run on a
  simulator or device, no UI tests; Instruments not used, so the smoothness gains are reasoned, not measured.
- Simulator pass (iPhone 17 Pro, iOS 26.5, `-uiFixture shell.home -uiFixtureV23 YES -uiFixtureUnified YES`), 2026-11-19:
  seen working: gear in the band + "Xem tất cả 7" with no type; filter sheet leads with Loại tiles, a pick selects the
  tile and recounts ("Xem 3 sự kiện"); Search sheet with no dock, pinned source chips and CTA, results follow typing,
  CTA count follows; Map with no dock, `scope` locate, query carried; an area tap flies to pins with the 292-wide
  carousel on the first event and no panel; a type chip tap centres the chip and the Filters pill names the type;
  Search over the Map says "Từ Bản đồ". Switch off: avatar back in the band. NOT checked: merged-bubble split (the
  fixture has no merged bubble), swipe-to-dismiss, keyboard (hardware keyboard on the simulator), real device feel.
  Merged-bubble split checked later the same day: "2 khu · 7" split into Quận 3 (1) + Quận 1 (6) at area level.
- **Search vs Map count (2026-11-19)**: two real causes fixed. (1) Both Maps (web `MapExplore.jsx` `searchedEvents`, iOS
  `computeResults`) now drop a live row 12 h past its start, as Search already did (`ENDED_AFTER_MS` / `endedAfter`) —
  without migration 167's job, past "live" events stayed on the Map only. (2) iOS `SearchMatch.buildDoc(for: MapEventRow)`
  now adds the event-type facts (`EventTypes.detailSearchTerms`), like the CatalogEvent doc and web's single
  `buildEventSearchDoc`. Web build green, unit 1022/1022, iOS simulator build green. STILL DIFFERENT BY DESIGN (web too):
  Search counts the demo catalogue (`EventCatalog.all` / `src/data/events.js` minus real keys) and events anywhere, while
  the Map counts only real rows with coordinates inside the committed area, so "Xem trên bản đồ · N" can exceed the
  Map's "Danh sách · N" (simulator: Gallery → Search 7, Map 5; the two extra were catalogue entries such as AEIE: Mở
  Xưởng). Owner decision (same day): **count only map events**. Done on web + iOS under `unified_discovery`:
  - The Search sheet's list, results head, CTA count (and its Filters counts on iOS) keep only docs with a Map row that
    has lat/lng, matched by row `id` OR `slug` (a demo-catalogue key is its live row's slug; real events' key is the id).
    Web: `mapPlottable` / `mapPoints` / `anyOutside` in `src/lib/unifiedDiscovery.js` (unit-tested), Search.jsx reads
    the Map's rows (or fetches them via the now-exported `fetchLiveEvents`); iOS: `AppState.mapPlottablePoints`
    (built in `mapEvents` didSet, id + slug keys), `mapEventsKnown`, SearchView loads map events when empty. Both map
    selects now include `slug` (`MapEventRow.slug`). Until map rows load, the old list stays (no empty flash).
  - The CTA sets `mapFitRequest` (web state / iOS `AppState.MapFitRequest`); the Map fits its camera to the N results'
    points when any lies outside the committed area (web `fitCamera` 'destination', iOS `.cluster`), else nothing.
  - Checks: web build green, unit 1023/1023; iOS simulator build green. Simulator: "Gallery" from Home/Map → 2 results,
    both plotted. The shell fixtures replace `discoveryEvents` with fixture rows, so Search there cannot see real rows
    like `sonmai-2` that the Map plots (it correctly drops the stale catalogue `sonmai`, which has no map row); a real
    data check needs the switch on in production or a fixture that loads real discovery events. The camera fit was not
    exercised (no result fell outside the view). Known limits: the Map's own hour window / For You can still narrow it
    below N; with more than 500 public events the Map loads only the visible area, so Search narrows to that area.

## Owner polish pass (2026-11-19, from screenshots)
- iOS "Xem trên bản đồ" CTA hugs its label (centred, 24 pt side padding) instead of full width; web already did.
- iOS Map list's floating "Bản đồ" button lifted above the home indicator in unified mode (`safeBottom + 10`); web
  already added `env(safe-area-inset-bottom)`.
- iOS Map price: the outlined ticket icon after paid prices (`priceView`) removed everywhere on the Map; VoiceOver keeps
  "/ ticket". Web never drew it.
- Simple Shell dock redesigned (web `BottomTabBar.jsx`, `DockCreateCenter.jsx`, `index.css` `.bb-dock-simple*`; iOS
  `BottomTabBar.swift` `SimpleDock`/`DockSurface`/`SimpleDockGlyph`, `DockCreateButtonView.swift`, `AccountAvatarView`
  `ringed:`): 64 tall pill (max 370 wide) with glass + hairline + shadow, five equal slots, inset 52 × 44 ink capsule for
  the active tab (springs between slots, jumps under Reduce Motion), one 24 px / 1.8 stroke icon set on both platforms
  (filled only when active), 48 clay "+" inside the pill, 16 tall Saved badge with a ring, 28 avatar with a ring;
  Reduce Transparency = opaque surface. Legacy dock unchanged. Seen on the simulator in light and dark.
- Event Detail cover flash: the v2.3 hero drew a brown radial plate with the event's first letter under the photo
  (iOS `EventDetailView.swift` `v23HeroBackdrop`, web `EventDetailV23View.jsx`), and on iOS the hero's 1100 px request
  missed the row's smaller cached decode, so the plate showed until the full decode. Now the plate shows only for an
  event with no photo; iOS `PhotoLoader.cachedAnySize` + `RemoteImage(anySize:)` paints the row's cached decode on the
  first frame (else `mat` + a 0.2 s fade, none under Reduce Motion); web `useImageReady` + `--bb-mat` + 180 ms fade.
  Simulator: tapping Bếp Nhỏ №12 on Home zoomed straight from its photo, no plate.
- Checks: web build green, unit 1023/1023; iOS simulator build green. Web guest-shell Playwright specs still fail at
  onboarding (pre-existing, note 90), not re-run on the base commit.

## Owner pass: See all, empty tab card, Map loading (2026-11-19)
- **See all (iOS)**: the end card's tap did nothing because `.onChange(of: nearYouScrollToken)` and `.id("home.nearYou")`
  lived inside a LazyVStack child that is not built while off screen. Now a zero-height `home.nearYou` anchor is a
  direct LazyVStack child and the onChange sits at the ScrollViewReader level; the anchor lands the heading under
  the folded 58 pt band (Reduce Motion: no animation). The pager's dashes now count cards + the end card and light
  the last dash on it (`dashIndex`). Simulator: For You end card → "Near you" under the band, last dash lit.
- **Empty tab card (iOS `HeroEmptyCard` in HomeShellV5Views.swift, web HomeShellV5.jsx + `.bb-hero-empty*`)**: full
  rail width (24 pt gutters), min 360 tall, 16 radius, hairline, tonal gradient with clay glow + vignette or the
  weekend's first cover blurred behind; tracked kicker (TONIGHT / THIS WEEKEND / FOR YOU [+ · area]), serif headline
  ("A quiet night." / "Đêm nay yên ắng.", "A quiet weekend." / "Cuối tuần yên ắng.", For You "Your picks start
  here." / "Gợi ý của bạn bắt đầu từ đây.", narrowed "No picks here yet." / "Chưa có gợi ý ở đây."), one line of
  what's next with the real weekend count when known (web `heroLists().weekendTotal`), ONE paper primary pill and
  the rest as quiet links; fan of up to 3 weekend covers on Tonight. Note-97 action logic and all ids unchanged.
  Web `home-hero.spec.js` 6/6 on chromium/webkit/firefox (width check now rail − 48).
- **Map loading (iOS MapExploreView.swift)**: "All 0" / "List · 0" came from framing only after the photo-URL fetch
  (no committed area), and the empty black bar was `emptyCard` with no matching branch. Now the Map frames as soon
  as rows arrive, a `MapLoadingCover` (paper/dark surface + softly pulsing pin capsules, static under Reduce
  Motion) covers it until MapKit's first camera change after framing + 0.35 s or 1.5 s max or a failed load, chip
  counts and "List · N" hide (spinner) until `countsKnown`, `emptyCard` needs content, the carousel needs its row.
  Web: chip/List counts hidden while loading (no cover). Simulator (dark): cover → framed map with real counts.
- Checks: iOS simulator build green; web build green, unit 1023/1023.
