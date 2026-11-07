# L9 — Rewards switch-on: preparation only (the switches are NOT changed by this run)

Current production values (2026-10-23): `rewards = false`, `rewards_v2 = false`. Server is ready (migrations 165,
177–180, 191–193 applied; note 58). Policy text for Rewards is already written and gated (note 59).

## Before turning `rewards` on (Vietnam first)
1. Lawyer (TODO(lawyer), `docs/policy-rewards-draft.md`): coins redeemable only for digital keychains, no cash value,
   no purchase → confirm this is not a "commercial promotion" needing notification under Decree 81/2018 as amended by
   128/2024 and 239/2026; confirm the Terms A9 wording; CCPA notice for US users before a US launch.
2. Measurement in place: F1 `app_events` on (needs the B12 re-consent decision first) or, at least, the server-side
   signals in `admin_retention_report()` (bookings, check-ins), so the before/after is visible.
3. L1 reminders live (they are: switch `event_reminders` on) and L2 recap decided — Rewards should reward attending,
   and attending needs host check-ins, which production does not have yet (0 check-ins on 2026-10-22).
4. Hosts actually check guests in (coins come only from host-confirmed check-ins): brief hosts first.
5. Admin › Feature switches → Rewards & badges → on. Everything appears without a release; the Terms show A9.

## Then `rewards_v2` (4+ weeks later)
- Same screen → Rewards v2. Weekly streak stays quiet: no streak notifications, no loss copy (guide tests enforce).

## Watch (guardrails)
- `reward_ledger` reversal and `off_window` / `attendance_cap` rows stay rare; any manual edit of the ledger is
  forbidden (append-only, reversal entries only).
- Second attendance within 60 days per market (`admin_retention_report`), compared with the weeks before.
