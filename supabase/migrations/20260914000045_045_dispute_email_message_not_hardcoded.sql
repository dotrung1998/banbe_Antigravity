-- Migration: the "Confirmation email sent to both parties" system message
-- was a promise, not a report — resolve_dispute() (a synchronous DB
-- transaction) inserted it unconditionally, entirely before the actual
-- email send even begins (that's a separate, client-triggered HTTP call to
-- api/dispute-resolved-email.js, deliberately decoupled from this RPC since
-- migration 043). The DB function has no way to know whether that later
-- call ever succeeds — it cannot await it, and was never meant to.
--
-- Fixed here: this message no longer claims the email was sent. The real
-- claim is now made by api/dispute-resolved-email.js itself, once it has
-- actually verified delivery — see that file's own changes for the honest,
-- outcome-reflecting message it posts instead.
CREATE OR REPLACE FUNCTION public.resolve_dispute(
  p_booking uuid, p_uphold boolean, p_resolution text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_note text := left(trim(COALESCE(p_resolution, '')), 400);
  v_result jsonb;
  v_thread_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADMIN_ONLY');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  IF v_b.payment_state <> 'disputed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_DISPUTED', 'state', v_b.payment_state);
  END IF;

  UPDATE bookings SET dispute_resolved_at = now(), dispute_resolution = v_note
  WHERE id = p_booking;

  IF p_uphold THEN
    v_result := verify_payment(p_booking, 'admin', 'admin',
                               jsonb_build_object('dispute_resolution', v_note));
  ELSE
    UPDATE bookings SET
      payment_state = 'expired', status = 'expired', verify_due_at = NULL
    WHERE id = p_booking;
    PERFORM log_payment_event(p_booking, 'dispute_resolved_against_buyer',
                              'disputed', 'expired', auth.uid(), 'admin', NULL, NULL,
                              jsonb_build_object('resolution', v_note));
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (v_b.user_id, 'dispute_resolved', 'Kết quả xem xét thanh toán',
            'banbe đã xem xét và không xác nhận được khoản thanh toán này. Chỗ đã được mở lại.',
            jsonb_build_object('booking_id', p_booking, 'resolution', v_note));
    v_result := jsonb_build_object('success', true, 'state', 'expired');
  END IF;

  UPDATE organizers o SET disputes_open = GREATEST(COALESCE(o.disputes_open, 1) - 1, 0)
  FROM events e WHERE e.id = v_b.event_id AND o.id = e.organizer_id;

  UPDATE dispute_threads SET
    guest_id = v_b.user_id,
    organizer_id = (SELECT organizer_id FROM events WHERE id = v_b.event_id),
    resolved_at = now(),
    resolution_kind = CASE WHEN p_uphold THEN 'ticket_issued' ELSE 'cancelled' END,
    resolution_note = v_note,
    purge_after = now() + interval '72 hours'
  WHERE booking_id = p_booking;

  -- No longer claims the email was sent — this transaction has no idea
  -- whether it will be. api/dispute-resolved-email.js posts the actual
  -- delivery confirmation (or failure) as its own follow-up message once
  -- it knows the real outcome.
  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, NULL,
            'Tranh chấp đã được giải quyết.'
            || ' / Dispute resolved.',
            'system');
  END IF;

  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.resolve_dispute(uuid, boolean, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_dispute(uuid, boolean, text) TO authenticated;
