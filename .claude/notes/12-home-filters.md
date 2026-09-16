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
