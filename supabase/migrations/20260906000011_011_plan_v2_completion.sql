-- Migration: Plan v2 Completion (confirm_payment, cancel_booking, cancel_event, v_host_ledger, system message receipt trail)

-- 1. confirm_payment(p_booking uuid, p_method text)
CREATE OR REPLACE FUNCTION confirm_payment(p_booking uuid, p_method text DEFAULT 'momo')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_is_authorized boolean;
  v_thread_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT b.* INTO v_booking FROM bookings b WHERE b.id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_booking.event_id
      AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) INTO v_is_authorized;

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_booking.status <> 'pending' AND v_booking.status <> 'confirmed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_PENDING');
  END IF;

  UPDATE bookings
  SET status = 'confirmed',
      paid_marked_at = now(),
      paid_method = p_method,
      paid_marked_by = auth.uid(),
      confirmed_at = now()
  WHERE id = p_booking;

  -- Ensure chat thread exists and post system message as receipt
  SELECT id INTO v_thread_id
  FROM threads
  WHERE event_id = v_booking.event_id AND guest_id = v_booking.user_id;

  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(), 'Host marked payment received via ' || COALESCE(p_method, 'direct transfer') || '.', 'system');
  END IF;

  RETURN jsonb_build_object('success', true, 'booking_id', p_booking);
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_payment(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION confirm_payment(uuid, text) TO authenticated;

-- 2. cancel_booking(p_booking uuid, p_reason text)
CREATE OR REPLACE FUNCTION cancel_booking(p_booking uuid, p_reason text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_is_authorized boolean;
  v_thread_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT b.* INTO v_booking FROM bookings b WHERE b.id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

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

  UPDATE bookings
  SET status = 'cancelled',
      cancelled_at = now(),
      cancelled_by = auth.uid(),
      cancel_reason = COALESCE(p_reason, '')
  WHERE id = p_booking;

  IF v_booking.status = 'confirmed' OR v_booking.paid_marked_at IS NOT NULL THEN
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

  RETURN jsonb_build_object('success', true, 'booking_id', p_booking);
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_booking(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION cancel_booking(uuid, text) TO authenticated;

-- 3. cancel_event(p_event text, p_reason text)
CREATE OR REPLACE FUNCTION cancel_event(p_event text, p_reason text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev events%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_thread_id uuid;
  v_count int := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_ev FROM events WHERE id = p_event OR slug = p_event OR key = p_event;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM organizers o WHERE o.id = v_ev.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) AND NOT EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  UPDATE events
  SET status = 'cancelled',
      cancelled_at = now(),
      cancel_reason = COALESCE(p_reason, '')
  WHERE id = v_ev.id;

  FOR v_booking IN SELECT * FROM bookings WHERE event_id = v_ev.id AND status IN ('pending', 'confirmed') LOOP
    UPDATE bookings
    SET status = 'cancelled',
        cancelled_at = now(),
        cancelled_by = auth.uid(),
        cancel_reason = COALESCE(p_reason, '')
    WHERE id = v_booking.id;

    IF v_booking.status = 'confirmed' OR v_booking.paid_marked_at IS NOT NULL THEN
      INSERT INTO refund_claims (booking_id, reservation_id, amount_vnd, reason, status)
      VALUES (v_booking.id, v_booking.id, v_booking.total_vnd, 'host_cancelled', 'owed');
    END IF;

    SELECT id INTO v_thread_id FROM threads WHERE event_id = v_ev.id AND guest_id = v_booking.user_id;
    IF v_thread_id IS NOT NULL THEN
      INSERT INTO messages (thread_id, sender_id, body, kind)
      VALUES (v_thread_id, auth.uid(), 'Event was cancelled by host. Reason: ' || COALESCE(NULLIF(p_reason, ''), 'Cancelled by organizer') || '.', 'system');
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'event_id', v_ev.id, 'bookings_cancelled', v_count);
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_event(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION cancel_event(text, text) TO authenticated;

-- 4. v_host_ledger View
CREATE OR REPLACE VIEW v_host_ledger AS
SELECT
  e.id AS event_id,
  e.organizer_id,
  e.name AS event_name,
  COALESCE(SUM(CASE WHEN b.status IN ('confirmed', 'attended') THEN b.qty ELSE 0 END), 0) AS seats_sold,
  COALESCE(SUM(CASE WHEN b.status = 'pending' AND (b.expires_at IS NULL OR b.expires_at > now()) THEN b.qty ELSE 0 END), 0) AS unpaid_pendings,
  COALESCE(SUM(CASE WHEN rc.status = 'owed' THEN rc.amount_vnd ELSE 0 END), 0) AS refunds_owed
FROM events e
LEFT JOIN bookings b ON b.event_id = e.id
LEFT JOIN refund_claims rc ON (rc.booking_id = b.id OR rc.reservation_id = b.id)
GROUP BY e.id, e.organizer_id, e.name;
