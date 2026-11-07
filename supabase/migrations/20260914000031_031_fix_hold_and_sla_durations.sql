-- Migration: fix two swapped duration constants in the two-phase payment
-- machine — the buyer's PHASE 1 hold and the organizer's PHASE 2
-- verification window ended up on the wrong numbers.
--
-- ---------------------------------------------------------------------------
-- WHAT WAS WRONG
-- ---------------------------------------------------------------------------
-- Migration 026 bumped events.hold_minutes' DEFAULT from the original
-- schema's 30 to 60, and hold_seats()'s own COALESCE fallback to match — the
-- buyer's hold was meant to become 30 minutes, not 60. Every event created
-- since then held a seat for a full hour while the Reserve button (until the
-- previous commit) said "60 minutes" to match — self-consistent, but the
-- wrong number for both sides of that consistency. No client ever lets an
-- organizer customize hold_minutes per event (there's no such field
-- anywhere in create_event/CreateEvent.jsx), so this is a global default
-- fixed from the server, not a per-event exception.
--
-- Separately, submit_payment_proof()'s organizer-side response window
-- (verify_due_at) was being started at 15 minutes — both clients passed
-- p_sla_minutes: 15 explicitly, and the RPC's own DEFAULT agreed — when the
-- intended window is 60 minutes. This is a genuinely different clock from
-- the buyer's hold (booking_holds_seat() stops consulting hold_expires_at
-- the moment payment_state leaves 'holding' — see that function's own
-- comment), so fixing the hold duration does nothing for this one; both
-- need fixing independently.
--
-- ---------------------------------------------------------------------------
-- 1. Buyer's hold: back to 30 minutes.
-- ---------------------------------------------------------------------------
ALTER TABLE public.events ALTER COLUMN hold_minutes SET DEFAULT 30;

-- Every event still sitting at exactly 60 got there from the column
-- default 026 set (no create flow ever lets an organizer choose this
-- value), so this is a safe, global correction — not an override of any
-- deliberate per-event choice.
UPDATE public.events SET hold_minutes = 30 WHERE hold_minutes = 60;

CREATE OR REPLACE FUNCTION public.hold_seats(
  p_event text, p_qty int, p_note text DEFAULT NULL,
  p_ip text DEFAULT NULL, p_user_agent text DEFAULT NULL
)
RETURNS bookings
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ev events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_user profiles%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_taken int;
  v_is_free boolean;
  v_hold_minutes int;
  v_ref text;
  v_thread_id uuid;
  v_recipient uuid;
  v_message text;
  v_amount_str text;
  v_pay_lines text := '';
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_qty IS NULL OR p_qty < 1 OR p_qty > 20 THEN RAISE EXCEPTION 'INVALID_QTY'; END IF;

  SELECT * INTO v_user FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;

  -- The lock that makes the count below trustworthy.
  SELECT * INTO v_ev FROM events
   WHERE id = p_event OR slug = p_event OR key = p_event
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVENT_NOT_FOUND'; END IF;
  IF v_ev.status != 'live' AND v_ev.status::text != 'open' THEN RAISE EXCEPTION 'EVENT_NOT_LIVE'; END IF;

  SELECT COALESCE(SUM(b.qty), 0) INTO v_taken
  FROM bookings b
  WHERE b.event_id = v_ev.id
    AND booking_holds_seat(b.payment_state, b.hold_expires_at, b.status);

  IF v_taken + p_qty > v_ev.capacity THEN RAISE EXCEPTION 'SOLD_OUT'; END IF;

  IF v_ev.organizer_id IS NOT NULL THEN
    SELECT * INTO v_org FROM organizers WHERE id = v_ev.organizer_id;
  END IF;

  v_is_free := COALESCE(v_ev.price_vnd, 0) <= 0;
  v_hold_minutes := GREATEST(COALESCE(v_ev.hold_minutes, 30), 1);
  v_ref := 'ART' || lpad(nextval('payment_ref_seq')::text, 5, '0');

  INSERT INTO bookings (
    event_id, user_id, qty, total_vnd, code, status, guest_note,
    payment_state, payment_ref, hold_minutes, hold_expires_at, expires_at, confirmed_at
  ) VALUES (
    v_ev.id, auth.uid(), p_qty, COALESCE(v_ev.price_vnd, 0) * p_qty,
    upper(substr(md5(gen_random_uuid()::text), 1, 6)),
    -- Seat status still follows the event's approval mode; payment_state is
    -- the axis that decides whether a ticket exists.
    CASE WHEN v_ev.approval = 'instant' THEN 'confirmed'::booking_status
         ELSE 'pending'::booking_status END,
    p_note,
    CASE WHEN v_is_free THEN 'confirmed'::payment_state
         ELSE 'holding'::payment_state END,
    v_ref, v_hold_minutes,
    CASE WHEN v_is_free THEN NULL ELSE now() + make_interval(mins => v_hold_minutes) END,
    CASE WHEN v_is_free THEN NULL ELSE now() + make_interval(mins => v_hold_minutes) END,
    CASE WHEN v_ev.approval = 'instant' THEN now() ELSE NULL END
  )
  RETURNING * INTO v_booking;

  -- T1: reservation, with the buyer's session metadata.
  PERFORM log_payment_event(
    v_booking.id, 'T1_hold_created', NULL, v_booking.payment_state,
    auth.uid(), 'buyer', p_ip, p_user_agent,
    jsonb_build_object(
      'qty', p_qty, 'total_vnd', v_booking.total_vnd, 'payment_ref', v_ref,
      'hold_minutes', v_hold_minutes, 'hold_expires_at', v_booking.hold_expires_at,
      'is_free', v_is_free
    )
  );

  IF v_is_free THEN
    UPDATE bookings SET
      paid_marked_at = now(), paid_method = 'free',
      verified_at = now(), verified_via = 'free',
      confirmed_at = COALESCE(confirmed_at, now()), status = 'confirmed'
    WHERE id = v_booking.id
    RETURNING * INTO v_booking;

    PERFORM log_payment_event(v_booking.id, 'T3_verified', 'holding', 'confirmed',
                              NULL, 'system', NULL, NULL,
                              jsonb_build_object('via', 'free'));
    BEGIN
      PERFORM ensure_payment_document(v_booking.id, 'invoice');
      PERFORM ensure_payment_document(v_booking.id, 'receipt');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  IF v_ev.organizer_id IS NOT NULL THEN
    INSERT INTO threads (event_id, guest_id, organizer_id)
    SELECT v_ev.id, auth.uid(), v_ev.organizer_id
    WHERE NOT EXISTS (SELECT 1 FROM threads WHERE event_id = v_ev.id AND guest_id = auth.uid());
    SELECT id INTO v_thread_id FROM threads WHERE event_id = v_ev.id AND guest_id = auth.uid();

    IF v_thread_id IS NOT NULL THEN
      IF v_is_free THEN
        v_message := 'Đặt chỗ thành công ▪︎ sự kiện miễn phí, không cần thanh toán.';
      ELSE
        v_amount_str := replace(to_char(v_booking.total_vnd, 'FM999G999G999'), ',', '.') || '₫';
        IF COALESCE(v_org.bank_account_no, '') <> '' THEN
          v_pay_lines := v_pay_lines || 'Ngân hàng: ' || COALESCE(v_org.bank_name, '')
                       || ', STK ' || v_org.bank_account_no
                       || COALESCE(' (' || NULLIF(v_org.bank_account_name, '') || ')', '') || '. ';
        END IF;
        IF COALESCE(v_org.momo_phone, '') <> '' THEN
          v_pay_lines := v_pay_lines || 'MoMo: ' || v_org.momo_phone || '. ';
        END IF;

        v_message := 'Đặt chỗ thành công ▪︎ số tiền ' || v_amount_str
                  || '. Nội dung chuyển khoản bắt buộc: ' || v_ref
                  || '. Giữ chỗ trong ' || v_hold_minutes || ' phút.'
                  || CASE WHEN v_pay_lines = ''
                          THEN ' Người tổ chức sẽ gửi thông tin chuyển khoản sớm.'
                          ELSE ' Chuyển khoản tới: ' || v_pay_lines END
                  || COALESCE(NULLIF(v_org.pay_note, '') || ' ', '')
                  || 'Sau khi chuyển, bấm "Tôi đã chuyển khoản" để giữ chỗ không bị huỷ.';
      END IF;

      INSERT INTO messages (thread_id, sender_id, body, kind)
      VALUES (v_thread_id, auth.uid(), v_message, 'system');
    END IF;

    SELECT COALESCE(v_org.owner_id, v_org.user_id) INTO v_recipient;
    IF v_recipient IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_recipient, 'booking_requested',
        CASE WHEN v_is_free THEN 'Có người tham gia mới' ELSE 'Yêu cầu đặt chỗ mới' END,
        COALESCE(NULLIF(v_user.display_name, ''), 'Một người tham gia')
          || ' đã đặt ' || p_qty || ' chỗ cho ' || v_ev.name
          || CASE WHEN v_is_free THEN '.' ELSE ' ▪︎ mã ' || v_ref || '.' END,
        jsonb_build_object('booking_id', v_booking.id, 'event_id', v_ev.id,
                           'payment_ref', v_ref, 'qty', p_qty,
                           'total_vnd', v_booking.total_vnd, 'is_free', v_is_free)
      );
    END IF;
  END IF;

  RETURN v_booking;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Organizer's response window: 60 minutes (was 15, both in the RPC's own
--    default and in what both clients passed explicitly — the clients are
--    fixed alongside this migration).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_payment_proof(
  p_booking uuid,
  p_transaction_id text,
  p_proof_path text,
  p_ip text DEFAULT NULL,
  p_user_agent text DEFAULT NULL,
  p_sla_minutes int DEFAULT 60
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_from payment_state;
  v_thread_id uuid;
  v_recipient uuid;
  v_txn text := left(trim(COALESCE(p_transaction_id, '')), 120);
  v_proof text := left(trim(COALESCE(p_proof_path, '')), 400);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  IF v_b.user_id <> auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- The spec requires proof AND a transaction id; without both there is
  -- nothing for an organizer to reconcile against their statement.
  IF v_txn = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'TRANSACTION_ID_REQUIRED');
  END IF;
  IF v_proof = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'PROOF_REQUIRED');
  END IF;

  v_from := v_b.payment_state;

  -- Already sorted: say so rather than reopening a settled booking.
  IF v_from = 'confirmed' THEN
    RETURN jsonb_build_object('success', true, 'state', 'confirmed', 'noop', true);
  END IF;
  IF v_from = 'pending_verification' THEN
    -- Re-submitting replaces the evidence but must not restart the SLA, or a
    -- buyer could keep an organizer's clock permanently reset.
    UPDATE bookings SET transaction_id = v_txn, proof_path = v_proof, proof_uploaded_at = now()
    WHERE id = p_booking RETURNING * INTO v_b;
    PERFORM log_payment_event(p_booking, 'T2_proof_resubmitted', v_from, v_from,
                              auth.uid(), 'buyer', p_ip, p_user_agent,
                              jsonb_build_object('transaction_id', v_txn, 'proof_path', v_proof));
    RETURN jsonb_build_object('success', true, 'state', 'pending_verification',
                              'verify_due_at', v_b.verify_due_at);
  END IF;
  IF v_from NOT IN ('holding', 'expired') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_from);
  END IF;

  -- A hold that lapsed only moments ago, whose seat nothing has taken yet, is
  -- recoverable — the buyer did pay. If the seat is gone, it is gone, and
  -- saying so here is far better than confirming a ticket that cannot exist.
  IF v_from = 'expired' THEN
    IF EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = v_b.event_id
        AND (SELECT COALESCE(SUM(b2.qty), 0) FROM bookings b2
             WHERE b2.event_id = e.id
               AND booking_holds_seat(b2.payment_state, b2.hold_expires_at, b2.status))
            + v_b.qty > e.capacity
    ) THEN
      PERFORM log_payment_event(p_booking, 'T2_proof_rejected_sold_out', v_from, v_from,
                                auth.uid(), 'buyer', p_ip, p_user_agent,
                                jsonb_build_object('transaction_id', v_txn));
      RETURN jsonb_build_object('success', false, 'error', 'HOLD_EXPIRED_AND_SOLD_OUT');
    END IF;
  END IF;

  UPDATE bookings SET
    payment_state = 'pending_verification',
    transaction_id = v_txn,
    proof_path = v_proof,
    proof_uploaded_at = now(),
    proof_submitted_at = now(),
    -- The organizer's clock starts here. The buyer's is now irrelevant:
    -- booking_holds_seat() stops consulting hold_expires_at outside 'holding'.
    verify_due_at = now() + make_interval(mins => GREATEST(COALESCE(p_sla_minutes, 60), 1)),
    verify_reminded_at = NULL,
    verify_escalated_at = NULL,
    status = CASE WHEN status = 'expired' THEN 'pending'::booking_status ELSE status END
  WHERE id = p_booking
  RETURNING * INTO v_b;

  -- T2: the buyer's confirmation, with everything a dispute would need.
  PERFORM log_payment_event(
    p_booking, 'T2_proof_submitted', v_from, 'pending_verification',
    auth.uid(), 'buyer', p_ip, p_user_agent,
    jsonb_build_object(
      'transaction_id', v_txn, 'proof_path', v_proof,
      'payment_ref', v_b.payment_ref, 'amount_vnd', v_b.total_vnd,
      'verify_due_at', v_b.verify_due_at, 'recovered_from_expired', v_from = 'expired'
    )
  );

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Khách báo đã chuyển khoản ▪︎ mã ' || COALESCE(v_b.payment_ref, '')
            || ', mã giao dịch ' || v_txn || '. Chỗ được giữ cho tới khi bạn xác nhận.',
            'system');
  END IF;

  SELECT COALESCE(o.owner_id, o.user_id) INTO v_recipient
  FROM events e JOIN organizers o ON o.id = e.organizer_id
  WHERE e.id = v_b.event_id;

  IF v_recipient IS NOT NULL THEN
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_recipient, 'payment_awaiting_verification',
      'Cần xác nhận thanh toán',
      'Một khách đã báo chuyển khoản ' || replace(to_char(v_b.total_vnd, 'FM999G999G999'), ',', '.')
        || '₫ ▪︎ mã ' || COALESCE(v_b.payment_ref, '') || '. Kiểm tra và xác nhận.',
      jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                         'payment_ref', v_b.payment_ref, 'transaction_id', v_txn,
                         'amount_vnd', v_b.total_vnd, 'verify_due_at', v_b.verify_due_at)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'state', 'pending_verification',
                            'verify_due_at', v_b.verify_due_at,
                            'payment_ref', v_b.payment_ref);
END;
$$;
