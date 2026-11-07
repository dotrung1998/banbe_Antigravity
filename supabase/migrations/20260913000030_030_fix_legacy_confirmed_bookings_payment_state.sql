-- Migration: repair the bookings 029's own backfill couldn't reach.
--
-- ---------------------------------------------------------------------------
-- WHY 029's backfill missed these rows
-- ---------------------------------------------------------------------------
-- 029 only moved a row off payment_state = 'holding' when it already had
-- clear evidence of that: paid_marked_at set, proof_uploaded_at set, or a
-- terminal status (cancelled/expired/attended/no_show). That correctly left
-- alone a *current*, hold_seats()-created instant-approval booking that
-- really is still unpaid — status = 'confirmed' with payment_state =
-- 'holding' is the intended, momentary state there, on its way to becoming
-- 'confirmed' once paid or 'expired' if the hold lapses.
--
-- But it also left alone every row where status = 'confirmed' with NO
-- paid_marked_at at all — which describes two kinds of legacy bookings:
--   1. Every one of migration 020's seeded demo bookings: a raw
--      `INSERT INTO bookings (event_id, user_id, qty, total_vnd, code,
--      status) VALUES (..., 'confirmed')` — no payment_state, no
--      paid_marked_at, no hold_expires_at, nothing. These represent an
--      already-attending participant in the demo data, not someone
--      mid-payment.
--   2. Any older booking claim_seats() created for a host_approves event
--      that an organizer later approved by hand (status -> 'confirmed')
--      without ever running it through a payment-confirmation RPC that
--      touches payment_state.
--
-- The reliable signal that distinguishes these from a genuine, currently
-- in-flight hold is hold_expires_at: hold_seats() always sets a real
-- hold_expires_at for a non-free 'holding' booking (only a FREE booking
-- skips straight to payment_state = 'confirmed', never sitting at
-- 'holding' with a null deadline in the first place). So payment_state =
-- 'holding' with hold_expires_at IS NULL alongside a 'confirmed' or
-- 'attended' status can only be one of these legacy rows — never a
-- currently-valid unpaid hold — and is safe to repair unconditionally.
UPDATE public.bookings
SET
  payment_state = 'confirmed',
  paid_marked_at = COALESCE(paid_marked_at, confirmed_at, created_at, now()),
  verified_at = COALESCE(verified_at, paid_marked_at, confirmed_at, created_at, now()),
  verified_via = CASE WHEN verified_via = '' THEN 'legacy_backfill' ELSE verified_via END
WHERE payment_state = 'holding'
  AND hold_expires_at IS NULL
  AND status IN ('confirmed', 'attended', 'no_show');
