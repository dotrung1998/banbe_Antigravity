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

## 2026-09-17 — three fixes: stale countdown on back-navigation, generic hold-failure error, un-wired hold notifications

**Bug 1 — stale countdown after "Tôi đã chuyển khoản" + back-navigation**: `PaymentDetails.jsx`/`PaymentDetailsView` fetched `paymentBookings` once per appearance and never again while the screen stayed mounted — a real `payment_state` change while the guest stayed on the exact screen never re-rendered. `Confirmed.jsx`/`ConfirmedView.swift` already had a 6s poll for this identical reason (organizer confirms, webhook matches, etc. while the guest is looking). Fixed by adding the same poll here:
- `src/screens/PaymentDetails.jsx` — new `useEffect` (after the existing tick-only countdown effect) polling `bookings` every 6s while `!isConfirmed && !isExpired`, patching the matching entry in `state.paymentBookings` on a real phase change.
- `apps/ios/BanbeApp/Views/PaymentViews.swift` — new `pollTask`/`startPollingIfNeeded()` (mirrors `ConfirmedView.swift`'s own), wired via `.onAppear`/`.onChange(of: booking?.paymentState)`/`.onDisappear`.

**Bug 2a — generic hold-failure error hid the real reason**: `hold_seats()` (031:38) raises one of `NOT_AUTHENTICATED`/`INVALID_QTY`/`PROFILE_NOT_FOUND`/`EVENT_NOT_FOUND`/`EVENT_NOT_LIVE`/`SOLD_OUT` as a plain `RAISE EXCEPTION '<CODE>'` (no ERRCODE/DETAIL). Web's `submitReserve()` (`GocContext.jsx`, was :2048-2051) showed the raw untranslated code verbatim; iOS's (`AppState+Data.swift`, was :729-735) always showed one generic message regardless of which exception fired. Both now map every known code to an honest Vietnamese/English message (same pattern `submitPaymentProof`'s own error handling already used), falling back to the old generic message only for an unrecognized code.

**Bug 2b — a cancelled event still offered a live "Giữ chỗ" button**: `ev.cancelled`/`event.cancelled` already existed (used elsewhere on the same screen for the refund note) but the Reserve bar's own label/tap/style never checked it, so a cancelled event (e.g. "Bàn Dài №4" — confirmed cancelled, `seats_remaining=2`) fell through to the live default and only ever failed later via `hold_seats()`'s own `EVENT_NOT_LIVE` — surfacing through the ungracefully-handled error path fixed in 2a. Fixed in `src/screens/EventDetail.jsx` and `apps/ios/BanbeApp/Views/EventDetailView.swift`: a new `cancelled` branch (checked before `ended`/`soldOut`, since a cancelled event's stale `seats_remaining` can still read as either) shows a disabled "Sự kiện đã bị huỷ" state instead. Verified against the real "Bàn Dài №4" event via a throwaway Playwright script (not committed): the Event screen now renders "Sự kiện đã bị huỷ" with no "Giữ chỗ" text anywhere on the page.

**Bug 2c — data-hygiene gap, not fixed this pass**: "Bàn Dài №4" (`bandai`) has `status='cancelled'` but `seats_remaining=2` — a stale/cosmetic value, not kept in sync with cancellation (or with `booking_holds_seat()`'s own real hold count). Confirmed via the seed migration (`20260910000020_020_seed_demo_events_for_test_accounts.sql:51,78-89`: `capacity = seats_remaining = 2` regardless of `status`). Harmless now that 2b hides the Reserve bar entirely for a cancelled event regardless of `seats_remaining`'s value, but worth a real fix later (e.g. `cancel_event()` zeroing `seats_remaining`, or deriving "seats left" from `booking_holds_seat()` at read time instead of trusting the stored column) — flagging rather than fixing, per this ticket's own scope.

**Bug 3 — hold-related notifications weren't tappable**: `openNotification()` (web: `GocContext.jsx:2664-2693`; iOS: `AppState+Data.swift:530-572`) already handled `booking_requested` (→ `openAttendance(event_id)`, the organizer's check-in list — this was already wired, contrary to this ticket's initial premise; no change needed there) and `dispute_message`/`payment_confirmed`/etc., but had no branch at all for two other payment-lifecycle kinds:
- `hold_created` (guest, `hold_seats()` migration 053) — new branch routes to `openPaymentDetails(booking_id)`, the guest's own timer/QR/payment screen, mirroring how `dispute_message`'s guest branch already does the same.
- `payment_awaiting_verification` (organizer, `submit_payment_proof()` 031:317) — found while auditing for "any other payment-related notification kind that should return to the timer/payment screen" per this ticket's own instruction; was never wired at all despite existing since migration 026/031. New branch routes to `openVerifications()` (not `openAttendance()` — this is specifically the "guest reported paying, needs a decision" step, which lives in Verifications' "Money received"/"Can't find it" actions, not Attendance's check-in list).

`vite build` clean; iOS `xcodebuild` clean (Debug + Release); full fast Playwright suite passes (see session for exact count).
