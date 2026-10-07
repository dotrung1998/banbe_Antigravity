# 37 — Event reminder card (Home "Your events")

Status: IMPLEMENTED LOCALLY (web + iOS), not committed. `vite build` + iOS simulator build clean; `tests/unit/eventReminder.test.mjs` green. NOT verified visually (no password for the test account; the halo has only been compiled, never watched).

- Rule (`src/lib/eventReminder.js`, iOS `Lib/EventReminder.swift`, keep in sync): ticket-holder's own event (confirmed booking, not a hold), not cancelled/ended, from 24h before `starts_at` until over. Events have NO end time, so "ongoing" is capped at 12h after the start.
- Card: tag "Sắp diễn ra / Starting soon" or "Đang diễn ra / Happening now" (gold `CHIP_COLORS.reminder`) replaces "Paid"; ★ on the chip; 2px gold border; halo pulses 3x then fades, border stays.
- "Replays on return": web Home remounts on navigation, so the CSS animation restarts naturally; iOS HomeView stays mounted, so `reminderHaloTrigger` is bumped on appear and when `app.screen` becomes `.home`. Reduce Motion = static border.
- Test data (production DB, account banbetestadmin@gmail.com, organizer org_a96236c5): events `reminder-test-soon` (starts ~5h after creation) and `reminder-test-live` (started 1h before creation), each with a confirmed booking (codes RMDSOON/RMDLIVE). Times are fixed at creation: "live" lapses 12h later, "soon" becomes "live" after ~5h. Re-seed or edit `starts_at` to retest. Cleanup: delete both events (+ their `event_photos`, `bookings`).
