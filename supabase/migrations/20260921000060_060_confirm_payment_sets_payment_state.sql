-- ---------------------------------------------------------------------------
-- confirm_payment() (migration 024) predates the two-phase payment_state
-- machine (migration 026) and was never updated after it landed — it only
-- ever set `status = 'confirmed'`, never `payment_state`. Every screen added
-- since 026 (PaymentDetails.jsx's isPending/isConfirmed cards, Home.jsx's
-- myPendingVerification/orgPendingCount banners, Verifications.jsx's
-- v_pending_verifications queue) reads `payment_state`, not `status` — so
-- accepting a guest via Attendance.jsx's "Có nhận khách này không?" ▪︎
-- "Nhận" (which calls this RPC) correctly flipped `status` but left
-- `payment_state` at whatever it was ('holding' or 'pending_verification'),
-- so every one of those screens kept rendering as if still pending: the
-- guest's countdown never disappeared, the organizer's own booking stayed
-- in v_pending_verifications, and both Home banners kept counting it.
--
-- Fixed the same way reject_pending_guest() (migration 059) halts a
-- rejected booking's timers: payment_state -> 'confirmed', and both
-- hold_expires_at/verify_due_at cleared so nothing keeps counting down
-- against a deadline that no longer means anything. Everything else here
-- is unchanged from migration 024.
-- ---------------------------------------------------------------------------
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
