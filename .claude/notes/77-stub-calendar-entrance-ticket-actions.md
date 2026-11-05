# 77 — Ticket-stub calendar tiles, Event Detail entrance, Confirmed ticket actions (2026-11-05)

Status: IMPLEMENTED (web + iOS), committed; both build (vite, xcodebuild sim). Not visually/device checked; UI tests not run.

## Event Detail
- The calendar button left the title row. `EventPlanTitleRow` (iOS) / `EventPlanTitle` (web) is now the title alone.
- New `EventPlanButtons` (iOS `EventPlanActions.swift`, web `EventPlanActions.jsx`): two tiles at the end of the stub's date row.
  - banbe Schedule: clay square + calendar glyph + gold sparkle. One tap adds; once added, tap → status + Remove.
  - Phone calendar: `MiniCalendarPage` (red band with month, day number). iOS → system editor (once marked: Add again / Clear mark); web → Google / .ics menu.
  - Status line now shows under the stub (`event.plan.message` / `event-plan-message`).
  - Ids: iOS `event.plan.schedule`, `event.plan.calendar` (old `event.plan.button` gone; PublicEntryScheduleUITests updated). Web `event-plan-button`, `event-plan-calendar`.
- Date block bigger: min width 100, day 46pt, month/weekday 13/12.5.
- Title band: pills→title gap 12, bottom 20.
- Entrance (fresh open only; off when coming back, in preview, with Reduce Motion): pills → title → stub (rise + 0.97 scale) → day number pop → calendar tiles slide from the right → details → bar. iOS `EntranceRise` modifier (`entered` state); web `.bb-rise-in` / `.bb-pop-in` in index.css with `backwards` fill (so the title's scroll-collapse inline transform still wins after it ends), `.bb-no-entrance` on the root.

## Confirmed
- Footer rows with hairlines replaced by two tiles on `block` fill + a "More options" capsule menu.
  - Tile 1: Apple Wallet (iOS paid, not gifted, no named attendees; web only when `isAppleWalletBrowser()`, else Download PDF); gifted → Re-download PDF.
  - Tile 2: Add to calendar (mini calendar page icon, same Google/Apple menu, check when `calAdded`).
  - More: Give a ticket, Download PDF (when not a tile), View/Request Receipt (disabled while sending / after sent).
- Same ids/testids kept for every action; new `confirmed.more` / `confirmed-more-button`.

## Follow-up (2026-11-05, owner review)
- Phone calendar icon is now monochrome (iOS 27 dark style): black tile, grey weekday, white day (`MiniCalendarPage`, weekday instead of month).
- Confirmed tiles compact: icon left of the label, ~56pt tall, radius 16, gaps 10; More pill 44pt.
- Date block entrance is a calendar flip (rotateX from the top edge, slight overshoot) instead of the day pop: iOS `rotation3DEffect`, web `.bb-flip-in`.
