-- Migration 219 · six tickets per person per event, across bookings (note 81, phase e). NOT APPLIED.
--
-- Why: v2.3 lets a guest add tickets after a hold by making a SECOND booking (hold_seats_with_attendees). Per booking
-- the cap is 6 (migration 173), but nothing stopped a person holding 6 + 6 + ... on one event. Also, claim_seats() is
-- still EXECUTE-able by every signed-in user and, since migration 162 rewrote it, it is a full legacy insert again:
-- no payment_state, no hold timer, no booking_holds_seat() count, no attendee rows, no per-person cap. No client calls it
-- (web and iOS use hold_seats_with_attendees), so it becomes the thin wrapper migration 029 meant it to be.
--
-- 1. hold_seats(): the body as live on production on 2026-11-14 (pg_get_functiondef, identical to migration 162's),
--    plus ONE block after the criteria check: PER_PERSON_LIMIT when the caller's seat-holding qty + p_qty > 6.
--    Cancelled / expired / lapsed holds do not count; confirmed, pending verification, disputed, attended do.
-- 2. claim_seats(): delegates to hold_seats() (same signature and return type), so it inherits every gate and the cap.
--    EXECUTE revoked from PUBLIC/anon, kept for authenticated.
-- Rollback: supabase/rollbacks/20261231000219_219_revert_per_person_cap.sql (restores both live bodies verbatim).
-- Tests: supabase/tests/219_per_person_cap/run.sh (throwaway stack only).

CREATE OR REPLACE FUNCTION public.hold_seats(p_event text, p_qty integer, p_note text DEFAULT NULL::text, p_ip text DEFAULT NULL::text, p_user_agent text DEFAULT NULL::text)
 RETURNS bookings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_mine int;
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

  -- Strict invite-only events (migration 113) — same gate as claim_seats
  -- above: the organizer owner may always book their own event; anyone
  -- else needs a non-revoked/non-declined/non-expired invite addressed to
  -- them specifically. This is the check that actually matters, since
  -- this is the function the real reserve flow calls.
  IF v_ev.visibility = 'invite'
     AND NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_ev.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
  THEN
    IF NOT EXISTS (
      SELECT 1 FROM event_invites ei
      WHERE ei.event_id = v_ev.id AND ei.invited_user_id = auth.uid()
        AND ei.status IN ('pending', 'accepted') AND ei.expires_at > now()
    ) THEN
      RAISE EXCEPTION 'INVITE_REQUIRED';
    END IF;
  END IF;

  PERFORM public.assert_reservation_criteria(v_ev);

  -- Migration 219: at most 6 tickets per person on one event, counted across ALL of the caller's bookings that still
  -- hold a seat (the same booking_holds_seat() rule as the capacity count below). Before this, the 6 cap lived only in
  -- hold_seats_with_attendees (per booking), so a second booking could take a person past 6. The event row lock above
  -- serialises this count with every other hold on the event.
  SELECT COALESCE(SUM(b.qty), 0) INTO v_mine
  FROM bookings b
  WHERE b.event_id = v_ev.id
    AND b.user_id = auth.uid()
    AND booking_holds_seat(b.payment_state, b.hold_expires_at, b.status);
  IF v_mine + p_qty > 6 THEN RAISE EXCEPTION 'PER_PERSON_LIMIT'; END IF;

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

    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (auth.uid(), 'payment_confirmed', 'Đã xác nhận',
            'Bạn đã tham gia ' || v_ev.name || '. Vé đã sẵn sàng.',
            jsonb_build_object('booking_id', v_booking.id, 'event_id', v_ev.id, 'via', 'free'));
  ELSE
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (auth.uid(), 'hold_created', 'Đã giữ chỗ',
            'Chỗ của bạn cho ' || v_ev.name || ' đang được giữ trong ' || v_hold_minutes
              || ' phút ▪︎ mã ' || v_ref || '. Chuyển khoản và báo lại trước khi hết giờ.',
            jsonb_build_object('booking_id', v_booking.id, 'event_id', v_ev.id,
                               'payment_ref', v_ref, 'hold_expires_at', v_booking.hold_expires_at));
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
$function$;

CREATE OR REPLACE FUNCTION public.claim_seats(p_event text, p_qty integer, p_note text DEFAULT NULL::text)
 RETURNS bookings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Migration 219: the legacy entry point is a thin wrapper, so it gets hold_seats()'s payment state, hold timer,
  -- invite / criteria gates, capacity rule and the per-person cap.
  RETURN public.hold_seats(p_event, p_qty, p_note);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.claim_seats(text, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_seats(text, integer, text) TO authenticated;
