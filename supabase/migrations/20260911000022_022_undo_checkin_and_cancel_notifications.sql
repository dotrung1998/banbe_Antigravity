-- Migration: let an organizer reverse a mistaken check-in (with a required
-- reason, notified both in-app and by email), and notify a guest when their
-- booking is cancelled — including after payment was already collected.
--
-- undo_check_in() is new. cancel_booking() already existed (migration 011)
-- with full authorization, refund-claim, and system-chat-message handling,
-- but predates the notifications table and was never actually wired to any
-- screen — this only adds the in-app notification, in the same transaction
-- as the status change, on top of its existing behavior.
--
-- Email delivery for both is handled outside the database by
-- api/notify-checkin-undo.js and api/notify-booking-cancelled.js, which
-- re-derive their recipient from the database using the caller's verified
-- session rather than trusting the client — the same pattern as the other
-- notification endpoints.

-- validate_booking_status_transition() (migration 004) only allowed
-- pending->{confirmed,expired,cancelled} and confirmed->{attended,no_show,
-- cancelled} — there was no way back from 'attended', so undo_check_in()'s
-- own UPDATE below would be rejected by this same trigger it has to go
-- through. Add exactly the one transition it needs.
CREATE OR REPLACE FUNCTION validate_booking_status_transition()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  IF (OLD.status = 'pending' AND NEW.status IN ('confirmed', 'expired', 'cancelled')) OR
     (OLD.status = 'confirmed' AND NEW.status IN ('attended', 'no_show', 'cancelled')) OR
     (OLD.status = 'attended' AND NEW.status = 'confirmed') THEN
    RETURN NEW;
  ELSE
    RAISE EXCEPTION 'Invalid booking status transition from % to %', OLD.status, NEW.status;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.undo_check_in(p_booking_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_host boolean;
  v_is_admin boolean;
  v_reason text := trim(p_reason);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF v_reason = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'REASON_REQUIRED');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
  END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  SELECT EXISTS(
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_booking.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) INTO v_is_host;
  SELECT EXISTS(SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin') INTO v_is_admin;

  IF NOT v_is_host AND NOT v_is_admin THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;

  IF v_booking.status <> 'attended' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking is not currently checked in');
  END IF;

  -- Delete rather than flag, so the guest can be legitimately checked in
  -- again later if they do show up — check_in_guest()'s own
  -- ON CONFLICT (booking_id) DO NOTHING would otherwise silently refuse.
  DELETE FROM check_ins WHERE booking_id = v_booking.id;
  UPDATE bookings SET status = 'confirmed' WHERE id = v_booking.id;

  IF v_booking.user_id IS NOT NULL THEN
    UPDATE profiles SET attended_count = GREATEST(COALESCE(attended_count, 0) - 1, 0) WHERE id = v_booking.user_id;

    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_booking.user_id,
      'checkin_undone',
      'Điểm danh của bạn đã được huỷ',
      COALESCE(v_event.name, 'Sự kiện') || ' vừa huỷ điểm danh của bạn. Lý do: ' || v_reason,
      jsonb_build_object('event_id', v_booking.event_id, 'booking_id', v_booking.id, 'reason', v_reason)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'booking_id', v_booking.id);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.undo_check_in(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.undo_check_in(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION cancel_booking(p_booking uuid, p_reason text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_authorized boolean;
  v_thread_id uuid;
  v_had_payment boolean;
  v_clean_reason text := trim(p_reason);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT b.* INTO v_booking FROM bookings b WHERE b.id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  v_is_authorized := (v_booking.user_id = auth.uid()) OR EXISTS(
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_booking.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  );

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_booking.status IN ('cancelled', 'expired', 'attended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_CANNOT_BE_CANCELLED');
  END IF;

  -- Captured from the pre-update snapshot: a booking already marked
  -- 'confirmed', or one a host had separately marked paid, had payment
  -- collected — the refund claim and the guest's notification both need to
  -- say so.
  v_had_payment := v_booking.status = 'confirmed' OR v_booking.paid_marked_at IS NOT NULL;

  UPDATE bookings
  SET status = 'cancelled',
      cancelled_at = now(),
      cancelled_by = auth.uid(),
      cancel_reason = COALESCE(p_reason, '')
  WHERE id = p_booking;

  IF v_had_payment THEN
    INSERT INTO refund_claims (booking_id, reservation_id, amount_vnd, reason, status)
    VALUES (v_booking.id, v_booking.id, v_booking.total_vnd, 'guest_cancelled', 'owed');
  END IF;

  SELECT id INTO v_thread_id
  FROM threads
  WHERE event_id = v_booking.event_id AND guest_id = v_booking.user_id;

  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(), 'Booking cancelled. Reason: ' || COALESCE(NULLIF(p_reason, ''), 'No reason provided') || '.', 'system');
  END IF;

  -- Notify the guest, unless they're the one who just cancelled it themselves.
  IF v_booking.user_id IS NOT NULL AND v_booking.user_id <> auth.uid() THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_booking.user_id,
      'booking_cancelled',
      'Vé của bạn đã bị huỷ',
      COALESCE(v_event.name, 'Sự kiện') || ' đã huỷ vé của bạn.'
        || (CASE WHEN v_had_payment THEN ' Khoản bạn đã thanh toán sẽ được hoàn lại.' ELSE '' END)
        || (CASE WHEN v_clean_reason <> '' THEN ' Lý do: ' || v_clean_reason ELSE '' END),
      jsonb_build_object('event_id', v_booking.event_id, 'booking_id', v_booking.id, 'reason', v_clean_reason, 'had_payment', v_had_payment)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'booking_id', p_booking);
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_booking(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION cancel_booking(uuid, text) TO authenticated;
