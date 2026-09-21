# Home screen filters: attending / saved / sold out / district (2026-09-16)

## Status: WORKING (web + iOS), first pass

## Audit — what already exists, reused as-is

**"Attending" status set — reused exactly, not redefined.** Note 04
(`.claude/notes/04-admin-escalation.md`, "2026-09-15" section) already
nailed down the canonical "Going" status set after a real bug: bookings
query `.in('status', ['pending', 'confirmed', 'attended'])` —
`'expired'`/`'cancelled'`/`'no_show'` never count. Confirmed still current:
- Web: `src/state/GocContext.jsx:690-697` (`loadMyEvents`) and `:2499`
  (`loadPaymentBookings`'s own copy) both use the identical three-value
  list; result lands in `s.attending`, read via `isGoing(key)` at
  `GocContext.jsx:1656`.
- iOS: `apps/ios/BanbeApp/State/AppState+Data.swift:260` (`loadMyEvents`)
  — same three values; `isGoing(_:)` at `AppState.swift:526`.

The new "Đang tham gia" (attending) filter chip on Home just calls
`isGoing(e.key)` per row — no new query, no new definition.

**"Saved" — `isSaved`/`toggleFav` reused, but flagging a real gap: this is
NOT backed by `public.favorites` today, on either platform**, even though
the table already exists (`supabase/migrations/20260906000003_003_social_chat.sql:30-34`,
`(user_id, event_id)` PK + owner-only RLS). Grepped both clients for
`from('favorites')`/`.from("favorites")` — zero hits anywhere. `s.favorites`
(`GocContext.jsx:267`) and iOS's `favorites` (`AppState.swift:179`) are both
plain in-memory arrays, toggled locally (`toggleFav`/`toggleFavorite`,
`GocContext.jsx:1657`, `AppState.swift:946-948`) and never read from or
written to the DB table — a reload empties them (web doesn't even persist
to `localStorage`, unlike `located`/`lang`/`theme`). **This filter ticket
reuses `isSaved`/`s.favorites` exactly as they already behave** (matching
the existing "Lưu" button's own definition of "saved" on every card, so
the filter and the button never disagree) — it does **not** fix the
missing DB persistence, which is a separate, bigger piece of work (wiring
real reads/writes to `favorites` across both clients) outside this
ticket's scope. Flagging it here rather than silently building on top of
it without saying so.

**"Sold out" — reused exactly: `e.soldOut`, a static catalogue flag, NOT a
live `seats_remaining` computation.** Checked both places that already
show "Hết chỗ": `src/screens/EventDetail.jsx:29` and `src/screens/Home.jsx:89`
(pre-existing, before this ticket) both branch on `ev.soldOut`/`e.soldOut`
directly — which comes from `src/data/events.js`'s hardcoded `STATUS` map
(e.g. `fanci: { soldOut: true }`, `events.js:87`), not from `public.events
.seats_remaining`. Confirmed via `src/lib/countdown.js:83-95`
(`liveEventOverrides`) — the one place a real DB row's live status gets
reconciled onto the static catalogue — that it only overrides
`cancelled`/`ended`, never seats/sold-out; this is consistent with note
11's already-documented architectural fact that Home's feed is the static
catalogue, not a live query, and iOS mirrors this identically
(`apps/ios/BanbeApp/State/AppState.swift:984`, `event.soldOut`). The new
"Hết chỗ" filter chip reuses this exact same flag — it does not introduce
a second, live-seats-based definition of sold-out that could disagree
with the "Hết chỗ" text already shown on the same card.

**"District/area" — the ticket's own concern about `public.events.area`
being free-text is correct, but moot for this screen.** Queried the real
column directly (`supabase db query --linked`):
```
select distinct area, count(*) from public.events group by area order by 1;
```
→ a real mix of clean district names (`Quận 1`, `Quận 3`, `Thảo Điền`, …),
bare city names (`Ho Chi Minh City`, `Hanoi` — from whatever seed/demo rows
those are), and at least one venue-plus-district compound
(`Yentown, Quận 1`) — genuinely inconsistent free text, confirming a
dropdown built directly off this column would show duplicate/incoherent
options. **But Home doesn't need one**: it already has its own curated,
non-free-text district picker — `AREAS` (`GocContext.jsx:302-309`; iOS
mirror likely named similarly, see `AppState.swift`'s `currentArea`/`AREAS`
usage) — five fixed entries (`Toàn Sài Gòn`/`Quận 1`/`Thảo Điền`/
`Bình Thạnh`/`Quận khác`/`Đà Nẵng`) matched via `.includes()` against the
**static catalogue's** own `meta` string, not the live DB column at all.
This is already wired into Home's header (`openArea`/`curArea`,
`Home.jsx:143`) and already combines with the category filter in the same
`feed` computation (`Home.jsx:84`). **No new area UI was built** — the new
attending/saved/sold-out chips just compose with this existing picker,
since it already always applies to `feed`.

**Category/filter model, reused, not duplicated a third time**:
`FILTER_DEFS` (`src/screens/Home.jsx:7-13`, exported for note 11's map
screen too) stays exactly as-is — the three new toggles are a *second*,
independent row of chips (multi-select, AND-combined with the single-select
category row and the area picker), not folded into `FILTER_DEFS` itself
(attending/saved/sold-out aren't categories, and note 11's map chips
already established the "everyone"/"open now"-style pattern of a separate
boolean-toggle chip row alongside the category row — this reuses that same
UI pattern, not a new one).

## Implementation

**Web** (`src/state/GocContext.jsx`):
- New `initialState` fields: `filterAttending: false`, `filterSaved: false`,
  `filterSoldOut: false`.
- New `toggleHomeFilter(key)` — `key` one of `'attending'|'saved'|'soldOut'`,
  flips the matching boolean.
- `clearFilters()` extended to also reset all three to `false`, alongside
  its existing `filter`/`area` reset — "Xem tất cả" clears every Home
  filter, not just category/area.

`src/screens/Home.jsx`:
- `feed`'s `useMemo` filter predicate gains three more `&&` clauses (only
  applied when the corresponding toggle is on): `(!s.filterAttending ||
  isGoing(e.key))`, `(!s.filterSaved || isSaved(e.key))`,
  `(!s.filterSoldOut || e.soldOut)`.
- New chip row directly under the existing category row, same visual
  language (`fieldGlass`, active state = filled/bordered, matching note
  11's map chip styling): "Đang tham gia" / "Đã lưu" / "Hết chỗ",
  `data-testid="home-filter-attending"` / `"home-filter-saved"` /
  `"home-filter-soldout"`.

**iOS** (`apps/ios/BanbeApp/State/AppState.swift`):
- New `@Published var filterAttending = false`, `filterSaved = false`,
  `filterSoldOut = false`.
- New `toggleHomeFilter(_ key: String)` mirroring the web action.
- `clearFilters()` extended the same way.
- `feed` computed property gains the same three `.filter { }` clauses.

`apps/ios/BanbeApp/Views/HomeView.swift`:
- New chip row under `filterTabs`, same `Button`/capsule pattern as the
  category tabs, `accessibilityIdentifier`s
  `filter.attending`/`filter.saved`/`filter.soldout`.

## New facts found while implementing

(none yet — appended below as they turn up)

## 2026-09-21 follow-up — real 48h expiry, isGoing narrowed to confirmed-only, extended chip set, Appearance toggle

**Confirmed real bug in the "Sự kiện của bạn" strip's 48h expiry, with a live before/after check**: `EVENTS`' (`src/data/events.js`) `endedHoursAgo` is a hardcoded number baked in at module-load time — e.g. `phokhuya: { endedHoursAgo: 10 }`, `motlop: { endedHoursAgo: 74 }` — that never increases as real time passes. Queried the real `events` rows directly (service-role script, not assumed):

| slug | catalogue's static `endedHoursAgo` | real `status` | real `starts_at` | consequence before this fix |
|---|---|---|---|---|
| `phokhuya` | 10 (frozen forever) | `ended` | 2026-08-19 (~33 days ago) | stuck at "10 hours ago", **never** cleared from the strip despite being weeks past the real 48h cutoff |
| `motlop` | 74 (already > 48) | `live` | 2026-09-28 (**upcoming**) | permanently hidden from the strip as if long-ended, even though it's a real future event |

Both are real, opposite-direction bugs from the same root cause (a frozen number standing in for a live clock) — one item that should have cleared never did, one item that shouldn't have been hidden always was.

**Fix**: new batched live-status fetch — `loadHomeLiveEvents()` (`GocContext.jsx`, right after the existing single-event `liveEvent` effect; `AppState+Data.swift`, right after `loadLiveEventStatus()`) — queries `events(slug, status, starts_at, cancelled_at, cancel_reason)` for every catalogue key at once (public info, no sign-in gate, same as the existing single-event version), stored in new `s.homeLiveEvents`/`app.homeLiveEvents` (keyed by catalogue key). `Home.jsx`'s new `withLive(e)` / `AppState.swift`'s new `withLive(_:)` merge this onto a catalogue event via the SAME `liveEventOverrides`/`Countdown.liveEventOverrides` function `curEvent` already uses for a single event — applied to both `feed` and `savedList`/`savedStrip` before their own filtering. `endedHoursAgo` is only ever set once `status == 'ended'` (confirmed by re-reading `liveEventOverrides`'s own branches) — an upcoming/ongoing event's `endedHoursAgo` stays `null` regardless of `homeLiveEvents` having a row for it, so the 48h clause (`!(e.endedHoursAgo != null && e.endedHoursAgo > 48)`, unchanged) structurally can never fire for anything that hasn't actually finished. Re-ran the same live query after implementing: `phokhuya` now resolves `endedHoursAgo ≈ 792` (correctly excluded), `motlop` now resolves `endedHoursAgo: null` (correctly no longer hidden).

Caption renamed (was "Tự xóa sau 48 giờ"/"Clears after 48h", implying everything in the strip is time-limited) to "Sự kiện đã qua sẽ ẩn sau 48h"/"Past events clear after 48h" — `Home.jsx`, `HomeView.swift`.

**`isGoing` narrowed to genuinely confirmed/paid**: was `s.attending.includes(k)`/`attending.contains(key)` — any booking that merely HOLDS A SEAT (`status` IN pending/confirmed/attended, the canonical "Going" set this note's own original pass deliberately chose for seat-holding purposes, note 04). Requested explicitly this pass: narrowed to `payment_state === 'confirmed'` (a free/instant-confirm booking also gets this immediately — `hold_seats()`, migration 053) via `s.paymentBookings`/`app.paymentBookings`, which Home already loads. **Confirmed safe via repo-wide grep before narrowing**: `isGoing` has exactly one consumer on each platform (`Home.jsx`/`AppState.swift`'s own `feed` + `HomeView.swift`) — `s.attending`/`attending` itself (Account.jsx's "Going" count, EventList.jsx's "going" mode) is READ DIRECTLY by those screens, not through `isGoing`, and is therefore UNCHANGED — still seat-holding, out of this ticket's scope. New `isAwaitingConfirmation(key)`/`isAwaitingConfirmation(_:)` — has an active booking (pending/confirmed/attended status) that's still `holding` or `pending_verification` — backs the new "Chưa xác nhận" filter.

**Chip set extended** (`HOME_EXTRA_FILTERS`/`homeExtraFilterChips`): added `notAttending`/`notConfirmed`/`notSaved` (straightforward inverses/refinements, now meaningful since `attending` is confirmed-only) plus `upcoming`/`ended` (judged genuinely useful, implemented directly per this ticket's own instruction not to just propose ideas) — `upcoming` = `!cancelled && endedHoursAgo == null`, `ended` = `endedHoursAgo != null`, both reusing the same live-merged event objects `withLive` produces, not a separate computation. New state fields `filterNotAttending`/`filterNotConfirmed`/`filterNotSaved`/`filterUpcoming`/`filterEnded` on both platforms, `toggleHomeFilter`/`clearFilters` extended to match. Not mutually exclusive with their own inverse (e.g. toggling both `attending` and `notAttending` together is allowed, yields an empty feed, same as any other contradictory AND-combined chip combination already possible before this pass).

**Appearance toggle**: Home's header gained a light/dark quick-toggle next to the language/area switchers, separated by this app's own "▪" glyph (already used in event captions like "Th 5, 09.07 ▪ 21:00") — `Home.jsx` (wired to the existing `toggleTheme`, already used by `Preferences.jsx`), `HomeView.swift` (wired to the existing `pickTheme(_:)` — iOS has no `toggleTheme()` convenience, so this calls `pickTheme` directly with the flipped value, still the same write/persistence path `Preferences.swift`'s own theme picker uses, not a parallel one).

**iOS-only compiler note**: `feed`'s computed property (`AppState.swift`) hit "the compiler is unable to type-check this expression in reasonable time" once extended to 8 `.filter` clauses in one chained expression — split into three intermediate `let` bindings (category/area, attendance, saved/status) to fix; purely a Swift type-checker limit, no behavior change.

Both `vite build` and `xcodebuild -destination 'generic/platform=iOS Simulator'` succeed.

## 2026-09-21 second follow-up — language toggle size, chip set pruned/reordered/wrapped, Home scroll-position preservation

**Task 1 — language toggle text size**: `toggleLang`'s own button (`src/screens/Home.jsx`'s header, `HomeView.swift`'s `header`) bumped 11px/11pt → 13px/13pt + semibold, scoped to that one control only (area/appearance stay at their existing size) per this ticket's own "without unbalancing the header" instruction.

**Task 2 — chip set pruned/reordered/wrapped**: `notAttending`/`notSaved` removed entirely (their own state fields, `toggleHomeFilter` cases, `clearFilters` resets, and `feed` filter clauses all removed too, on both platforms — not left as dead code). Remaining six reordered to `[upcoming, saved, attending, notConfirmed, soldOut, ended]` — Upcoming/Saved/Attending lead, Ended stays last. "Upcoming" already existed from the prior pass (CONFIRMED FACT this ticket itself flagged, checked before assuming it needed adding) — reused as-is, already computed from `withLive`'s real (not baked-in) event status. Row layout: web's `overflowX: 'auto'` single row → `flexWrap: 'wrap'` (`Home.jsx`); iOS's horizontally-scrolling `ScrollView` → `FlowLayout` (`MapExploreView.swift`'s own reusable wrapping layout, already used for Map Explore's category row — reused directly rather than writing a second one). Every chip is now always visible, wrapping to a second line instead of requiring a swipe.

**Task 3 — Home scroll-position preservation**: confirmed a real, generic mechanism already exists — `src/App.jsx`'s `Shell` component has a `scrollPositions` ref keyed by `state.screen`, saved on every scroll event and restored via `useLayoutEffect` on screen change. In principle this already covers Home↔Event-Detail (both ends are literally `state.screen === 'home'`/`'event'`) — but the reported bug is real: Home's own `loadHomeLiveEvents()` (added the same day, prior entry above) fetches asynchronously and can shrink/reorder `feed`/`savedList` a beat AFTER the synchronous `useLayoutEffect` restore already ran, silently pulling the restored position back toward the top once the page's total scrollable height changes underneath it. Fixed generically in `App.jsx` (not Home-specific): a `ResizeObserver` on the scroll container re-applies the same saved target scrollTop for as long as the user hasn't scrolled again themselves since the restore (a real scroll flips a local `userScrolled` flag that stops the corrective re-apply), for up to a 2s settle window — long enough for a real network fetch to resolve and reflow, short enough to never fight a screen with genuinely dynamic content indefinitely.

iOS has no equivalent generic mechanism at all (confirmed via grep — no per-screen scroll-position map anywhere) and no raw pixel-offset restore API at this project's iOS 17 deployment target (`ScrollPosition`/`.scrollPosition(_:)` for an arbitrary Y offset is iOS 18+). Built a scoped one using iOS 17's own `.scrollPosition(id:)` (bidirectional: reports which id is at the top as the user scrolls, AND scrolls to that id once the view reappears with a non-nil binding already set) — `ScreenScaffold` (`Components.swift`) gained an optional `scrollPositionID: Binding<String?>?` parameter that, when passed, applies `.scrollTargetLayout()`/`.scrollPosition(id:)`; `HomeView` passes `$app.homeScrollAnchorID` (new `@Published` on `AppState`, survives the view being torn down/recreated on navigation the same way `mapExploreState` does) and gives each feed `EventCard` a stable `.id(event.key)` — only the event cards are id'd, not the header/banners/chips, since "which event card was on screen" is the only meaningful restore granularity here.

Both `vite build` and `xcodebuild -destination 'generic/platform=iOS Simulator'` succeed. No schema changes this pass.
