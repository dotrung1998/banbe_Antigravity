-- Migration: banbe must never appear in the normal verification flow — only
-- when a host explicitly escalates a payment they truly can't resolve with
-- the guest directly.
--
-- ---------------------------------------------------------------------------
-- WHAT WAS WRONG
-- ---------------------------------------------------------------------------
-- reject_payment() (migration 026) set payment_state = 'disputed'
-- unconditionally, on every single "Payment not found" tap — there was no
-- separate escalation step at all; rejecting *was* disputing. That put
-- "banbe đang xem xét / banbe is reviewing this" in front of the guest (and
-- routed the booking into the admin-only v_disputes queue) for what is
-- routine back-and-forth — an organizer flagging that they can't find a
-- transfer yet, which the guest might resolve in one chat message (a typo'd
-- reference, a delayed bank feed). banbe is meant to be an intermediary, not
-- an automatic reviewer of every disagreement.
--
-- ---------------------------------------------------------------------------
-- THE FIX
-- ---------------------------------------------------------------------------
-- reject_payment() no longer touches payment_state at all — the booking
-- stays exactly where it was (normally 'pending_verification'), the reason
-- is still recorded (bookings.dispute_reason, the audit log, a chat system
-- message, and a notification) but framed as a request for more information,
-- not a verdict. The guest can resubmit proof (submit_payment_proof() already
-- supports this without resetting the SLA) and the organizer can approve
-- normally once resolved — banbe never enters the picture.
--
-- A new, separate escalate_payment_dispute() is the only thing that still
-- sets payment_state = 'disputed' — an explicit, deliberate action a host
-- takes only when they and the guest truly cannot agree, which is what
-- actually routes the booking into the admin-only v_disputes queue and
-- surfaces the "banbe is reviewing this" copy (still driven by
-- payment_state = 'disputed', unchanged client-side — see Confirmed.jsx /
-- PaymentDetails.jsx / ConfirmedView.swift / PaymentViews.swift).
CREATE OR REPLACE FUNCTION public.reject_payment(
  p_booking uuid, p_reason text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
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

  IF v_b.payment_state NOT IN ('pending_verification', 'holding') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_b.payment_state);
  END IF;

  -- payment_state is deliberately left untouched — this is feedback, not a
  -- verdict. dispute_reason still records the latest reason given (reused
  -- by escalate_payment_dispute() below, and read by Verifications.jsx to
  -- show what was last said), but disputed_at stays NULL until an explicit
  -- escalation actually happens.
  UPDATE bookings SET dispute_reason = v_reason WHERE id = p_booking;

  PERFORM log_payment_event(
    p_booking, 'T2_flagged_not_found', v_b.payment_state, v_b.payment_state,
    auth.uid(), 'organizer', NULL, NULL,
    jsonb_build_object('reason', v_reason, 'transaction_id', v_b.transaction_id,
                       'proof_path', v_b.proof_path, 'payment_ref', v_b.payment_ref)
  );

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Người tổ chức chưa tìm thấy khoản chuyển khoản này'
            || COALESCE(': ' || NULLIF(v_reason, ''), '')
            || '. Vui lòng kiểm tra lại thông tin chuyển khoản hoặc gửi thêm bằng chứng — chỗ của bạn vẫn được giữ.',
            'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_b.user_id, 'payment_needs_info', 'Cần thêm thông tin chuyển khoản',
          'Người tổ chức chưa tìm thấy khoản chuyển khoản của bạn. Chỗ vẫn được giữ — kiểm tra tin nhắn để biết chi tiết.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                             'reason', v_reason));

  RETURN jsonb_build_object('success', true, 'state', v_b.payment_state);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.reject_payment(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reject_payment(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- escalate_payment_dispute() — the one and only door into 'disputed' now.
-- Same shape reject_payment() used to be; a host reaches for this only once
-- they and the guest genuinely can't resolve it themselves.
-- ---------------------------------------------------------------------------
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
    -- Falls back to whatever reason a prior reject_payment() already left —
    -- an escalation doesn't have to repeat itself if nothing changed.
    dispute_reason = CASE WHEN v_reason <> '' THEN v_reason ELSE v_b.dispute_reason END,
    verify_due_at = NULL
  WHERE id = p_booking
  RETURNING * INTO v_b;

  PERFORM log_payment_event(
    p_booking, 'T3_disputed_escalated', v_from, 'disputed', auth.uid(), 'organizer', NULL, NULL,
    jsonb_build_object('reason', v_b.dispute_reason, 'transaction_id', v_b.transaction_id,
                       'proof_path', v_b.proof_path, 'payment_ref', v_b.payment_ref)
  );

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

  -- Surfaces on the organizer's public profile, same counter the overdue
  -- refund sweep uses.
  UPDATE organizers o SET disputes_open = COALESCE(o.disputes_open, 0) + 1
  FROM events e WHERE e.id = v_b.event_id AND o.id = e.organizer_id;

  RETURN jsonb_build_object('success', true, 'state', 'disputed');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.escalate_payment_dispute(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.escalate_payment_dispute(uuid, text) TO authenticated;
