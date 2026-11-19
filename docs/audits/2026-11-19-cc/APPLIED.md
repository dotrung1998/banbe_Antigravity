# APPLIED — audit 2026-11-19 (CC)

Working tree: local `main`, nothing pushed, no PR, no deploy. One commit per finding (rows 37+38 share one
copy commit, as they touch the same two strings). All migrations are new files; no applied migration was edited.

`/docs/audits/` is generated output and stays ignored, with one narrow exception `.gitignore` now carries (owner,
2026-11-19): this ledger and the before/after screenshots for rows 25 and 29 are tracked, and the screenshots ride in
the two fix commits themselves. The ledger is committed just after them, because it cites their shas.

## Rows

| # | Status | Commit | Files | Check |
|---|--------|--------|-------|-------|
| 1 | applied | `014874b` | `supabase/migrations/20261231000222_222_bookings_insert_lock.sql`, `supabase/rollbacks/…222…`, `supabase/tests/222_bookings_insert_lock/` | local Postgres (`g-db`, `ON_ERROR_STOP=1`), 5/5 |
| 2 | applied | `166a58f` | migration `…223_223_organizers_private_columns.sql` + rollback + `supabase/tests/223_organizers_column_grants/`, `src/state/BanBeContext.jsx`, `src/screens/sheets/PaymentQrManager.jsx` | local Postgres 9/9; `npm run build` green |
| 3 | applied | `e97b1a8` | migration `…224_224_events_client_write_guard.sql` + rollback + `supabase/tests/224_events_client_write_guard/` | local Postgres 13/13 |
| 4 | applied | `7264ca0` | `api/send-email.js` (deleted), `src/lib/sendEmail.js` (deleted), `README.md` | `npm run build` green |
| 5 | applied (owner action: rotate the password) | `68d960e` | `apps/ios/BanbeAppUITests/ScreenshotCatalogTests.swift`, `apps/ios/BanbeAppUITests/UITestAuthHelpers.swift`, 6 UI-test files | read env, no literal credential left. The password in git history must be rotated by the owner |
| 6 | applied | `911b62b` | `src/lib/eventEnd.js`, migration `…225_225_no_booking_after_event_ends.sql` + rollback + `supabase/tests/225_event_ended_hold/`, callers in `Home.jsx`/`Search.jsx`/`MapExplore.jsx` | local Postgres 9/9; `test:unit` 1042/1042 |
| 7 | applied | `e270b69` | migration `…226_226_taken_event_keys.sql` + rollback + `supabase/tests/226_taken_event_keys/`, `src/screens/Search.jsx`, iOS `AppState+Data.swift`/`SearchView.swift` | local Postgres 7/7 |
| 8 | applied | `b3fc339` | `src/lib/homeDiscovery.js` + iOS `Lib/HomeDiscovery.swift` (`almostFull`) | build + unit |
| 9 | applied | `ae95390` | migration `…227_227_checkin_requires_payment.sql` + rollback + `supabase/tests/227_checkin_payment/` | local Postgres 7/7 |
| 10 | applied | `d27be3e8` | `supabase/migrations/20261231000230_230_verify_payment_expired_state.sql`, `supabase/rollbacks/…230…`, `supabase/tests/230_verify_payment/` | `verify_payment` refused before any write (INVALID_STATE, state `expired`) for an expired status or payment_state, and `expired` left the allowed list; the status trigger is unchanged. Tested on `g-db` (7/7): expired → INVALID_STATE and row untouched, pending/expired → INVALID_STATE and untouched, pending/holding → confirmed, rollback → the old trigger error. Callers already handle `success: false` (`BanBeContext.jsx:3906`), so the error is no longer a raw P0001 |
| 11 | applied | `12e2741` | `api/_lib/handlers/cronPurgePaymentDocuments.js`, `api/_lib/handlers/cronWalletPassSweep.js` | build green; behaviour read from source (fail closed when `CRON_SECRET` unset) |
| 12 | applied | `9bfc2e9` | `api/auth/index.js` | build green; admin delete now 403 without `admin_event_wipe` |
| 13 | applied | `13bef88` | `src/screens/Home.jsx`, `src/screens/AdminManageEvents.jsx`, `apps/ios/BanbeApp/Views/AdminManageEventsView.swift` | build + unit; iOS `xcodebuild build` green |
| 14 | applied | `b0afab6` | `src/state/BanBeContext.jsx` (`takenEventKeys`, `loadTakenEventKeys`), `src/screens/Search.jsx` | build + unit |
| 15 | **disputed** | — | — | `total` is the pre-filter base (`Home.jsx:648-659`: `total: shortlistBase.length`) while `rows` are that base narrowed by the filters; `shortlistEnd` prints “You’ve seen every event” only when nothing is hidden (`listEnd.js:15-37`), and the “N of M shown” copy when filters hide rows. `390-home-scrolled.png` shows “15 sự kiện” over 15 rendered events |
| 16 | applied | `559c36c` | `src/App.jsx` (lazy + `Suspense`) | build green; entry chunk 3,370 → 3,271 kB, 99 kB moved to on-demand chunks |
| 17 | applied | `5cf667f` | `src/screens/Search.jsx` (`cardDateBadge`), `src/screens/MapExplore.jsx` (`eventWhen`), `src/screens/Home.jsx` (rail copy) | build + unit |
| 18 | applied | `08b23e0` | `src/state/BanBeContext.jsx` (`goSchedule`/`goProfile`/`goInbox`), `src/lib/guestAccess.js` (`account` context) | build + unit |
| 19 | applied | `48cfc67` | `src/lib/onboardingFlow.js`, `tests/unit/onboardingFlow.test.mjs` | unit 1042/1042 (the two skip→recap assertions assert the new behaviour) |
| 20 | applied | `55a1bae`, `519359c3` | `src/index.css` (`.bb-home-head__mid`, `@media (max-width: 339px)`), `src/components/event/TicketStubV23.jsx` | build + unit. Visual pass 2026-11-19: at 320 the chip no longer touches the search circle (20 px gap) and is icon-only (its old shrink clipped the label to "N"); the stub footer wraps — "Lưu ngày" on its own row, "Thêm banbe" + "Lịch" beside it, "/ vé" stays on one line. Light + dark |
| 21 | applied | `2465afa` | `src/lib/mapDiscovery.js`, `tests/fixtures/map-discovery.json`, `apps/ios/BanbeApp/Lib/MapDiscovery.swift` | unit (fixture regenerated); iOS build green; **not visually checked** · Visual pass 2026-11-19: area bubbles read "N khu vực", labels do not collide at 390/320, light + dark |
| 22 | applied | `6ad0089` | `src/screens/Search.jsx` | build + unit |
| 23 | applied (visual pass: no clay text under 4.5:1 on Home or Event, light + dark) | `a7d22bc` | `src/index.css`, `src/theme.js`, `src/components/event/TicketStubV23.jsx`, `src/screens/PublicProfile.jsx`, `apps/ios/BanbeApp/Views/BanbeTheme.swift`, `tests/fixtures/design-tokens.json` | unit (tokens fixture); iOS build green |
| 24 | applied | `8949ddc`, `d87c72f7` | `src/index.css` (`--bb-text-meta` 12 px, `--bb-text-kicker` 11 px), 118 `src/**/*.jsx` files, `src/screens/CreateEvent.jsx` (map credit .45 → .65), `src/screens/MapExplore.jsx` (area-bubble "+N" was built in a runtime cssText string and kept 10.5 px) | 559 inline sizes and 6 CSS sizes now read the floor token; uppercase tracked kickers keep 11 px. `npm run build` green, `npm run test:unit` 1042/1042. Visual pass 2026-11-19, light + dark: Home 39, Home 320 39, event 50, filter sheet 0, login gate 0 sub-12 px nodes — every one uppercase with letter-spacing; the map now has none either (the "+N" moved to the token; only MapLibre's own 10 px attribution stays, by design) |
| 25 | applied | `cc0cd15`, `d3a8dd11` | `src/screens/sheets/HomeFilterSheet.jsx` | Close 44×44 and Reset 58×44 from `cc0cd15`; the visual pass then found the When/availability/sort chips at 38 px and "Price for 2" at 16 px, now all ≥ 44 px (`d3a8dd11`). Measured in the running app at 390 and 320, light + dark: 24 buttons, none under 44; with the sheet scrolled to the end the deepest control ends 77 px above the sticky CTA (76.7 before), so density and CTA clearance are unchanged. Ported by computed height/rect, screenshots `filter-{390,320}-{light,dark}-after.png` |
| 26 | applied | `2fd465c` | `src/components/home/HomeShellV5.jsx`, `src/screens/Home.jsx` | build + unit · Visual pass: each card's save control is an icon button with aria-label "Lưu sự kiện", no chip text |
| 27 | applied | `1e75695` | `src/screens/EventPlanActions.jsx` (the calendar chip) | build + unit · Visual pass: the stub chip reads "Thêm banbe" with a bell icon |
| 28 | applied | `297a5e3` | `src/screens/sheets/HomeFilterSheet.jsx` | build + unit · Visual pass: with the sheet scrolled to the end the price slider and every chip sit above the sticky CTA (deepest control ends 692 px, CTA starts 769 px); CTA carries no duplicate sub-line |
| 29 | applied | `bc22170`, `d33e0e01` | `src/App.jsx` (`DOCK_CLEARANCE`), `src/screens/Home.jsx`, `src/components/home/HomeShellV5.jsx` (`guestNotice` slot between the band and the photo hero) | `bc22170` gave the feed its end clearance; the visual pass found the guest banner still under the floating dock at 320×700 (36 px). The banner now renders above the photo hero (`d33e0e01`). Measured in the running app at 390×844 and 320×700, light + dark: banner 115–209, dock starts 764 / 620, rects do not intersect; end-of-feed clearance still 156 px; the photo card's bottom row stays above the dock. Screenshots `home-{390,320}-{light,dark}-after.png` vs `home-320-{light,dark}-before.png` |
| 30 | applied | `1fc73c5` | `src/screens/Login.jsx` | build + unit · Visual pass: the theme control reads "☾ Tối" / "☀ Sáng"; the Facebook row is dashed, tagged "Sắp có" and disabled, with its note beneath |
| 31 | applied (5/5 on the simulator) | `8d0ff46` | `apps/ios/BanbeAppUITests/NavigationUITests.swift`, `…/Views/BottomTabBar.swift`, `…/Views/SecurityView.swift` | 5 safe NavigationUITests: **5 passed, 0 failed** (`xcodebuild test`, simulator `B601F39F`) |
| 32 | applied | `e9db089` | migration `…229_229_photo_insert_scope.sql` + rollback + `supabase/tests/229_photo_insert/` | local Postgres 6/6 |
| 33 | applied | `fa37c84` | `src/data/events.js` (`VENUE`) | build + unit |
| 34 | not-a-defect | `a5f2a6e` (earlier) | `tests/unit/mapStyle…` | `npm run test:unit` 1042/1042 |
| 35 | applied | `13391b2` | `src/screens/MapExplore.jsx` (chip row offset) | build + unit; **not visually checked** · Visual pass 1280: filter and locate controls sit inside the phone frame (x 777 / x 461), nothing clipped |
| 36 | applied | `dae6587` | `src/components/home/HomeShellV5.jsx` (`tabLabel`) | build + unit · Visual pass: a guest sees "Tất cả · Tối nay · Cuối tuần" — no "For You" claim without prefs |
| 37 | applied | `4b219e3` | `src/lib/guestAccess.js` | build + unit |
| 38 | applied | `4b219e3` | `src/lib/eventEnd.js`, `src/screens/Home.jsx`, `src/screens/CreateEvent.jsx`, `apps/ios/BanbeApp/Lib/V23EventRules.swift`, `…/Views/HomeV23Sections.swift`, `…/Views/OnboardingViews.swift`, `tests/unit/eventEnd.test.mjs` | build + unit 1042/1042 |
| 39 | not-a-defect | — | `apps/ios/BanbeApp/Views/Sheets.swift` (`AreaMenuOptions`, `AreaSearchSheet`) | Every string goes through `app.T(vi, en)`; the sheet was located and read |
| 40 | not-a-defect | — | `apps/ios/BanbeApp/Views/HomeShellV5Views.swift` | Area, view, search, Map, quick settings, account and the wordmark each carry a localized `accessibilityLabel` |
| 41 | **blocked: needs owner DB check** | — | — | No production DB access from this machine: whether migration 183 is applied (and the conditional P0 in `01-money-access.md`) cannot be checked |

## Needs owner

- Rotate the UI-test password that used to live in `ScreenshotCatalogTests.swift` (row 5).
- Check whether migration 183 is applied in production (row 41 / `01-money-access.md` M2).
- Apply the new migrations (222–227, 229) with the usual `supabase db push` when the owner is ready — none were applied
  here, and nothing was deployed.

## Follow-ups from the visual pass

- Map attribution stays 10 px: MapLibre's compact legal control, not app copy (deliberate).

## Not verified

- iOS `xcodebuild build` on the simulator: **BUILD SUCCEEDED** (rows 2, 5, 7, 8, 13, 21, 23, 31, 37, 38 compile).
- iOS `NavigationUITests` (row 31): **all five pass** in one `xcodebuild test` run on simulator `B601F39F`
  (157–160 s): feed → event → back, event → Host tab → organizer profile, Home filter sheet narrowing the feed,
  area menu narrowing the feed, and Security as its own Account row. Run individually first, then as one suite twice.
- Visual coverage (2026-11-19 pass): web Home 390/320, Event 390/320, Filter sheet, Map 390/320/1280, Login gate — light and dark where the screen has one. Rows 20, 21, 23, 25–30, 35, 36 and the row-24 floor were checked; screenshots in `docs/audits/2026-11-19-cc/shots/` (plus a follow-up pass at 390/320, light + dark, for rows 25 and 29: before/after pairs). Signed-in screens and iOS devices were not covered, and row 31 is the iOS test row (already 5/5).
- Row 24: verified through computed styles rather than a screen-by-screen eyeball pass; tight 16 px badges at 12 px type
  should still get one look on a device.
- Production ACL/runtime behaviour for rows 1, 2, 3, 9, 32 is proven on the local Postgres only. The policies were not
  exercised against the hosted database.
- Row 11's cron behaviour and row 12's admin gate were read from the source and built; neither was exercised against a
  live scheduler or a real admin session.
