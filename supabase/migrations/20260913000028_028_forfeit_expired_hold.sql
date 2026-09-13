-- Migration: fix a genuinely broken hold-expiry path, then give a client a
-- way to forfeit its OWN expired hold instantly.
--
-- ---------------------------------------------------------------------------
-- THE ROOT CAUSE — not a display lag, a permanently stuck booking
-- ---------------------------------------------------------------------------
-- validate_booking_status_transition() (migration 004, last touched by
-- migration 022) only allows:
--   pending  -> confirmed, expired, cancelled
--   confirmed -> attended, no_show, cancelled
--   attended -> confirmed
--
-- hold_seats() (migration 026) sets status = 'confirmed' immediately for
-- every 'instant'-approval event — which is every seeded demo event — even
-- while payment_state sits at 'holding' and nothing has been paid yet. When
-- expire_stale_holds()'s minutely sweep then tries `UPDATE bookings SET
-- status = 'expired' ...` on one of those rows, this trigger raises "Invalid
-- booking status transition from confirmed to expired" — and since the
-- sweep's loop has no exception handling, that single row aborts the entire
-- function call, rolling back every row it had already expired earlier in
-- the same run. The row that failed reappears in next minute's WHERE
-- clause and fails again. Forever. A held seat on an instant-approval event
-- was therefore never actually expiring server-side at all — not delayed by
-- up to a minute, permanently stuck at "holding" — which is exactly what
-- made a lapsed countdown keep showing "Going" with no Reserve button: nothing
-- ever flipped the row that every one of those screens reads.
--
-- Fixed at the source: 'confirmed' can transition to 'expired' too — an
-- instant-approval booking that time out before payment is exactly as valid
-- a case as a host_approves one.

CREATE OR REPLACE FUNCTION validate_booking_status_transition()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  IF (OLD.status = 'pending' AND NEW.status IN ('confirmed', 'expired', 'cancelled')) OR
     (OLD.status = 'confirmed' AND NEW.status IN ('attended', 'no_show', 'cancelled', 'expired')) OR
     (OLD.status = 'attended' AND NEW.status = 'confirmed') THEN
    RETURN NEW;
  ELSE
    RAISE EXCEPTION 'Invalid booking status transition from % to %', OLD.status, NEW.status;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- Defense in depth: even with the trigger fixed, one bad row should never
-- again be able to silently wedge every other row's expiry in the same
-- sweep. Each row's update now stands on its own.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_stale_holds()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row record;
  v_count int := 0;
BEGIN
  FOR v_row IN
    SELECT id, user_id, event_id, payment_ref
    FROM bookings
    WHERE payment_state = 'holding'
      AND hold_expires_at IS NOT NULL
      AND hold_expires_at < now()
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      UPDATE bookings SET payment_state = 'expired', status = 'expired'
      WHERE id = v_row.id;

      PERFORM log_payment_event(v_row.id, 'hold_expired', 'holding', 'expired',
                                NULL, 'system', NULL, NULL,
                                jsonb_build_object('payment_ref', v_row.payment_ref));

      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (v_row.user_id, 'hold_expired', 'Hết thời gian giữ chỗ',
              'Chỗ của bạn đã được mở lại vì chưa nhận được xác nhận chuyển khoản.',
              jsonb_build_object('booking_id', v_row.id, 'event_id', v_row.event_id));

      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      -- Whatever went wrong with this one row, the rest of the sweep must
      -- still run — that guarantee is the entire point of this block, and
      -- is what the previous version of this function didn't have.
      RAISE WARNING 'expire_stale_holds: booking % failed to expire: %', v_row.id, SQLERRM;
    END;
  END LOOP;
  RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- forfeit_my_expired_hold() — lets the client that is actually watching a
-- countdown flip its own booking the instant it hits zero, instead of
-- waiting up to a minute for the sweep above to get to it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.forfeit_my_expired_hold(p_booking uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  IF v_b.user_id <> auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- Idempotent: the client may call this more than once (Home's banner and
  -- the ticket screen can both notice the same expiry within the same
  -- second), and the sweep above may have already gotten to it first.
  -- Either way, report the current state rather than erroring on a booking
  -- that is already exactly where the caller wanted it.
  IF v_b.payment_state <> 'holding' THEN
    RETURN jsonb_build_object('success', true, 'state', v_b.payment_state, 'noop', true);
  END IF;

  -- The one thing this must never do: expire a hold whose deadline the
  -- CLIENT merely thinks has passed (clock skew, a stale cached booking, a
  -- buyer's system clock set wrong). Trust only the server's own clock
  -- against the server's own deadline — never the caller's claim.
  IF v_b.hold_expires_at IS NULL OR v_b.hold_expires_at > now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'HOLD_STILL_ACTIVE', 'state', v_b.payment_state);
  END IF;

  UPDATE bookings SET payment_state = 'expired', status = 'expired' WHERE id = p_booking;

  PERFORM log_payment_event(p_booking, 'hold_expired_by_client', 'holding', 'expired',
                            auth.uid(), 'buyer', NULL, NULL, '{}'::jsonb);

  RETURN jsonb_build_object('success', true, 'state', 'expired');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.forfeit_my_expired_hold(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.forfeit_my_expired_hold(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Backfill: every instant-approval booking that has been silently wedged at
-- status='confirmed'/payment_state='holding' since migration 026 shipped,
-- past its own deadline, gets swept once here rather than waiting for
-- whoever next opens that ticket screen.
-- ---------------------------------------------------------------------------
SELECT public.expire_stale_holds();
