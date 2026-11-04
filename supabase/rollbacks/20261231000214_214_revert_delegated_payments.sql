-- Revert 214: delegated payment confirmation off for good. Puts verify_payment back exactly as 213 defined it and
-- confirm_payment exactly as 060 did, drops the money view, the proof opener, the delegate storage policy and its helper,
-- and restores 211's project_limits(). event_money_audit rows are kept (they follow the booking).
DROP POLICY IF EXISTS "pay_proof_read_delegate" ON storage.objects;
DROP FUNCTION IF EXISTS public.pay_proof_delegate_ok(text);
DROP FUNCTION IF EXISTS public.open_payment_proof(uuid);
DROP FUNCTION IF EXISTS public.get_event_money_view(text);

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

  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  v_from := v_b.payment_state;

  -- Idempotent by design: two people (or two taps) may approve the same booking.
  IF v_from = 'confirmed' THEN
    RETURN jsonb_build_object('success', true, 'state', 'confirmed', 'noop', true);
  END IF;
  IF v_from NOT IN ('holding', 'pending_verification', 'disputed', 'expired') THEN
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

  RETURN jsonb_build_object('success', true, 'state', 'confirmed',
                            'receipt_number', v_receipt_number, 'via', p_via);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.verify_payment(uuid, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_payment(uuid, text, text, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.confirm_payment(p_booking uuid, p_method text DEFAULT 'momo')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_is_authorized boolean;
  v_thread_id uuid;
  v_receipt payment_documents%ROWTYPE;
  v_receipt_number text := NULL;
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
      payment_state = 'confirmed',
      hold_expires_at = NULL,
      verify_due_at = NULL,
      paid_marked_at = now(),
      paid_method = p_method,
      paid_marked_by = auth.uid(),
      confirmed_at = now()
  WHERE id = p_booking;

  -- Documents. The invoice is issued first so a paid booking is never left
  -- holding a receipt for an invoice that was never raised.
  BEGIN
    PERFORM ensure_payment_document(p_booking, 'invoice');
    v_receipt := ensure_payment_document(p_booking, 'receipt');
    v_receipt_number := v_receipt.number;
  EXCEPTION WHEN OTHERS THEN
    v_receipt_number := NULL;
  END;

  SELECT id INTO v_thread_id
  FROM threads
  WHERE event_id = v_booking.event_id AND guest_id = v_booking.user_id;

  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Host marked payment received via ' || COALESCE(p_method, 'direct transfer') || '.'
            || COALESCE(' Biên nhận ▪︎ Receipt ' || v_receipt_number, ''), 'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_booking.user_id, 'payment_confirmed',
          'Đã nhận thanh toán',
          'Người tổ chức xác nhận đã nhận thanh toán của bạn. Biên nhận đã sẵn sàng trong Tài khoản.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_booking.event_id,
                             'receipt_number', v_receipt_number));

  RETURN jsonb_build_object('success', true, 'booking_id', p_booking,
                            'receipt_number', v_receipt_number, 'payment_state', 'confirmed');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.confirm_payment(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.confirm_payment(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.project_limits()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'lanesMax', 10, 'laneNameMax', 24, 'changeWhyMax', 140, 'reasonMin', 3, 'reasonMax', 140,
    'taskTitleMin', 3, 'taskTitleMax', 60, 'postTitleMin', 3, 'postTitleMax', 80, 'postBodyMax', 280,
    'replyMax', 140, 'repliesMax', 10, 'proposalOptionsMin', 2, 'proposalOptionsMax', 4, 'proposalOptionMax', 40,
    'rosTitleMin', 2, 'rosTitleMax', 40, 'rosMinMinutes', 10, 'rosWindowBeforeStartHours', 12, 'rosWindowAfterStartHours', 24,
    'trashMax', 30, 'trashDays', 7, 'channelsMax', 5, 'channelLabelMax', 30, 'channelUrlMax', 300,
    'inviteHours', 48, 'inviteMaxUses', 20, 'grantDays', 7, 'readOnlyDays', 30, 'purgeDays', 90, 'digestHour', 18);
$$;

UPDATE public.app_feature_flag_defs SET description = 'Event Project Hub: team members with money access may confirm payments (needs 213)'
 WHERE key = 'project_delegate_payments';
