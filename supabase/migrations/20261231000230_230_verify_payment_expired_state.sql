-- 230 (audit 2026-11-19 row 10): verify_payment listed 'expired' among the payment states it may confirm, but an
-- expired hold cannot be confirmed: validate_booking_status_transition (028, last widened by 044) lets 'expired' start no
-- transition, so the function's own UPDATE raised 'Invalid booking status transition from expired to confirmed' and the
-- caller got a raw Postgres exception (SQLSTATE P0001) instead of the function's INVALID_STATE answer. Nothing was
-- written — the whole call rolled back — but the branch was dead and its error was unhandled by every caller.
--
-- The fix is in the function, not the trigger: 'expired' is terminal by design and allowing expired -> confirmed would
-- let a forfeited seat be sold twice. A booking whose status is 'expired' but whose payment_state is not is refused the
-- same way, because the same UPDATE would hit the same trigger. The body is otherwise 214's, unchanged.

CREATE OR REPLACE FUNCTION public.verify_payment(
  p_booking uuid,
  p_via text DEFAULT 'organizer',
  p_actor_kind text DEFAULT 'organizer',
  p_meta jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_from payment_state;
  v_authorized boolean;
  v_thread_id uuid;
  v_receipt payment_documents%ROWTYPE;
  v_receipt_number text;
  v_delegate boolean := false;
  v_bank boolean := false;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  -- 213: p_actor_kind 'webhook'/'system' used to skip this check while EXECUTE was granted to every signed-in user, so
  -- anyone could confirm anyone's payment. Now the ONLY caller that skips it is the Casso/PayOS bank feed
  -- (api/payment-webhook.js -> record_bank_transaction), and only with the service-role key: auth.role() comes from the
  -- verified JWT, which no signed-in user can forge. Telegram ('system') is gone.
  v_bank := p_actor_kind = 'webhook' AND coalesce(auth.role(), '') = 'service_role';
  IF v_bank THEN
    v_authorized := true;
  ELSE
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  SELECT EXISTS(
    SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_b.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) INTO v_authorized;
  END IF;

  -- 214 (note 76): a project member with money access, behind switch project_delegate_payments, on TOP of the unchanged
  -- check above, and only for a guest who says they paid and waits for a check (pending_verification).
  IF NOT v_authorized THEN
    v_delegate := v_b.payment_state = 'pending_verification' AND public.project_delegate_ok(v_b.event_id, 'money');
    v_authorized := v_delegate;
  END IF;
  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  v_from := v_b.payment_state;

  -- Idempotent by design: two people (or two taps) may approve the same booking.
  IF v_from = 'confirmed' THEN
    RETURN jsonb_build_object('success', true, 'state', 'confirmed', 'noop', true);
  END IF;
  -- 230: an expired hold is not confirmable — its seats went back on sale, and the status trigger (028, widened by 044)
  -- refuses expired -> confirmed, so the UPDATE below would raise 'Invalid booking status transition' instead of
  -- answering. Refuse before any write, with the same INVALID_STATE shape the other stale states use. `status` alone can
  -- be 'expired' (seat forfeited) while payment_state is not, and that UPDATE hits the same trigger, so both are refused.
  IF v_b.status = 'expired' OR v_from = 'expired' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_from);
  END IF;
  IF v_from NOT IN ('holding', 'pending_verification', 'disputed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_from);
  END IF;

  UPDATE bookings SET
    payment_state = 'confirmed',
    status = CASE WHEN status IN ('attended', 'no_show') THEN status
                  ELSE 'confirmed'::booking_status END,
    verified_at = now(),
    verified_via = left(COALESCE(p_via, 'organizer'), 40),
    verified_by = auth.uid(),
    -- The compatibility bridge: every existing ticket gate reads these.
    paid_marked_at = COALESCE(paid_marked_at, now()),
    paid_method = CASE WHEN COALESCE(paid_method, '') = ''
                       THEN left(COALESCE(p_via, 'bank'), 40) ELSE paid_method END,
    paid_marked_by = COALESCE(paid_marked_by,
                              auth.uid()),
    confirmed_at = COALESCE(confirmed_at, now()),
    verify_due_at = NULL
  WHERE id = p_booking
  RETURNING * INTO v_b;

  BEGIN
    PERFORM ensure_payment_document(v_b.id, 'invoice');
    v_receipt := ensure_payment_document(v_b.id, 'receipt');
    v_receipt_number := v_receipt.number;
  EXCEPTION WHEN OTHERS THEN
    v_receipt_number := NULL;
  END;

  -- T3: verification, naming which route settled it.
  PERFORM log_payment_event(
    p_booking, 'T3_verified', v_from, 'confirmed',
    auth.uid(),
    CASE WHEN v_bank THEN 'webhook' WHEN p_actor_kind IN ('webhook', 'system') THEN 'organizer' ELSE p_actor_kind END, NULL, NULL,
    COALESCE(p_meta, '{}'::jsonb)
      || jsonb_build_object('via', p_via, 'receipt_number', v_receipt_number,
                            'amount_vnd', v_b.total_vnd, 'payment_ref', v_b.payment_ref)
  );

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id,
            auth.uid(),
            'Đã xác nhận thanh toán ▪︎ '
            || CASE WHEN v_bank THEN 'tự động đối soát qua ngân hàng' ELSE 'người tổ chức xác nhận' END
            || COALESCE('. Biên nhận ' || v_receipt_number, '') || '.',
            'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_b.user_id, 'payment_confirmed', 'Đã nhận thanh toán',
          'Thanh toán của bạn đã được xác nhận. Vé và biên nhận đã sẵn sàng.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                             'receipt_number', v_receipt_number, 'via', p_via));

  IF v_delegate THEN PERFORM public.event_money_audit_add(v_b.event_id, v_b.id, NULL, 'confirm_payment', NULL); END IF;

  RETURN jsonb_build_object('success', true, 'state', 'confirmed',
                            'receipt_number', v_receipt_number, 'via', p_via);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.verify_payment(uuid, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_payment(uuid, text, text, jsonb) TO authenticated;
