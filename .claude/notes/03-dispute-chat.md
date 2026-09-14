# Stage 5-6: "Not found" branch + temporary chat + resolution

## Files / functions
- `supabase/migrations/20260914000032_032_dispute_requires_explicit_escalation.sql:36` `reject_payment()` — "Payment not found", no longer touches `payment_state` (was auto-disputing pre-032)
- `supabase/migrations/20260913000026_026_payment_state_machine.sql:729` `reject_payment()` — OLD version (superseded by 032, kept for history)
- `supabase/migrations/20260914000033_033_dispute_thread_and_resolution.sql:84` `send_dispute_message()` — RPC, guest/organizer post to temp chat
- `supabase/migrations/20260914000033_033_dispute_thread_and_resolution.sql:129` `escalate_payment_dispute()` — **this is what actually opens `dispute_threads`**, not `reject_payment`
- `src/screens/Verifications.jsx:15` — "Can't find it" (calls `rejectPayment`) vs "Escalate to banbe" (calls `escalateDispute`), two distinct buttons
- `src/screens/DisputeChatPanel.jsx:12` `DisputeChatPanel()` — shared chat UI (web)
- `apps/ios/BanbeApp/Views/DisputeChatPanel.swift` `DisputeChatPanel` — same, iOS
- `src/state/GocContext.jsx:962` `escalateDispute()`; `apps/ios/BanbeApp/State/AppState+Payments.swift:621` `escalateDispute()`

## DB tables/columns
- `public.dispute_threads` (id, booking_id UNIQUE, event_id, guest_id, organizer_id, resolved_at, resolution_kind, resolution_note, email_sent_at, purge_after)
- `public.dispute_messages` (id, dispute_thread_id, sender_id, sender_role, body, created_at)
- `public.bookings.dispute_reason`, `.disputed_at` (set only on escalate, not on plain reject)
- `public.threads`/`public.messages` — the PERMANENT ordinary chat (reject_payment posts its reason here as a system message, not into dispute_messages)

## Status: WORKING, with a naming/architecture mismatch vs this ticket's grouping
"Not found" (reject) and "temporary chat" are NOT the same stage in code: reject_payment (stage 5) only messages the guest in the PERMANENT ordinary thread; the temporary `dispute_threads`/`dispute_messages` chat this ticket calls stage 5-6 is only created by `escalate_payment_dispute` (this ticket's stage 7). There is no temp chat available during a plain "not found" rejection before escalation.

## TODO / open questions
- No test coverage for `send_dispute_message` RLS/state-guard (DISPUTE_RESOLVED / NOT_DISPUTED error paths) on either platform.

## 2026-09-14 diagnosis — reported bug: chat not opening / not delivering live

Root cause A (session/linkage, CONFIRMED): `reject_payment()` (032:36) never
inserted into `dispute_threads` — only `escalate_payment_dispute()` (033:129)
did. `loadDisputeChat` (`src/state/GocContext.jsx:1049`) looks a thread up by
`booking_id`, finds none for a plain "not found," and silently resolves to an
empty chat — reads exactly like "not delivering" when there was no session to
link to. Compounded by UI gating: `PaymentDetails.jsx:150` only rendered
`<DisputeChatPanel>` when `isDisputed` (payment_state='disputed'), never for
plain `pending_verification` + a reason — same gap in `Verifications.jsx`'s
`myOpenDisputes` (sourced from `v_disputes`, `WHERE payment_state='disputed'`).
**Fixed**: `supabase/migrations/20260914000041_041_dispute_chat_on_reject.sql`
— `reject_payment()` now also opens the `dispute_threads` row (`ON CONFLICT
(booking_id) DO NOTHING`), without touching `payment_state`/`disputed_at`;
`v_pending_verifications` now exposes `dispute_reason`. Client: `dispute_reason`
added to the `loadPaymentBookings` select (`GocContext.jsx:679-681`) and to
`PayableBookingRow`/`PayableBooking` (`AppState+Payments.swift:351-403`,
`PaymentDocument.swift:107-136`); new gated blocks render `<DisputeChatPanel>`
for `pending_verification` + `dispute_reason` in `PaymentDetails.jsx:150-165`
and `PaymentViews.swift` (`needsInfoCard`, ~L240); `Verifications.jsx:114-123`
and `VerificationsView.swift` (`row.disputeReason` block) add an inline
"Open chat" entry per queue row (not just the escalated list).

Root cause B (no realtime delivery, CONFIRMED): zero `supabase.channel(`/
`postgres_changes` usage anywhere in this repo (`src/`, `apps/ios/BanbeApp/`,
`supabase/migrations/` — grepped, no hits), and `dispute_messages` was never
added to the `supabase_realtime` publication. `DisputeChatPanel.jsx`/`.swift`
only fetched once on mount + after the local sender's own message — the other
party never saw new messages without leaving/reopening. **Fixed**: added a 4s
poll (`setInterval`/`Task` loop) in both `src/screens/DisputeChatPanel.jsx`
(useEffect) and `apps/ios/BanbeApp/Views/DisputeChatPanel.swift`
(`startPolling()`/`onAppear`/`onDisappear`) — matches this codebase's existing
6s poll pattern in `PaymentDetails.jsx` rather than introducing Realtime
channels nothing else here uses.

Applied to production via `supabase db push`. Web build + iOS
`xcodebuild` both green; 75/75 existing Playwright tests still pass (no new
automated test added for the chat linkage/poll fix itself).
