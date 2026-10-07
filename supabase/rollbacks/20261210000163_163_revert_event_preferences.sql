-- Rollback for migration 162 (event preferences + reservation criteria).
-- NOT in the migration chain. Restores claim_seats/hold_seats to migration
-- 113's definitions, then drops everything 162 added. Destroys all saved
-- event preferences, onboarding markers and event reservation criteria.
-- Existing bookings are untouched.
BEGIN;
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
  v_taken int;
  v_user profiles%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_booking_code text;
  v_expires_at timestamptz;
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

  -- Invite-only gate: the organizer owner may always book their own event;
  -- anyone else needs a non-revoked, non-declined, non-expired invite row
  -- addressed to THEM specifically. A pending invite is enough to book —
  -- "accept" is a separate, informational RSVP acknowledgment (see
  -- respond_to_event_invite below), not a hard prerequisite for booking,
  -- per the spec's own "an invite grant is not a ticket" framing (the
  -- ticket rules below are what actually gate the seat, not this switch).
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

  SELECT COALESCE(SUM(qty), 0) INTO v_taken
  FROM bookings
  WHERE event_id = v_ev.id
    AND status IN ('confirmed', 'pending')
    AND (expires_at IS NULL OR expires_at > now());

  IF v_taken + p_qty > v_ev.capacity THEN
    RAISE EXCEPTION 'SOLD_OUT';
  END IF;

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

  IF v_ev.organizer_id IS NOT NULL THEN
    INSERT INTO threads (event_id, guest_id, organizer_id)
    SELECT v_ev.id, auth.uid(), v_ev.organizer_id
    WHERE NOT EXISTS (
      SELECT 1 FROM threads
      WHERE event_id = v_ev.id AND guest_id = auth.uid()
    );
  END IF;

  RETURN v_booking;
END;
$$;
REVOKE EXECUTE ON FUNCTION claim_seats FROM anon;
GRANT EXECUTE ON FUNCTION claim_seats TO authenticated;

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
$$;
REVOKE EXECUTE ON FUNCTION public.hold_seats(text, int, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.hold_seats(text, int, text, text, text) TO authenticated;

DROP FUNCTION IF EXISTS public.assert_reservation_criteria(events);
DROP FUNCTION IF EXISTS public.check_my_reservation_eligibility(text);
DROP FUNCTION IF EXISTS public.event_criteria_check(jsonb, uuid);
DROP FUNCTION IF EXISTS public.criteria_group_missing(jsonb, text[]);
DROP FUNCTION IF EXISTS public.set_event_reservation_criteria(text, jsonb);
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_reservation_criteria_valid;
ALTER TABLE public.events DROP COLUMN IF EXISTS reservation_criteria;
DROP FUNCTION IF EXISTS public.complete_preferences_onboarding(jsonb);
DROP FUNCTION IF EXISTS public.complete_settings_onboarding();
DROP FUNCTION IF EXISTS public.save_my_event_preferences(jsonb);
DROP FUNCTION IF EXISTS public.get_my_event_preferences();
DROP TABLE IF EXISTS public.profile_event_preferences;
DROP TABLE IF EXISTS public.event_onboarding_config;
DROP FUNCTION IF EXISTS public.validate_reservation_criteria(jsonb);
DROP FUNCTION IF EXISTS public.validate_event_preferences(jsonb);
DROP FUNCTION IF EXISTS public.event_pref_multi_ok(jsonb, text);
DROP FUNCTION IF EXISTS public.event_pref_ids(text);
COMMIT;
