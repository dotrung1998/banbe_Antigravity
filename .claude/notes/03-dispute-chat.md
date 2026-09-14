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
- Confirm intended stage boundary: should `reject_payment` also open a `dispute_threads` row immediately (so guest/host can chat before formal escalation), or is escalation-gated chat correct as-is?
- No test coverage for `send_dispute_message` RLS/state-guard (DISPUTE_RESOLVED / NOT_DISPUTED error paths) on either platform.
