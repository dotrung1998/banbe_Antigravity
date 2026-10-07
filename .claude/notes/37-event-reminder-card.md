# 37 — Event reminder card (Home "Your events")

Status: IMPLEMENTED LOCALLY (web + iOS), not committed. `vite build` + iOS simulator build clean; `tests/unit/eventReminder.test.mjs` green. NOT verified visually (no password for the test account; the halo has only been compiled, never watched).

- Rule (`src/lib/eventReminder.js`, iOS `Lib/EventReminder.swift`, keep in sync): ticket-holder's own event (confirmed booking, not a hold), not cancelled/ended, from 24h before `starts_at` until over. Events have NO end time, so "ongoing" is capped at 12h after the start.
- Card: tag "Sắp diễn ra / Starting soon" or "Đang diễn ra / Happening now" (gold `CHIP_COLORS.reminder`) replaces "Paid"; ★ on the chip; 2px gold border; halo pulses 3x then fades, border stays.
- "Replays on return": web Home remounts on navigation, so the CSS animation restarts naturally; iOS HomeView stays mounted, so `reminderHaloTrigger` is bumped on appear and when `app.screen` becomes `.home`. Reduce Motion = static border.
- Test data (production DB, account banbetestadmin@gmail.com, organizer org_a96236c5): events `reminder-test-soon` (starts ~5h after creation) and `reminder-test-live` (started 1h before creation), each with a confirmed booking (codes RMDSOON/RMDLIVE). Times are fixed at creation: "live" lapses 12h later, "soon" becomes "live" after ~5h. Re-seed or edit `starts_at` to retest. Cleanup: delete both events (+ their `event_photos`, `bookings`).

## Follow-up: reminder events first + host announcements (migration 166)
- Strip order: reminder events lead "Your events" ("live" before "soon"), stable otherwise (web `reminderRank` sort in Home.jsx; iOS `sortedSavedStrip`).
- Backend: `supabase/migrations/20261213000166_166_event_announcements.sql` — NOT APPLIED. Adds `messages.announcement_category`, `event_announcements` log, `send_event_announcement(p_event, p_category, p_body, p_template_id)` (host/admin only; window = 24h before start .. 12h after; max 10/event/hour; one chat message per confirmed ticket-holder, creating the thread if needed) and re-defines `notify_new_message()` so announcements notify with kind `event_announcement` (title "Thông báo từ host"), not `new_message`. Needs `supabase db push`.
- Catalogue: `src/lib/eventAnnouncements.js` (5 categories, 23 bilingual templates, accent-insensitive search); iOS copy is GENERATED: `node scripts/gen-announcement-templates-ios.mjs` after editing.
- Host UI: red "Announce to guests" card on the Attendance screen (only inside the window) -> `AnnouncementSheet.jsx` / `EventAnnouncementSheet.swift`: message box, 3 quick picks, search, category chips, template list, two-step confirm. Message goes out in the host's app language (one string; no per-guest localisation).
- Red styling: announcement chat bubble (label + red border/tint), red banner under the chat header for 12h after an announcement, red-accent notification row and toast. Not changed: Inbox list rows.
- Not verified: nothing run against a database with 166; no visual check on either platform; tapping the notification opens the thread (same as new_message).

## Follow-up: host Dashboard
- Upcoming events list uses the same reminder treatment as Home (gold border + halo on the thumbnail, ★ + "Starting soon / Happening now" tag, reminder events first, filled Check-in button). Shared web CSS/rank live in `src/lib/eventReminder.js` (`REMINDER_CSS`, `reminderRank`); iOS reuses `EventReminderHalo`.
- Web bug fixed along the way: real (host-created) events were never listed on the web Dashboard (only the static catalogue was), so they had no Check-in button. They are now added from `realEventsById` (live/ended only). iOS already listed them.
- "Team" moved to the very bottom of the Dashboard and is collapsed by default (toggle shows the member count). State is per visit, not remembered.

## Follow-up 2: collapsibles, Account host card, back target
- Dashboard "Submitted events" and "Past events" are collapsed by default (count shown in the header), like Team. NOTE: collapsed by default means a "Needs fixing" submission is hidden until expanded; the header count still includes it.
- Account host card (first block in the Host tab): when any of the host's open events is within 24h of starting or in progress (`reminderPhase`), it gets the gold border + halo (replays whenever Account becomes visible), a "Check-in" label left of the ›, and a full-strength ›. Web computes it in Account.jsx (loads live events + real events for the host's keys); iOS `AppState.hostReminderPhase`.
- Dashboard Back always returns to Account when opened from Account: the Account Action Center entry now passes `profile`/`.profile` (it passed nothing, so Back went to a stale target such as Home). Opening the Dashboard from Home's "Your host page" or a notification still returns to where it came from.
