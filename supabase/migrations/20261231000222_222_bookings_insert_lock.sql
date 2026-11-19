-- 222 — bookings are created only by the booking RPCs, never by a client INSERT.
--
-- Audit 2026-11-19 row 1 (P0). `bookings_insert_guest` (002:113-114) let any signed-in caller INSERT a booking
-- row over PostgREST with their own user_id and an arbitrary body: status='confirmed', payment_state='confirmed',
-- total_vnd=0, any qty, any event_id. That bypassed hold_seats (capacity, invite-only, criteria, per-person cap),
-- payment confirmation and the door's payment check, and the row then read as a paid ticket (QR, check-in, rewards).
-- 132/133 revoked UPDATE on bookings but not INSERT, and no client writes bookings directly: every creation path is
-- a SECURITY DEFINER function (hold_seats / hold_seats_with_attendees / claim_seats in 219), which keeps its own
-- privileges after this revoke. service_role (api/*, cron, webhooks) is unaffected.
BEGIN;

DROP POLICY IF EXISTS "bookings_insert_guest" ON public.bookings;
REVOKE INSERT ON public.bookings FROM authenticated, anon;

COMMIT;

-- Verification (after `supabase db push`, as a signed-in user through PostgREST):
--   POST /rest/v1/bookings {event_id, user_id:<self>, qty:1}  -> 403 "permission denied for table bookings"
--   RPC hold_seats('event', 1)                               -> still succeeds
