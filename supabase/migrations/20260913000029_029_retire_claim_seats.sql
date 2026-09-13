-- Migration: retire claim_seats() as an independent code path, and backfill
-- every booking it stranded.
--
-- ---------------------------------------------------------------------------
-- THE BUG — not a display bug, a wrong RPC call that has been running since
-- migration 026 shipped
-- ---------------------------------------------------------------------------
-- Both clients' "Reserve" flow (src/state/GocContext.jsx's submitReserve,
-- AppState+Data.swift's submitReserve) call claim_seats() — the RPC from
-- migration 025, written before the two-phase payment_state machine (026)
-- existed. claim_seats() never touches payment_state, hold_expires_at or
-- payment_ref at all, so every booking it creates is left at the column
-- defaults: payment_state = 'holding' (its NOT NULL DEFAULT), hold_expires_at
-- = NULL. That is true even for a free event, an instantly-approved one, or
-- one an organizer has since marked paid (confirm_payment()/verify_payment()
-- change status/paid_marked_at, not payment_state).
--
-- The client-side effect: Confirmed.jsx/PaymentDetails.jsx (and their iOS
-- counterparts) derive `phase` from payment_state first, so every one of
-- these bookings reads as PHASE 1 "holding" forever; msUntil(null) floors at
-- 0, so the countdown shows a permanent 00:00 no matter how long ago the
-- booking was actually paid or attended. Migration 026's own backfill only
-- ran once, against whatever rows existed the moment it was applied — it
-- could not have caught a single booking claim_seats created afterward,
-- which is every booking since, because the client was never switched to
-- call hold_seats() instead. That switch is a client-side change (this
-- migration doesn't touch the client) — this migration is the database
-- side: stop new rows from being able to land in this state again, and
-- repair the ones already stuck.
--
-- ---------------------------------------------------------------------------
-- 1. Backfill every row this has already happened to. Same rule migration
--    026 used, just not restricted to `payment_ref IS NULL` — number of
--    stranded rows plausibly small, but even a live/paid one lacking a
--    payment_ref is exactly the pathology being repaired here, not a signal
--    to skip it.
-- ---------------------------------------------------------------------------
UPDATE public.bookings SET
  payment_state = CASE
    WHEN status = 'cancelled' THEN 'cancelled'::payment_state
    WHEN status = 'expired' THEN 'expired'::payment_state
    WHEN paid_marked_at IS NOT NULL THEN 'confirmed'::payment_state
    WHEN proof_uploaded_at IS NOT NULL THEN 'pending_verification'::payment_state
    WHEN status IN ('attended', 'no_show') THEN 'confirmed'::payment_state
    ELSE payment_state
  END,
  hold_expires_at = COALESCE(hold_expires_at, expires_at),
  verified_at = COALESCE(verified_at, paid_marked_at),
  verified_via = CASE WHEN paid_marked_at IS NOT NULL AND verified_via = ''
                      THEN 'organizer' ELSE verified_via END,
  payment_ref = COALESCE(payment_ref, 'ART' || lpad(nextval('payment_ref_seq')::text, 5, '0'))
WHERE payment_ref IS NULL
   OR (payment_state = 'holding' AND (paid_marked_at IS NOT NULL OR proof_uploaded_at IS NOT NULL
                                       OR status IN ('cancelled', 'expired', 'attended', 'no_show')));

-- ---------------------------------------------------------------------------
-- 2. claim_seats() itself becomes a thin wrapper around hold_seats(), rather
--    than a second, independently-maintained copy of the reservation logic
--    that can silently drift from it again — this exact drift (025 vs. 026)
--    is what caused the bug. Any caller still using the old name (there
--    shouldn't be one left after the client fix, but RPC names are public
--    API surface — a stale build, a cached bundle, an integration this repo
--    doesn't know about) gets the correct, up-to-date behavior instead of a
--    silently-broken one.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_seats(
  p_event text,
  p_qty int,
  p_note text DEFAULT NULL
)
RETURNS bookings
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.hold_seats(p_event, p_qty, p_note, NULL, NULL);
$$;
REVOKE EXECUTE ON FUNCTION public.claim_seats(text, int, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.claim_seats(text, int, text) TO authenticated;
