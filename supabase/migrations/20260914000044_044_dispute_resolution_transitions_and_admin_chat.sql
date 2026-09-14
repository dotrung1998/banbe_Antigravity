-- Migration: three exact, narrow gaps found via live reproduction on
-- ART10025 ("Vườn Sau") — not a state-machine redesign, just the specific
-- transitions/authorization this dispute's actual history needs.
--
-- ---------------------------------------------------------------------------
-- ERROR 1/2 — resolve_dispute() failing with P0001 "Invalid booking status
-- transition from cancelled to confirmed/expired"
-- ---------------------------------------------------------------------------
-- validate_booking_status_transition() (migration 004, last redefined by
-- 028) allows:
--   pending   -> confirmed, expired, cancelled
--   confirmed -> attended, no_show, cancelled, expired
--   attended  -> confirmed
-- No entry starts from 'cancelled' at all — any transition OUT of
-- 'cancelled' is rejected, by design (a cancelled booking is meant to be
-- terminal).
--
-- ART10025's `bookings.status` is 'cancelled' because `cancel_booking()`
-- (migration 022, apps/BOTH the guest, the organizer, or an admin can call
-- it) has no awareness of `payment_state` at all — it only refuses when
-- `status` is already 'cancelled'/'expired'/'attended'. Nothing stops it
-- from cancelling a booking that is mid-dispute (`payment_state =
-- 'disputed'`), which is what must have happened here: `status` moved to
-- 'cancelled' while `payment_state` stayed 'disputed', an unanticipated
-- combination — `status` and `payment_state` are meant to be independent
-- axes (see 026's own header comment on that split), and this is the one
-- corner where a cancel can land `status` somewhere `resolve_dispute()`'s
-- two outcomes can't legally leave it.
--
-- `status` has no 'disputed' value of its own (booking_status enum:
-- pending/confirmed/cancelled/expired/no_show/attended — `payment_state` is
-- the only column with 'disputed') and adding one is a real state-machine
-- change, which this fix deliberately avoids. Minimal fix instead: allow
-- 'cancelled' as a source for exactly the two transitions resolve_dispute()
-- needs — a disputed booking a guest or organizer cancelled out from under
-- the dispute must still be resolvable either way once banbe rules on it.
CREATE OR REPLACE FUNCTION validate_booking_status_transition()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  IF (OLD.status = 'pending' AND NEW.status IN ('confirmed', 'expired', 'cancelled')) OR
     (OLD.status = 'confirmed' AND NEW.status IN ('attended', 'no_show', 'cancelled', 'expired')) OR
     (OLD.status = 'attended' AND NEW.status = 'confirmed') OR
     (OLD.status = 'cancelled' AND NEW.status IN ('confirmed', 'expired')) THEN
    RETURN NEW;
  ELSE
    RAISE EXCEPTION 'Invalid booking status transition from % to %', OLD.status, NEW.status;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- ERROR 3 — sendDisputeMessage: guest and organizer can post, admin gets
-- NOT_AUTHORIZED
-- ---------------------------------------------------------------------------
-- send_dispute_message()'s authorization check (033:107-113) only ever
-- checked `v_t.guest_id = auth.uid()` or an organizer-ownership EXISTS —
-- no `public.is_platform_admin()` branch at all, unlike every sibling
-- dispute RPC/RLS policy (reject_payment, escalate_payment_dispute,
-- resolve_dispute, dispute_threads_select, dispute_messages_select all
-- already have one). An admin can already SELECT this same thread's
-- messages (RLS allows it) but could never INSERT one — this RPC's own
-- internal check, not RLS, was the gap.
CREATE OR REPLACE FUNCTION public.send_dispute_message(p_booking uuid, p_body text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t dispute_threads%ROWTYPE;
  v_body text := left(trim(COALESCE(p_body, '')), 2000);
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF v_body = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMPTY_MESSAGE');
  END IF;

  SELECT * INTO v_t FROM dispute_threads WHERE booking_id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_DISPUTED');
  END IF;
  IF v_t.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'DISPUTE_RESOLVED');
  END IF;

  IF v_t.guest_id = auth.uid() THEN
    v_role := 'guest';
  ELSIF EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_t.organizer_id
                AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    v_role := 'organizer';
  ELSIF public.is_platform_admin() THEN
    v_role := 'admin';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  INSERT INTO dispute_messages (dispute_thread_id, sender_id, sender_role, body)
  VALUES (v_t.id, auth.uid(), v_role, v_body);

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.send_dispute_message(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_dispute_message(uuid, text) TO authenticated;
