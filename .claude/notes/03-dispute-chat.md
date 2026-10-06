# Stage 5-6: "Not found" branch + temporary chat + resolution

## Files / functions
- `supabase/migrations/20260914000032_032_dispute_requires_explicit_escalation.sql:36` `reject_payment()` — "Payment not found", no longer touches `payment_state` (was auto-disputing pre-032)
- `supabase/migrations/20260913000026_026_payment_state_machine.sql:729` `reject_payment()` — OLD version (superseded by 032, kept for history)
- `supabase/migrations/20260914000033_033_dispute_thread_and_resolution.sql:84` `send_dispute_message()` — RPC, guest/organizer post to temp chat
- `supabase/migrations/20260914000033_033_dispute_thread_and_resolution.sql:129` `escalate_payment_dispute()` — **this is what actually opens `dispute_threads`**, not `reject_payment`
- `src/screens/Verifications.jsx:15` — "Can't find it" (calls `rejectPayment`) vs "Escalate to banbe" (calls `escalateDispute`), two distinct buttons
- `src/screens/DisputeChatPanel.jsx:12` `DisputeChatPanel()` — shared chat UI (web)
- `apps/ios/BanbeApp/Views/DisputeChatPanel.swift` `DisputeChatPanel` — same, iOS
- `src/state/BanBeContext.jsx:962` `escalateDispute()`; `apps/ios/BanbeApp/State/AppState+Payments.swift:621` `escalateDispute()`

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
did. `loadDisputeChat` (`src/state/BanBeContext.jsx:1049`) looks a thread up by
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
added to the `loadPaymentBookings` select (`BanBeContext.jsx:679-681`) and to
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
`loadDisputeChat` (`BanBeContext.jsx:1049`, `.maybeSingle()` on web,
`.single()`-throws on iOS) can't distinguish from a genuinely empty
conversation. `send_dispute_message()` (`033:84`) independently re-checks
`v_t.guest_id`/`organizer_id` against the same row and returns
`NOT_AUTHORIZED` for the same reason — previously swallowed by
`console.warn`/`print` only, no UI feedback, which is what made Send look
like it did nothing at all (network request DOES fire; the RPC responds
`{success:false, error:'NOT_AUTHORIZED'}`; nothing showed it).

The Send-button-disabled-looking-frozen report itself is not a separate
bug: `disputeChatDraft`/`onChange` (`DisputeChatPanel.jsx:63,` `disputeChat
DraftType` at `BanBeContext.jsx:1064`) were verified correct in isolation —
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
initial value `BanBeContext.jsx:130`; set in `loadDisputeChat`/
`sendDisputeMessage`, `BanBeContext.jsx:1049-1093`; rendered
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
buttons' code (`resolveDispute`, `BanBeContext.jsx`) was **not touched** by
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
(`BanBeContext.jsx:1068-1095`, `AppState+Payments.swift:769-`) to call it
once and retry the load automatically the moment a thread lookup comes back
empty — no manual admin action needed. `resolve_dispute()` itself
(`20260914000043_...sql`) also now re-links `guest_id`/`organizer_id` as
part of closing out a dispute, as a secondary safety net (moot for the
still-open case, but stops a resolved dispute from ever locking in a stale
link before the transcript email reads it).

**(2) Resolve buttons doing nothing, PRE-EXISTING, unrelated to (1)
(CONFIRMED):** `resolveDispute` (`BanBeContext.jsx`, and `AppState+Payments.
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
update the screen — `BanBeContext.jsx`'s `resolveDispute`/new
`sendDisputeResolvedEmail`, `AppState+Payments.swift`'s `resolveDispute`/new
`sendDisputeResolvedEmail`.

Applied to production via `supabase db push`. Web build + iOS `xcodebuild`
both green; 75/75 Playwright tests pass. Neither fix verified against the
live ART10025 row or a real resolve click (no production DB read access in
this session) — needs a real click-through to confirm.

## 2026-09-14 diagnosis #4 — ERROR 3: admin gets NOT_AUTHORIZED sending a dispute message (guest can send fine)

Root cause (CONFIRMED by code inspection): `send_dispute_message()`
(`20260914000033_033_...sql:107-113`) only ever checked `v_t.guest_id =
auth.uid()` or an organizer-ownership `EXISTS` — **no `public.is_platform_
admin()` branch at all**, unlike every sibling dispute RPC/policy
(`reject_payment`, `escalate_payment_dispute`, `resolve_dispute`,
`dispute_threads_select`, `dispute_messages_select`, all in 033/041/042/043)
which already have one. RLS lets an admin `SELECT` the same thread's
messages fine — this was the RPC's own internal check, not RLS, and it was
simply missing the admin case.

**Fixed**: `supabase/migrations/20260914000044_...sql` adds `ELSIF public.
is_platform_admin() THEN v_role := 'admin';` before the final `NOT_
AUTHORIZED` else-branch. `dispute_messages.sender_role` has no CHECK
constraint (comment-only: `'guest' | 'organizer' | 'system'`), so `'admin'`
needed no schema change. Client: `DisputeChatPanel.jsx`/`.swift`'s sender
label switch (previously organizer/guest/else-"System") now also renders
`'admin'` as "banbe" instead of falling through to "System".

Applied to production. See `04-admin-escalation.md` for ERRORS 1/2 (the
same live repro, on the resolve buttons) — all three fixed in the same
migration, `20260914000044_...sql`.

## 2026-10-04 — Closing a REFUND dispute, and downloading its transcript (migration 130)

**`supabase/migrations/20261110000130_130_refund_dispute_close_and_transcript.sql`
— WRITTEN AND LOCALLY VERIFIED, NOT YET APPLIED to any deployed database.**
(No `supabase` CLI or DB credentials in this environment, and migrations
require the user's own explicit approval gate before `supabase db push` —
same gate as `04-admin-escalation.md`'s migration 121.)

**The gap 129 left**: migration 129 gave a refund dispute a chat but only two
endings — the host re-sent the money (or the claim was confirmed/waived,
which stamped the 7-day clock lazily), or nothing happened and the chat stayed
open forever. Neither party could say "we're done arguing" without one of
them fabricating a transfer.

**The design constraint that shapes the whole migration**: closing must NOT
move the money. `refund_claims.status` is the field the entire refund state
machine is built on, and every financial RPC gates on it. Writing
`guest_confirmed` or `waived` on close would tell both apps the goer got
their money (or never was owed it) when nobody said so, and would block the
host from still sending it. So closure is its OWN additive fact:

- `refund_claims.dispute_closed_at` / `dispute_closed_by_role` — "closed by one
  of its two parties", **no financial meaning**. Claim stays exactly as it was.
- `dispute_threads.resolved_at` / `purge_after` / `resolution_kind` — the
  existing soft-delete pair 129 already stamps, which flips the chat
  read-only, starts the 7-day window, and lets the EXISTING
  `purge_resolved_dispute_threads()` cron (033) hard-delete the transcript for
  both parties. **The cron is untouched** — a refund transcript dies exactly the
  way a payment transcript always has, and the ordinary booking conversation is
  a different table and is never touched.

**RPCs added**: `close_refund_dispute(p_claim_id, p_note)` (either party, plus
admin; idempotent — a second call returns `already=true` without re-notifying
or re-stamping, so a double tap or a network retry can never move the purge
deadline; refuses with `ADMIN_RESOLUTION_REQUIRED` on any thread with a
`booking_id` or `kind <> 'refund'`), `get_refund_dispute_thread(p_claim_id)`
(the ONE verified per-claim read that replaced the client reading `viewer_role`
off whatever row happened to be in the polled list), and
`get_refund_dispute_for_conversation(p_thread)` /
`get_refund_dispute_transcript(p_claim_id)`. `get_my_dispute_chats()` is
redefined with four ADDITIONAL columns only.

**`dispute_threads.booking_id` is deliberately preserved** and still returns
`t.booking_id` (NULL for a refund dispute) because web
`src/screens/Inbox.jsx:134` passes `chat.booking_id` straight to
`DisputeChatPanel`; the new `source_booking_id` / `conversation_thread_id` are
additive and are what let a client find the EXISTING booking conversation
without creating a second one. Payment-dispute resolution is untouched —
`resolve_dispute` is not modified anywhere in this migration.

**iOS**: the refund dispute now renders INSIDE the existing booking
conversation's "Booking cancelled" system card (resolved on `threads`' own
UNIQUE `(event_id, guest_id)`), instead of the removed yellow Messages
accordion; `VerificationsView`'s inline copy of the payment dispute was
replaced with a jump into that same conversation; and a single open dispute
now deep-links straight from the Action Center instead of the queue in front
of it. Export is offered BEFORE closing, so nobody has to close a dispute to
keep a copy.

**2026-10-04 UPDATE — NOW EXECUTED AGAINST A REAL DATABASE.** See
`supabase/_localtest/` (harness, never deployed) and run it with
`./supabase/_localtest/run.sh`.

**A real bug this caught, which reading the SQL could not:** `CREATE OR REPLACE
FUNCTION` **cannot change a function's return type**, and `get_my_dispute_chats()`
is declared `RETURNS TABLE(...)`, so adding four columns to its OUT list failed
the whole migration with `cannot change return type of existing function`. It
needed `DROP FUNCTION IF EXISTS` + `CREATE FUNCTION`. Nothing depends on that
function (a leaf read path called only over PostgREST — web
`src/state/BanBeContext.jsx`, iOS `loadDisputeChats`; no view, trigger or other
function references it), so the drop is safe, and it all happens inside one
transaction. This would have failed `supabase db push` outright.

**Verified for real** (clean `supabase/postgres:17.6.1.166`, matching
production's PG 17.6):
- All **125 migrations apply cleanly from an empty schema**, in order, 001→130.
- **51/51 behavioural assertions pass.** Includes: the dispute resolves to the
  right conversation/booking/event for BOTH the goer and the host (A1–A6) and the
  same goer's *other* conversation on a different event finds **nothing** (A4);
  viewer roles per party with strangers refused (B); payment disputes refused
  with `ADMIN_RESOLUTION_REQUIRED` on both guard branches (D); **`refund_claims.
  status` unchanged at `disputed` after close — no money moved** (E5); idempotency
  does not move `purge_after`, re-notify, or overwrite the first closer (F);
  the closed dispute stays in the conversation then vanishes once `purge_after`
  passes (G); `booking_id` still NULL for refund disputes so the web Inbox is
  unaffected (H1); transcript labels resolve (I).
- iOS `xcodebuild` clean on **Debug and Release**; 24/24 unit tests pass.

**iOS card placement confirmed against the real message text**: the system card
for a body starting `"Booking cancelled."` maps to status `declined`
(`MessagingViews.swift:828-829`) and `attachedDispute(for:)` matches **only**
`declined`, so the dispute hangs off the "Booking cancelled" card and nothing
else. The active-dispute marking is wired on both surfaces — the Inbox row gets a
red "Dispute in progress" label + tint and the card gets the same label + alert
border, both keyed on an exact `conversationThreadId` match (never an event-name
match), and both disappear on close because `dispute_closed_at` now clears
`isActiveDispute`.

**STILL NOT verified**: never applied to any deployed database (still needs your
`supabase db push` approval), and no dispute has been closed, exported or purged
through the real iOS app with two live accounts — so the Swift UI wiring above is
verified by code path and DB contract, not by a device click-through. The web
client's Inbox was not re-run against the redefined `get_my_dispute_chats()`.

**A trap for whoever re-runs the harness**: seed the refund claim as
`host_marked_sent`, NOT `disputed` — `dispute_refund()` short-circuits with
`already=true` on an already-disputed claim and never creates the thread, so a
`disputed` seed silently tests nothing at all.

## 2026-10-05 — "Not found" now has a 2-day window (migration 149)

**`supabase/migrations/20261129000149_149_not_found_two_day_window.sql` — written, verified in `supabase/_localtest` (assertion `10_not_found_window_assert.sql`), NOT applied to any deployed DB.**

- `reject_payment()` stamps `bookings.not_found_at` (first report only — never extended by repeat reports or goer re-uploading proof) and `dispute_threads.expires_at = not_found_at + 2 days`.
- `expire_not_found_bookings()` (pg_cron every 5 min, `bb_expire_not_found_bookings`): for bookings still `pending_verification`/`holding` past the window → `payment_state/status = 'expired'` (seat back to inventory, same end state as hold expiry), thread soft-closed (`resolution_kind='cancelled'`, purged after 72h by the existing cron), system message in the permanent chat, notification to goer + host.
- "Settled" needs no extra code: host confirming → `confirmed`, escalating to banbe → `disputed`; the sweep only looks at the two pre-settlement states.
- **Surfacing (follow-up, same day):** user saw no chat/notification/red highlight. Causes: (1) migration 149 (and 129-148) not applied remotely, so nothing exists server-side yet; (2) iOS only attached a payment chat to the conversation once the booking was `disputed`, and `isActiveDispute` was refund-only. Fixed: `livePaymentDisputeBookingID` now also accepts `pending_verification`/`holding` with `not_found_at` set; new "Transfer not found" system card (iOS `MessagingViews`, web `Chat.jsx`) hosts the panel with red border; `DisputeChatSummary.isActiveDispute` true for open payment threads (red Inbox row); host now gets a notification on the first report; `get_my_dispute_chats()` gained `expires_at` + `booking_payment_state` (web Inbox shows "closes in ~Nh" + proper label). Web does not yet have the red Inbox row (uses the yellow dispute section). Unit tests 19/19, web build green; no device click-through.
- **Not done (old note):** iOS panel has no countdown line; web no countdown inside the chat panel itself; no countdown UI on web/iOS yet (`window_ends_at` is returned by `reject_payment` and put in the notification `data`, and `dispute_threads.expires_at` is readable under existing RLS). `resolution_kind='cancelled'` is reused rather than a new value because `dispute_resolution_stats` has a CHECK on it (and the sweep doesn't write stats).
