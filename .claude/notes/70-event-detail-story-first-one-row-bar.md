# 70 — Event Detail story-first + one-row booking bar (web + iOS)

Status: IMPLEMENTED (web + iOS), 2026-10-31, not committed. No migration. Checked in Chromium/Firefox/WebKit at 390×844
and in the iOS simulator (iPhone 17 Pro), light + dark, English. Not device-verified; VI not screenshot-checked.

## Why
Owner device screenshots of `bepnho` after note 68 showed ten problems. The owner picked layout B (story-first) and a
one-row bar from the proposal page.

## Root causes found (keep these)
- **Seat bar vs "3 left".** This was not a code bug. Production data for `bepnho` is `capacity 3, seats_remaining 3`,
  and `get_public_event_fill` returns booked 0. The "14" only appears in the About text ("Mười bốn chỗ"). The bar
  showed a booked share of 0 next to a scarcity label.
  - Fix: the bar only shows once ≥ 1 seat is booked, and the pill reads "N of M left".
  - Web also never fetched the fill on a direct open, and fell back to the never-decremented `seats_remaining`. It now
    loads the fill on open (`loadEventFill` ⇄ `.task loadPublicEventFill`) and uses the fill only (iOS parity).
- **Date tile.** Don't format it from `ev.startDate`. Demo `startDate` is a browser-local Date, and `bepnho`'s seeded
  `starts_at` (19:00Z) is 02:00 next day in Vietnam, so the tile would disagree with the Time tile (taken from the
  `when` text). `dateTileLabel` therefore localizes the same "Th 4, 04.11" text: EN "Wed 4 Nov", VI unchanged.
  - The seeded `starts_at` of the demo rows looks off by the seeder's local zone. Not fixed; it is a data question.
- **Place tile.** `stripKm` added a distance with no threshold. Event Detail now shows only the area as the value.
  `distanceLabel` (≤ 50 km; m / one decimal / whole km; `.` EN, `,` VI) replaces the "Place" label. `stripKm` is
  unchanged for other screens.
- **Diet chip.** `detailFacts` joined multi choices with ", ". It now also returns `values`, and `splitFacts` makes one
  chip per value. The first chip keeps `event-type-fact-dietary` / `event.typeFact.dietary`; later ones get `-2`, `-3`.
- **Quantity.** The cap was a flat 6. Now `maxQty(remaining)` ⇄ `ReserveBar.qtyCeiling(remaining:)` and
  `clampQty(n, max)`. The web context `setQty`/`qtyPlus` use the open event's fill too. `hold_seats` stays the
  authority, and there is no per-person limit in the data.

## What changed
- **Hero.** Pills and the title sit on the photo over a bottom scrim, `HERO_SCRIM` ⇄ `heroScrim` = 0 at 20% → 0.70 at
  55% → 0.78. A unit test checks white text ≥ 4.5:1 on a white photo.
  - The calendar control gets an `onPhoto` variant (web `EventPlanTitle`, iOS `EventPlanTitleRow`).
  - The collapse/title hand-off still keys off the title frame (web `titleProgress` now uses `offsetTop` directly).
  - Hero stays 320.
- **Sheet order:**
  1. Price + seat pill
  2. One-line Date/Time/Place tiles (they wrap/stack only at accessibility sizes)
  3. Alcohol/diet chips + type rows
  4. Who can reserve
  5. Host
  6. About
  7. "On the menu"/"Included" as its own chip section (`event-included-items` ⇄ `event.includedItems`)
  8. Photos
- **"More ›".** It stays on About (`event-included-section`). When About is hidden, the included heading takes it over.
- **Who can reserve.** Rendered by `criteriaPlain` ⇄ `ReservationCriteria.plain(vi:)`: "Open to people into Supper
  club", then one suffix:
  - "✓ You qualify" when the eligibility check says yes. On iOS that is `reserveEligibleKey`, server only. On web it is
    the server answer or the existing local fallback.
  - "Sign in to check" for guests.
  - An unmet result keeps the existing card. `criteriaSummary` / `summary(vi:)` are still used by Create review.
- **Photo strip.** `stripPhotos` drops the hero URL and repeated URLs. The viewer still opens on the full list at the
  tapped photo.
- **Bar.** One row: a 44pt stepper and the CTA "Reserve · total", then a centred refund line. The 1·2·3 presets are gone
  (`QTY_PRESETS` / `ReserveBar.presets` removed).
- **Separators.** On Event Detail, `▪︎` became `·` in visible copy (CTA, waitlist, blocked, invite chip). The internal
  `' ▪︎ '` delimiter in `where`/`when` stays. There was no app-wide sweep.

## Tests
- **Shared fixtures:** `tests/fixtures/event-detail-presentation.json` (new groups: `splitFactsValues`,
  `includedSection`, `distanceLabel`, `dateTileLabel`, `stripPhotos`, plus seat cases), new
  `tests/fixtures/criteria-plain.json`, and `event-types.json` detailFacts `values`.
- **Unit:** JS `npm run test:unit` gives 671 pass. iOS `EventDetailPresentationTests`, `ReserveBarTests`,
  `EventTypesTests` and new `CriteriaPlainTests` give 38 pass.
- **E2E / UI:**
  - `tests/event-detail-compact.spec.js` adds: bar ≤ 12% of 844, one-line tiles, title above the sheet, rules before
    the host, no "Any of:"/"▪", no VI date in EN. Passes in 3 browsers × 2 themes.
  - `tests/event-detail-intro-included.spec.js` now runs signed out (`guestToHome`) and passes.
  - `EventDetailCompactUITests` adds: bar height, title band, `dietary-2`, EN date, no km, "of 3 left", and the stepper
    stopping at 3. The fixture seeds `bepnho` fill = 0/3 (mirrors production).
- Run `xcodegen generate` after pulling (new test file).

## Open (owner)
- Distance threshold 50 km and the bar-only-when-booked rule are my recommendations from the plan, applied as defaults.
- An app-wide `▪︎` sweep (Home, Dashboard, Confirmed, countdown strings) is not done.
