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

## 2026-09-14 diagnosis #2 — reported bug: ART10025 ("Vườn Sau") chat frozen, Send does nothing

Repro: `dotrung1998@gmail.com` (organizer) on Verifications.jsx
(`data-testid="verification-open-not-found-chat"` row), "No messages yet."
never resolves, Send button never visually enables, screen otherwise
unresponsive.

Root cause (CONFIRMED by code inspection, not a live DB query — production
reads are blocked in this session): `INSERT INTO dispute_threads (...) ON
CONFLICT (booking_id) DO NOTHING` in both `reject_payment()` (`041:70-72`, now
`042`) and `escalate_payment_dispute()` (`033:184-186`, now `042`) means a
booking whose `dispute_threads` row was ever created with the wrong
`organizer_id`/`guest_id` (a stale row from before 041 existed, or any
`events.organizer_id` that was ever NULL/different at INSERT time — that
column is nullable) can never be repaired by a later call. `dispute_threads_
select`/`dispute_messages_select` RLS (`033:57-73`) then silently returns
ZERO rows to the real organizer — not an error, just nothing — which
`loadDisputeChat` (`GocContext.jsx:1049`, `.maybeSingle()` on web,
`.single()`-throws on iOS) can't distinguish from a genuinely empty
conversation. `send_dispute_message()` (`033:84`) independently re-checks
`v_t.guest_id`/`organizer_id` against the same row and returns
`NOT_AUTHORIZED` for the same reason — previously swallowed by
`console.warn`/`print` only, no UI feedback, which is what made Send look
like it did nothing at all (network request DOES fire; the RPC responds
`{success:false, error:'NOT_AUTHORIZED'}`; nothing showed it).

The Send-button-disabled-looking-frozen report itself is not a separate
bug: `disputeChatDraft`/`onChange` (`DisputeChatPanel.jsx:63,` `disputeChat
DraftType` at `GocContext.jsx:1064`) were verified correct in isolation —
typing does update state and the button's enabled style does key off
`s.disputeChatDraft.trim()`. The perceived "stays disabled" is this same
silent-failure symptom described imprecisely: every send attempt fails
`NOT_AUTHORIZED` with no visible change, reading as "nothing happens."

**Fixed**: `supabase/migrations/20260914000042_042_dispute_thread_self_heal_and_errors.sql`
— `ON CONFLICT (booking_id) DO UPDATE SET guest_id/organizer_id = EXCLUDED.*
WHERE resolved_at IS NULL` in both functions, so a stale row self-heals the
next time either runs on that booking. For ART10025 specifically: the
organizer re-tapping "Can't find it" now re-links the existing row — no
manual data fix was made (no DB write access to target that one row
directly in this session). Client: added `disputeChatError` (state +
initial value `GocContext.jsx:130`; set in `loadDisputeChat`/
`sendDisputeMessage`, `GocContext.jsx:1049-1093`; rendered
`DisputeChatPanel.jsx:44,74-78`; same on iOS — `AppState.swift:258`,
`AppState+Payments.swift:742-793`, `DisputeChatPanel.swift`) so a real
RLS/RPC denial now shows an actual error message instead of an
indistinguishable "No messages yet."; a failed send also restores the
typed draft instead of silently discarding it.

Applied to production via `supabase db push`. Web build + iOS `xcodebuild`
both green; 75/75 Playwright tests pass. Not verified against the live
ART10025 row itself (no production DB read access in this session) — needs
a real click-through by the organizer to confirm the self-heal actually
fires for that specific booking.

**⚠️ Last fix (042) caused a chat-load regression — see diagnosis #3 below
before reapplying anything similar.** The self-heal in 042 could never
actually fire for a booking already in `payment_state = 'disputed'`
(ART10025's exact state on the admin's Disputes.jsx screen), since the only
two functions it patched (`reject_payment`/`escalate_payment_dispute`) both
refuse to run once a booking is disputed. The error banner it added was
correct and working as designed — but with no way for the UI to actually
repair the row, "silent freeze" became "error banner that never clears."

## 2026-09-14 diagnosis #3 — regression: chat now errors instead of freezing silently; admin's resolve buttons still do nothing

`git diff HEAD~1` (commit `40a4361`, the 042 fix) confirmed the resolve
buttons' code (`resolveDispute`, `GocContext.jsx`) was **not touched** by
that commit — its "still does nothing" is a separate, pre-existing bug, not
caused by 042. Two distinct root causes, not one shared one:

**(1) Chat error banner, unfixable by 042 (CONFIRMED):** 042's `ON CONFLICT
... DO UPDATE` self-heal lives in `reject_payment()`/`escalate_payment_
dispute()`, both gated `IF v_from NOT IN ('pending_verification', 'holding')
THEN RETURN INVALID_STATE`. A booking on the admin's Disputes.jsx screen is
by definition `payment_state = 'disputed'` — neither function is reachable,
so the self-heal was structurally dead code for exactly this case. Fixed:
`supabase/migrations/20260914000043_...sql` adds `resync_dispute_thread(p_
booking)` — a new RPC with NO `payment_state` restriction at all (guest,
event organizer, or admin), purely re-linking `dispute_threads.guest_id`/
`organizer_id`. Wired into `loadDisputeChat` on both platforms
(`GocContext.jsx:1068-1095`, `AppState+Payments.swift:769-`) to call it
once and retry the load automatically the moment a thread lookup comes back
empty — no manual admin action needed. `resolve_dispute()` itself
(`20260914000043_...sql`) also now re-links `guest_id`/`organizer_id` as
part of closing out a dispute, as a secondary safety net (moot for the
still-open case, but stops a resolved dispute from ever locking in a stale
link before the transcript email reads it).

**(2) Resolve buttons doing nothing, PRE-EXISTING, unrelated to (1)
(CONFIRMED):** `resolveDispute` (`GocContext.jsx`, and `AppState+Payments.
swift`'s counterpart) `await`ed the `api/dispute-resolved-email.js` fetch
call **inside the same try block as, and before,** `disputeBusy` being
cleared and `loadDisputes()`/`loadAdminDisputes()` refreshing the list. That
endpoint runs `puppeteer-core` + `@sparticuz/chromium` inside a Vercel
function and has never been load-tested end-to-end (see
`05-notify-retention.md`) — a slow cold start or a hang there silently
blocked every visible sign that `resolve_dispute()` (the DB RPC) had
already succeeded, which reads exactly like "the button does nothing" even
though the dispute really was resolved server-side. Fixed: the email send
is now fire-and-forget, called only *after* `disputeBusy`/`loadDisputes()`
update the screen — `GocContext.jsx`'s `resolveDispute`/new
`sendDisputeResolvedEmail`, `AppState+Payments.swift`'s `resolveDispute`/new
`sendDisputeResolvedEmail`.

Applied to production via `supabase db push`. Web build + iOS `xcodebuild`
both green; 75/75 Playwright tests pass. Neither fix verified against the
live ART10025 row or a real resolve click (no production DB read access in
this session) — needs a real click-through to confirm.
