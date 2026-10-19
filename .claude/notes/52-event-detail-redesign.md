# 52 — Event Detail redesign (product-page pass + approved mockup)

Status: pass 1 committed (9522f32). Pass 2 (mockup match + ⋯ pop-up menu + clay accent) IMPLEMENTED LOCALLY on web
and iOS, NOT committed. Web visually checked at 390 and 320px, light and dark, as a guest. iOS visually checked in
the simulator, light and dark, via the new `shell.event` fixture (opening state, collapsed nav bar, bottom).

Sources: uxpeak "This UI/UX redesign will teach you more than 100 tutorials" (product-page teardown), event-ticketing
guidance (date/time, place, price and the CTA above the fold; total before the tap; trust near the action), and the
owner's mockup "01 · Khi mở trang / 02 · Khi cuộn xuống". Owner decisions: keep Jost (no serif), host track record
instead of star ratings (no ratings data exists), a new clay accent. Plan: `~/.claude/plans/using-this-helpful-resource-along-golden-peacock.md`.

## Layout (both platforms, same structure)
- **Over the photo**: back pill "‹ {backLabel}" plus ⋯ / Share / Save discs, all clay-tinted glass with white glyphs,
  over a top scrim. Web controls sit at `max(66px, safe-area + 16px)`. Heart is white or clay now (the old hard-coded
  red `#C8372D` is gone).
- **Collapsing nav bar** (mockup 02): once the title scrolls away, a solid paper bar covers the pinned photo strip and
  shows the event name. The controls lose their glass and become clay glyphs, and back shrinks to its chevron. The
  photo hides so it never peeks through the sheet's rounded corners. Web: `COLLAPSE_AT` + `collapsed` state, which
  flips only at the threshold. iOS: `collapsed` is derived from `scrollOffset`, plus `navBar` and `ControlChrome`.
- **⋯ menu**: the same pop-up as the calendar pill beside the title.
  - Web: shared `src/components/GlassMenu.jsx`, also used by `EventPlanTitle`.
  - iOS: native SwiftUI `Menu`, like `EventPlanTitleRow`.
  - Items: Open in map (from Home only), Back to home (not from Home), Share to Story (host only), divider, Copy link.
  - Ids: `event-detail-more` / `event.more`, `event-open-in-map` / `event.openInMap`,
    `event-share-to-story` / `event.shareToStory`, `event-copy-link` / `event.copyLink`.
- **Sheet**, top to bottom:
  1. Ink category chip (hidden when the category is empty) and a clay invite-only chip.
  2. Title with an outlined clay "Thêm lịch"/"Đã thêm" pill.
  3. Description, clamped to 4 lines with "Read more" when the About & Included sheet exists and the text is over 180
     characters.
  4. Clay track-record line: host · N events · since year (+ Following).
  5. Price at display 26 with "/ vé".
  6. **Ngày / Giờ / Địa điểm tiles** (split from `when`; the place tile links to Maps; wraps 2+1 on narrow screens).
  7. **Seats bar**, only when capacity is known (web: `eventFill` or the real row's capacity/seats_remaining; iOS:
     `eventFill`). Otherwise just the "Còn N chỗ" text.
  8. Criteria line and card.
  9. **"Bao gồm" check chips**, opening the About & Included sheet.
  10. **Host row** "Ghé {host}" (or "Trang tổ chức" when the name is empty) with an outlined clay "Nhắn tin".
  11. **Photo mosaic**: 3 tiles plus 1 wide, "+N" on the last.
- **Sticky bar**: rounded top and soft shadow, then:
  - Row 1: "1 vé · 2 vé · 3 vé" chips and a clay − n + stepper, both driving `qty` (1–6).
  - Row 2: shield line — refund promise for open paid events, else "held 30 min".
  - Row 3: ink CTA with the live total. `event-reserve-bar` / `event.actionBar` stay on the CTA itself, because
    ReserveButtonRegressionUITests taps the first match.

## Tokens
Clay is the decorative/brand accent:
- Web: `--bb-clay` (#9C5B3B light, #D8926C dark), `--bb-clay-rgb`, `--bb-clay-bg`; exported as `clay`/`clayBg` from
  `src/theme.js`.
- iOS: `Palette.clay` / `Palette.clayBg`, value for value.
- Never an error colour (that is `alert`) and never the primary CTA (ink).

## Shared logic
`src/lib/reserveBar.js` ⇄ `apps/ios/BanbeApp/Lib/ReserveBar.swift` (tests `tests/unit/reserveBar.test.mjs`,
`BanbeAppTests/ReserveBarTests.swift`):
- Price parse and total.
- Bar state priority: booking > cancelled > ended > sold out > blocked > reserve.
- Qty clamp 1–6 and presets **[1, 2, 3]**.

Change both together.

## State
- `qty` is global. Reserve reads it, so the chips and stepper pre-fill Reserve. Web has `setQty` in the context; iOS
  writes `app.qty`.
- Both platforms reset `qty` to 1 when a DIFFERENT event opens (`goEvent`).

## Testing aids
- iOS fixture `-uiFixture shell.event` opens catalogue event `bepnho` (long content, photos, included items). Use it
  for Event Detail UI tests and screenshots. Fixture events (`fx-*`) are too short to reach the nav bar.
- Web guest screenshots: set `localStorage['banbe.preferences']`, tap the splash, then open `/event/<key>`. The
  signed-in Playwright suite is blocked by the test account's DOB gate.

## Known limitations / follow-ups
- `seats_remaining` is still stale (note 50; migration 186 not applied). "N left" and sold-out can be wrong, and the
  seats bar only appears where live fill/capacity exists.
- No ratings data: the mockup's star row is the host track record. Real ratings would need a table plus a post-event
  rating flow.
- iOS place tile shows only the distance when an event has no area (fixture events).
- `ShellFixtureUITests.testAccountTabsAreSwipeableAndStayInAccount` (Account tab under 44pt) fails independently of
  this work.
