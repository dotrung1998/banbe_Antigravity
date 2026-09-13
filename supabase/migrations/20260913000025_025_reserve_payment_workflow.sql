-- Migration: the actual "reserve -> pay -> confirm" workflow.
--
-- Until now, claim_seats() created a booking and the client jumped straight
-- to the QR ticket screen regardless of whether anyone had paid anything —
-- for 'instant' approval events (every seeded demo event) that meant the
-- ticket appeared immediately, with no payment step at all. This migration
-- doesn't change what claim_seats() decides about *seat* holding (that's
-- still instant vs. a 30-minute hold, per the event's approval mode); it
-- adds the missing payment loop around it:
--
--   1. claim_seats() now also tells the guest how to pay (a system message
--      in their thread, built from the organizer's own payment details —
--      migration 024) and tells the organizer a booking is waiting on them
--      (a 'booking_requested' notification).
--   2. The organizer confirms payment (confirm_payment(), already wired to
--      Attendance's "mark as paid") — unchanged from 024, still issues the
--      receipt and notifies the guest ('payment_confirmed').
--   3. Only paid_marked_at (not booking.status) gates the QR ticket on the
--      client — that part is a client change, not this migration's — so a
--      booking can sit "confirmed" (seat-wise) but unpaid without ever
--      showing a ticket.
--
-- A free event (price_vnd <= 0) has nothing to collect, so claim_seats()
-- marks it paid immediately instead of making an organizer click through an
-- empty confirmation for $0.

CREATE OR REPLACE FUNCTION claim_seats(
  p_event text,
  p_qty int,
  p_note text DEFAULT NULL
)
RETURNS bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_taken int;
  v_user profiles%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_booking_code text;
  v_expires_at timestamptz;
  v_is_free boolean;
  v_thread_id uuid;
  v_amount_str text;
  v_pay_lines text := '';
  v_message text;
  v_recipient uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  SELECT * INTO v_user FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND';
  END IF;

  SELECT * INTO v_ev FROM events WHERE id = p_event OR slug = p_event OR key = p_event FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND';
  END IF;

  IF v_ev.status != 'live' AND v_ev.status::text != 'open' THEN
    RAISE EXCEPTION 'EVENT_NOT_LIVE';
  END IF;

  SELECT COALESCE(SUM(qty), 0) INTO v_taken
  FROM bookings
  WHERE event_id = v_ev.id
    AND status IN ('confirmed', 'pending')
    AND (expires_at IS NULL OR expires_at > now());

  IF v_taken + p_qty > v_ev.capacity THEN
    RAISE EXCEPTION 'SOLD_OUT';
  END IF;

  IF v_ev.organizer_id IS NOT NULL THEN
    SELECT * INTO v_org FROM organizers WHERE id = v_ev.organizer_id;
  END IF;

  v_is_free := COALESCE(v_ev.price_vnd, 0) <= 0;
  v_booking_code := upper(substr(md5(gen_random_uuid()::text), 1, 6));

  IF v_ev.approval = 'instant' THEN
    INSERT INTO bookings (
      event_id, user_id, qty, total_vnd, code, status, guest_note, confirmed_at
    ) VALUES (
      v_ev.id, auth.uid(), p_qty, v_ev.price_vnd * p_qty, v_booking_code, 'confirmed', p_note, now()
    )
    RETURNING * INTO v_booking;
  ELSE
    v_expires_at := now() + interval '30 minutes';
    INSERT INTO bookings (
      event_id, user_id, qty, total_vnd, code, status, expires_at, guest_note
    ) VALUES (
      v_ev.id, auth.uid(), p_qty, v_ev.price_vnd * p_qty, v_booking_code, 'pending', v_expires_at, p_note
    )
    RETURNING * INTO v_booking;
  END IF;

  -- Nothing to collect on a free event — skip straight to paid, and back it
  -- with the same documents a real payment would get (confirm_payment does
  -- the same pair; failures here must not lose the booking itself).
  IF v_is_free THEN
    UPDATE bookings SET
      status = 'confirmed',
      paid_marked_at = now(),
      paid_method = 'free',
      confirmed_at = COALESCE(confirmed_at, now())
    WHERE id = v_booking.id
    RETURNING * INTO v_booking;

    BEGIN
      PERFORM ensure_payment_document(v_booking.id, 'invoice');
      PERFORM ensure_payment_document(v_booking.id, 'receipt');
    EXCEPTION WHEN OTHERS THEN
      NULL; -- the booking stands even if the paperwork couldn't be minted
    END;
  END IF;

  IF v_ev.organizer_id IS NOT NULL THEN
    INSERT INTO threads (event_id, guest_id, organizer_id)
    SELECT v_ev.id, auth.uid(), v_ev.organizer_id
    WHERE NOT EXISTS (
      SELECT 1 FROM threads
      WHERE event_id = v_ev.id AND guest_id = auth.uid()
    );

    SELECT id INTO v_thread_id FROM threads
     WHERE event_id = v_ev.id AND guest_id = auth.uid();

    IF v_thread_id IS NOT NULL THEN
      IF v_is_free THEN
        v_message := 'Đặt chỗ thành công ▪︎ sự kiện miễn phí, không cần thanh toán.'
                  || ' Reservation confirmed ▪︎ this event is free, nothing to pay.';
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

        IF v_pay_lines = '' THEN
          -- The organizer hasn't filled in payment details yet (Payout /
          -- save_organizer_payment, migration 024) — say so rather than
          -- sending an empty instruction.
          v_message := 'Đặt chỗ thành công ▪︎ số tiền cần thanh toán ' || v_amount_str
                    || ' (mã ' || v_booking.code || '). Người tổ chức sẽ gửi thông tin chuyển khoản sớm.';
        ELSE
          v_message := 'Đặt chỗ thành công ▪︎ số tiền cần thanh toán ' || v_amount_str
                    || ' (mã ' || v_booking.code || '). Chuyển khoản tới: ' || v_pay_lines
                    || COALESCE(NULLIF(v_org.pay_note, '') || ' ', '')
                    || 'Xem chi tiết và gửi ảnh xác nhận trong mục Thanh toán.';
        END IF;
      END IF;

      INSERT INTO messages (thread_id, sender_id, body, kind)
      VALUES (v_thread_id, auth.uid(), v_message, 'system');
    END IF;

    -- The organizer learns a spot was just taken, whether or not it needs
    -- their attention to collect payment on — tapping it opens their
    -- check-in list for this event (see openAttendance / Attendance screen),
    -- where "mark as paid" already lives.
    SELECT COALESCE(v_org.owner_id, v_org.user_id) INTO v_recipient;
    IF v_recipient IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_recipient,
        'booking_requested',
        CASE WHEN v_is_free THEN 'Có người tham gia mới' ELSE 'Yêu cầu đặt chỗ mới' END,
        COALESCE(NULLIF(v_user.display_name, ''), 'Một người tham gia')
          || ' đã đặt ' || p_qty || CASE WHEN p_qty = 1 THEN ' chỗ' ELSE ' chỗ' END
          || ' cho ' || v_ev.name
          || CASE WHEN v_is_free THEN '.' ELSE ' ▪︎ chờ xác nhận thanh toán.' END,
        jsonb_build_object(
          'booking_id', v_booking.id, 'event_id', v_ev.id, 'user_id', auth.uid(),
          'qty', p_qty, 'total_vnd', v_booking.total_vnd, 'is_free', v_is_free
        )
      );
    END IF;
  END IF;

  RETURN v_booking;
END;
$$;
REVOKE EXECUTE ON FUNCTION claim_seats FROM anon;
GRANT EXECUTE ON FUNCTION claim_seats TO authenticated;
