-- Migration: a dispute_threads row that was ever created with the wrong
-- organizer_id/guest_id could never be corrected — ON CONFLICT (booking_id)
-- DO NOTHING (migrations 033, 041) means a repeat call from
-- reject_payment()/escalate_payment_dispute() on the same booking leaves a
-- pre-existing row exactly as it was. If that row's organizer_id doesn't
-- match the real organizer (a stale row from before either function existed
-- in its current form, or from an events.organizer_id that was ever NULL/
-- different at INSERT time), the dispute_threads_select/dispute_messages_select
-- RLS policies (033) silently return zero rows to that organizer — not an
-- error, just nothing — which is indistinguishable, client-side, from an
-- empty conversation. send_dispute_message() then also legitimately
-- returns NOT_AUTHORIZED against that same row, which the client only
-- console.warn'd (see GocContext.jsx's loadDisputeChat/sendDisputeMessage,
-- fixed alongside this migration to surface disputeChatError instead).
--
-- This is very likely the exact failure on booking ART10025 ("Vườn Sau"):
-- "No messages yet." never resolving, and sending silently doing nothing,
-- both match a dispute_threads row RLS is quietly hiding from the real
-- organizer rather than a chat that is merely empty.
--
-- Fix: ON CONFLICT (booking_id) DO UPDATE re-links organizer_id/guest_id to
-- whatever they actually are right now, every time either function runs —
-- self-healing a stale row instead of leaving it stuck. For ART10025
-- specifically: the organizer re-tapping "Can't find it" (reject_payment)
-- once this migration is applied re-links the existing row and unblocks it
-- immediately — no manual data fix needed.

CREATE OR REPLACE FUNCTION public.reject_payment(
  p_booking uuid, p_reason text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_authorized boolean;
  v_thread_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_b.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) INTO v_authorized;
  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_b.payment_state NOT IN ('pending_verification', 'holding') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_b.payment_state);
  END IF;

  UPDATE bookings SET dispute_reason = left(trim(COALESCE(p_reason, '')), 400) WHERE id = p_booking
  RETURNING * INTO v_b;

  PERFORM log_payment_event(
    p_booking, 'T2_flagged_not_found', v_b.payment_state, v_b.payment_state,
    auth.uid(), 'organizer', NULL, NULL,
    jsonb_build_object('reason', v_b.dispute_reason, 'transaction_id', v_b.transaction_id,
                       'proof_path', v_b.proof_path, 'payment_ref', v_b.payment_ref)
  );

  INSERT INTO dispute_threads (booking_id, event_id, guest_id, organizer_id)
  VALUES (v_b.id, v_b.event_id, v_b.user_id, (SELECT organizer_id FROM events WHERE id = v_b.event_id))
  ON CONFLICT (booking_id) DO UPDATE SET
    guest_id = EXCLUDED.guest_id,
    organizer_id = EXCLUDED.organizer_id
  WHERE dispute_threads.resolved_at IS NULL;

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Người tổ chức chưa tìm thấy khoản chuyển khoản này'
            || COALESCE(': ' || NULLIF(v_b.dispute_reason, ''), '')
            || '. Vui lòng kiểm tra lại thông tin chuyển khoản hoặc gửi thêm bằng chứng — chỗ của bạn vẫn được giữ.',
            'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_b.user_id, 'payment_needs_info', 'Cần thêm thông tin chuyển khoản',
          'Người tổ chức chưa tìm thấy khoản chuyển khoản của bạn. Chỗ vẫn được giữ — kiểm tra tin nhắn để biết chi tiết.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                             'reason', v_b.dispute_reason));

  RETURN jsonb_build_object('success', true, 'state', v_b.payment_state);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.reject_payment(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reject_payment(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.escalate_payment_dispute(
  p_booking uuid, p_reason text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_from payment_state;
  v_authorized boolean;
  v_thread_id uuid;
  v_reason text := left(trim(COALESCE(p_reason, '')), 400);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_b.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) INTO v_authorized;
  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  v_from := v_b.payment_state;
  IF v_from NOT IN ('pending_verification', 'holding') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_from);
  END IF;

  UPDATE bookings SET
    payment_state = 'disputed',
    disputed_at = now(),
    dispute_reason = CASE WHEN v_reason <> '' THEN v_reason ELSE v_b.dispute_reason END,
    verify_due_at = NULL
  WHERE id = p_booking
  RETURNING * INTO v_b;

  PERFORM log_payment_event(
    p_booking, 'T3_disputed_escalated', v_from, 'disputed', auth.uid(), 'organizer', NULL, NULL,
    jsonb_build_object('reason', v_b.dispute_reason, 'transaction_id', v_b.transaction_id,
                       'proof_path', v_b.proof_path, 'payment_ref', v_b.payment_ref)
  );

  INSERT INTO dispute_threads (booking_id, event_id, guest_id, organizer_id)
  VALUES (v_b.id, v_b.event_id, v_b.user_id, (SELECT organizer_id FROM events WHERE id = v_b.event_id))
  ON CONFLICT (booking_id) DO UPDATE SET
    guest_id = EXCLUDED.guest_id,
    organizer_id = EXCLUDED.organizer_id
  WHERE dispute_threads.resolved_at IS NULL;

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Người tổ chức và bạn chưa thống nhất được về khoản chuyển khoản này, nên đã chuyển cho banbe xem xét. Chỗ của bạn vẫn được giữ trong lúc chờ.',
            'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_b.user_id, 'payment_disputed', 'Thanh toán đang được xem xét',
          'banbe đang xem xét khoản thanh toán của bạn. Chỗ vẫn được giữ trong lúc chờ.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                             'reason', v_b.dispute_reason));

  UPDATE organizers o SET disputes_open = COALESCE(o.disputes_open, 0) + 1
  FROM events e WHERE e.id = v_b.event_id AND o.id = e.organizer_id;

  RETURN jsonb_build_object('success', true, 'state', 'disputed');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.escalate_payment_dispute(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.escalate_payment_dispute(uuid, text) TO authenticated;
