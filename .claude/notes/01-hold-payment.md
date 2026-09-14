# Stage 1-2: Hold slot (30min) + payment window (30min)

## Files / functions
- `supabase/migrations/20260913000026_026_payment_state_machine.sql:282` `hold_seats()` — RPC, PHASE 1 entry
- `supabase/migrations/20260914000031_031_fix_hold_and_sla_durations.sql:38` `hold_seats()` — redefine, hold_minutes default 60→30
- `supabase/migrations/20260913000026_026_payment_state_machine.sql:112` `booking_holds_seat()` — live seat-availability predicate
- `src/state/GocContext.jsx:1558` `submitReserve()` — calls `hold_seats` RPC (web)
- `apps/ios/BanbeApp/State/AppState+Data.swift:512` `submitReserve()` — calls `hold_seats` RPC (iOS)
- `src/screens/Reserve.jsx:5,24` `Reserve()`, `reserveBtnLabel` — "Giữ chỗ ▪︎ 30 phút"
- `apps/ios/BanbeApp/Views/ReserveView.swift:83` — same label, iOS
- `src/lib/countdown.js`, `apps/ios/BanbeApp/Lib/Countdown.swift` — countdown render helpers

## DB tables/columns
- `public.events.hold_minutes` (int, default 30)
- `public.bookings.payment_state` ('holding' | ...), `.hold_expires_at`, `.expires_at` (legacy mirror), `.payment_ref`

## Status: WORKING
`hold_minutes` default reverted 60→30 in migration 031; `hold_seats()` fallback and Reserve button copy match. Verified via source-text test `tests/payment-state-machine.spec.js:88`.

## TODO / open questions
- No per-event organizer UI to customize `hold_minutes` — always the 30min default. Confirm this is intentional (not a gap).
- "Payment window" is the same 30min hold countdown, not a separate window — confirm this matches product intent, or if a distinct post-hold payment window was meant.
