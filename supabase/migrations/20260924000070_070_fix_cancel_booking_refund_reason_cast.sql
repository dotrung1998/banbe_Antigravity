-- Migration: fix cancel_booking() refund_claims.reason enum/text mismatch.
--
-- CONFIRMED ROOT CAUSE (real iPhone error): "column "reason" is of type
-- refund_reason but expression is of type text". cancel_booking()
-- (migration 069) inserts into refund_claims.reason using:
--   CASE WHEN v_host_initiated THEN 'host_cancelled' ELSE 'guest_cancelled' END
-- Unlike a bare string-literal VALUES entry (which Postgres treats as
-- "unknown" type and freely assignment-casts to the target enum column —
-- see the untouched cancel_event()/undo_checkin() definitions in migrations
-- 011/022, which still use exactly that pattern and were never affected),
-- a CASE expression over two literal branches resolves to a concrete `text`
-- type, and Postgres does not implicitly cast `text` to `refund_reason` on
-- INSERT — only an explicit cast does. Every host cancellation of a
-- paid/confirmed booking hit this and failed outright; the friendly UI
-- error added in a447c33 was correctly surfacing the failure, but the SQL
-- itself was still broken.
--
-- Fix: explicit `::refund_reason` cast on each CASE branch. Same signature,
-- same authorization/status logic, same notification/thread behavior as
-- migration 069 — only the enum typing changes. This is a NEW forward
-- migration (069 stays as committed) per this ticket's own instruction not
-- to edit an already-applied migration in place.
--
-- Audited every other refund_claims.reason write in migration 069
-- (mark_refund_sent/confirm_refund_received/dispute_refund) — none of them
-- write `reason` at all (status-only updates), so no other instance of this
-- mismatch exists there.
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
  v_host_initiated boolean;
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

  v_had_payment := v_booking.status = 'confirmed' OR v_booking.paid_marked_at IS NOT NULL;
  v_host_initiated := v_booking.user_id IS DISTINCT FROM auth.uid();

  UPDATE bookings
  SET status = 'cancelled',
      cancelled_at = now(),
      cancelled_by = auth.uid(),
      cancel_reason = COALESCE(p_reason, '')
  WHERE id = p_booking;

  IF v_had_payment THEN
    INSERT INTO refund_claims (booking_id, reservation_id, amount_vnd, reason, status)
    VALUES (
      v_booking.id, v_booking.id, v_booking.total_vnd,
      -- The actual fix: explicit cast on each branch. Without it, this
      -- CASE expression resolves to `text`, not the "unknown" type a bare
      -- literal gets, and Postgres refuses to implicitly assign it to the
      -- `refund_reason` enum column.
      CASE WHEN v_host_initiated THEN 'host_cancelled'::refund_reason ELSE 'guest_cancelled'::refund_reason END,
      'owed'
    );
  END IF;

  SELECT id INTO v_thread_id
  FROM threads
  WHERE event_id = v_booking.event_id AND guest_id = v_booking.user_id;

  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(), 'Booking cancelled. Reason: ' || COALESCE(NULLIF(p_reason, ''), 'No reason provided') || '.', 'system');
  END IF;

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
