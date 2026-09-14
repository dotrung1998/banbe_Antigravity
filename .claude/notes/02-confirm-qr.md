# Stage 3-4: Organizer confirm (1h SLA) / auto-confirm + QR issuance

## Files / functions
- `supabase/migrations/20260913000026_026_payment_state_machine.sql:459` `submit_payment_proof()` — sets `verify_due_at = now()+p_sla_minutes`
- `supabase/migrations/20260914000031_031_fix_hold_and_sla_durations.sql:195` `submit_payment_proof()` — redefine, SLA default 15→60min
- `supabase/migrations/20260913000026_026_payment_state_machine.sql:608` `verify_payment()` — RPC, manual organizer/admin confirm → `payment_state='confirmed'`
- `supabase/migrations/20260913000027_027_organizer_alert_routing.sql:92` `verify_payment_from_bot()` — Telegram-bot confirm path (alt entry to verify_payment)
- `supabase/migrations/20260913000026_026_payment_state_machine.sql:939` `sweep_verification_slas()` — cron, reminds/escalates overdue, **does NOT auto-confirm**
- `api/cron/escalate-verifications.js` — drains `alert_outbox`, sends Telegram alerts only
- `src/state/GocContext.jsx:918` `approvePayment()` / `apps/ios/BanbeApp/State/AppState+Payments.swift:584` `approvePayment()`
- `src/screens/Verifications.jsx:15` — organizer queue UI ("Money received" button)
- `src/screens/Confirmed.jsx:200,216` `QrCode()` — QR render via `qrcode` lib, value = `booking.id`

## DB tables/columns
- `public.bookings.verify_due_at`, `.verified_at`, `.verified_via`, `.verified_by`, `.payment_state`
- `public.alert_outbox`, `public.v_alert_queue` (Telegram reminder/escalation queue)

## Status: PARTIALLY WORKING
Manual confirm (organizer tap, bot tap) and QR issuance: WORKING. **Auto-confirm after 1h SLA elapses is NOT IMPLEMENTED** — `sweep_verification_slas()` only sends Telegram reminder (T+SLA) and urgent escalation (T+2×SLA) to the organizer; nothing ever calls `verify_payment` automatically.

## TODO / open questions
- Confirm whether "auto-confirm" was ever meant to exist, or if the ticket's stage description is aspirational — if real, needs a new sweep step calling `verify_payment(p_actor_kind='system')` past some deadline.
- `verify_payment_from_bot` vs `verify_payment` — two RPCs doing the same state transition from different entry points; not unified, not obviously a bug.
