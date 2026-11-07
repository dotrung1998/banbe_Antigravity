# Phase 2 — core loops L1–L4: implementation plan (2026-10-23)

One migration (199) for the server, then web + iOS. In-app first; push goes through the dormant 194 pipeline
(quiet hours, mutes, `push_enabled`); email is NOT built (the mail setup on Vercel is unverified, and reminders are
not worth a daily cron). Policy text gated per switch; B12 limits in `docs/policy-retention-draft.md`.

## L1 Event reminders — switch `event_reminders` (ON: transactional, in-app)
- pg_cron every 10 min: for each ticket holder (booking `status = confirmed` or a free claim) of a live event, insert
  `event_reminder_day` when the start is 23–25 h away and `event_reminder_soon` when 2.5–3.5 h away. One of each per
  booking (`event_reminder_log`), never for a cancelled event or booking, never when the kind is muted.
- Text names the event and the start time IN THE EVENT'S ZONE; English via 142 rules. Data: event_id, booking_id.

## L2 Guest recap + private feedback — switch `event_recap` (OFF: new data, B12)
- When an event becomes `ended` (cron 167), ticket holders get one `event_recap` notification: "<event> has ended"
  with a link to the recap card (photos, follow host, next from this host, 👍/👎 + optional note).
- `event_feedback` (one row per guest per event, editable 14 days, owner-only via RPC). The host sees aggregates only
  when 3 or more guests answered (`get_event_feedback_summary`): counts up/down and notes without names, shuffled.

## L3 Host recap + "Run it again" — switch `host_recap` (OFF)
- `follows.created_at` (existing rows stay NULL = unknown, so they never count as "new").
- On `ended`: the host gets `host_event_recap`. `get_host_event_recap(event)` (owner/team only): confirmed seats,
  check-ins, new followers since submission, repeat guests (count), feedback summary (≥3), photo count.
- "Run it again": the client copies the event into Create Event (date moved one week, never past), using note 48's
  smart defaults; nothing is created until the host submits.

## L4 Follow-host alerts — switch `follow_alerts` (OFF)
- When an event becomes live + public, each follower of its organizer gets a queue row; an hourly job sends at most
  ONE `follow_alert` per person per 24 h, bundling everything queued ("New from hosts you follow"), only between
  09:00 and 20:00 in the person's market zone, never for events already started, never when muted.

Tests: SQL suite 26 (+ shared vectors `tests/fixtures/core-loops.json`), web unit, iOS unit.
