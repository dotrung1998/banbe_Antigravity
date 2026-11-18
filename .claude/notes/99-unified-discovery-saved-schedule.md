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
