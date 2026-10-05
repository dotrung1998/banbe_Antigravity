-- Migration: cancel_event() never told anyone, and never gave its refunds a
-- deadline (refund_due_at stayed NULL, so neither the goer's screen nor the
-- host's overdue tracking had a date — cancel_booking() has set it to 3
-- business days since 072). Both fixed below, plus a backfill of existing
-- event-cancel claims that have no deadline.
--
-- Original note: cancel_event() never told anyone. It cancelled every booking,
-- opened the refund claims and posted a line in each conversation, but wrote
-- no notification, so the goer got no bell badge and no push. (cancel_booking()
-- has notified since 069; the whole-event path was missed.)
--
-- Body is migration 011's, plus one notification per cancelled booking. Same
-- kind and wording as cancel_booking()'s so the existing localisation patterns
-- (142) and client handling apply unchanged. Unlike cancel_booking(), it is
-- sent even when the holder is the canceller (a host who also holds a ticket
-- should still see their own ticket was cancelled with the event).

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
  v_had_payment boolean;
  v_clean_reason text := left(trim(COALESCE(p_reason, '')), 400);
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

    v_had_payment := v_booking.status = 'confirmed' OR v_booking.paid_marked_at IS NOT NULL;
    IF v_had_payment THEN
      INSERT INTO refund_claims (booking_id, reservation_id, amount_vnd, reason, status, refund_due_at)
      VALUES (v_booking.id, v_booking.id, v_booking.total_vnd, 'host_cancelled', 'owed',
              goc_add_business_days(now(), 3));
    END IF;

    SELECT id INTO v_thread_id FROM threads WHERE event_id = v_ev.id AND guest_id = v_booking.user_id;
    IF v_thread_id IS NOT NULL THEN
      INSERT INTO messages (thread_id, sender_id, body, kind)
      VALUES (v_thread_id, auth.uid(), 'Event was cancelled by host. Reason: ' || COALESCE(NULLIF(p_reason, ''), 'Cancelled by organizer') || '.', 'system');
    END IF;

    IF v_booking.user_id IS NOT NULL THEN
      INSERT INTO public.notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_booking.user_id,
        'booking_cancelled',
        'Vé của bạn đã bị huỷ',
        COALESCE(v_ev.name, 'Sự kiện') || ' đã huỷ vé của bạn.'
          || (CASE WHEN v_had_payment THEN ' Khoản bạn đã thanh toán sẽ được hoàn lại.' ELSE '' END)
          || (CASE WHEN v_clean_reason <> '' THEN ' Lý do: ' || v_clean_reason ELSE '' END),
        jsonb_build_object('event_id', v_ev.id, 'booking_id', v_booking.id, 'reason', v_clean_reason, 'had_payment', v_had_payment)
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'event_id', v_ev.id, 'bookings_cancelled', v_count);
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_event(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION cancel_event(text, text) TO authenticated;

-- Backfill: open claims from event cancellations that never got a deadline.
-- Counted from when the claim was created, not from now, so an old claim
-- correctly shows as overdue instead of being granted fresh time.
UPDATE refund_claims
SET refund_due_at = goc_add_business_days(created_at, 3)
WHERE refund_due_at IS NULL AND status = 'owed';
