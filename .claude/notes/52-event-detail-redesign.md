# 52 — Event Detail redesign (product-page pass)

Status: IMPLEMENTED LOCALLY (web + iOS), NOT committed. Web visually checked at 390px (light + dark) as a guest;
iOS builds and `ReserveBarTests` pass; on-device / simulator visual check still pending.

Source: uxpeak "This UI/UX redesign will teach you more than 100 tutorials" (product-page teardown) plus event-ticketing
guidance (title, date/time, place, price and the CTA above the fold; transparent price/total before the tap;
trust near the action). Plan: `~/.claude/plans/using-this-helpful-resource-along-golden-peacock.md`.

## What changed (both platforms, same structure)
- **Photo controls**: back is a 40pt icon-only disc like share/save (destination kept as the accessibility label and,
  on web, visually-hidden text so `event-detail-back` innerText still reads "Map"/"banbe"). Top gradient scrim.
  Web controls sit at `max(66px, safe-area + 16px)`. iOS discs use `nativeGlass` + hairline + shadow (was a flat
  85% paper fill).
- **⋯ menu** (`event-detail-more` / `event.more`): "Back to home", "Open in map", "Share to Story" moved here from
  text links above the title. Test ids unchanged (`event-open-in-map`, `event.openInMap`, `event.shareToStory`); UI
  tests that tap Open in map now tap the menu first.
- **Header**: uppercase letter-spaced category, single "invite only" chip (the duplicate sentence is gone), title,
  then a **key-facts block**: date/time (was missing from the page entirely), place, seats, price. The place row
  drops the day/time segments of `ev.where` (it is "area ▪︎ distance ▪︎ day ▪︎ time").
- **Body**: description 15pt / roomier leading / 85% ink, 4-line clamp + "Read more" only when an About & Included
  sheet exists and the text is > 180 chars. Host card (40pt avatar, Following, track record, Message pill) moved up;
  photos moved up with a count; one "About & included" row with a chevron (only tappable rows get one). The old
  bottom Price row and floating refund note are gone.
- **Sticky action area**: material bar with hairline; seat presets 1 · 2 · 4 + "More" (stepper 1–6); CTA shows the
  live total ("Giữ 2 chỗ ▪︎ 1.800.000₫"); one trust line under it ("Held 30 min while you pay ▪︎ full refund if
  cancelled", refund half only for open paid events). Blocked-by-criteria now says "Not eligible yet ▪︎ see why" and
  scrolls to `CriteriaUnmetCard` instead of a dead tap.

## Shared logic
`src/lib/reserveBar.js` ⇄ `apps/ios/BanbeApp/Lib/ReserveBar.swift` (tests `tests/unit/reserveBar.test.mjs`,
`BanbeAppTests/ReserveBarTests.swift`): price parse, total, bar state priority (booking > cancelled > ended > sold out
> blocked > reserve, same order as the old inline chain), qty clamp. Change both together.

## State
- `qty` is global; Reserve already reads it, so a preset pre-fills Reserve. New `setQty` (web context).
- **Both platforms now reset `qty` to 1 when a DIFFERENT event opens** (`goEvent`) — before, a quantity carried over.

## Known limitations / follow-ups
- `seats_remaining` is still stale (note 50; migration 186 not applied): "N left" and sold-out can be wrong. Presets
  are capped only by the 1–6 rule, not by seats left.
- Heart red `#C8372D` still hard-coded on both (pre-existing exception, not `alert`).
- `event.actionBar` must stay on the CTA itself (ReserveButtonRegressionUITests taps its first match; a container id
  would be inherited by the seat chips).
- Playwright e2e is blocked locally (Home/Splash never resolve for the signed-in suite account: DOB gate). Guest
  browsing works for screenshots: set `localStorage['banbe.preferences']`, tap the splash, open `/event/<key>`.
- Phase 3 (not done, needs a product decision): "N going"/attendee avatars (host opt-in), ratings/reviews (no data
  model), sticky title in the nav on scroll.
