-- Migration: Flow 2 — host refund -> guest confirmation lifecycle.
--
-- refund_claims/refund_status/refund_reason and goc_flag_overdue_refunds()
-- already existed (002/008); the three transition RPCs below did not.
--
-- 1. cancel_booking() fix: it always inserted refund_claims.reason =
--    'guest_cancelled', even when an organizer/admin cancelled a paid
--    booking (confirmed by reading the current definition, migration 022) —
--    only cancel_event() (011) got the host branch right. Fixed here by
--    checking whether the caller IS the booking's own guest, same
--    v_is_authorized reasoning that function already computes; guest-
--    initiated cancellation is untouched (still 'guest_cancelled').
--
-- 2. mark_refund_sent/confirm_refund_received/dispute_refund: the
--    owed -> host_marked_sent -> guest_confirmed / disputed state machine.
--    Each is idempotent (a repeat call at the target state returns success
--    without re-inserting a notification or moving state backward) and each
--    notifies the other party exactly once per real transition.
--
-- 3. goc_flag_overdue_refunds(): unchanged scoping (rc.status = 'owed',
--    rc.last_flagged_at IS NULL — already never double-counts a disputed
--    claim, since disputing it moves status off 'owed' and this function's
--    own WHERE clause excludes anything that isn't), now also sends the
--    organizer a real 'refund_overdue' notification (previously it only
--    incremented disputes_open silently).
--
-- Amount formatting/recipient-resolution both match this codebase's own
-- established conventions exactly (025/026/053: `replace(to_char(n,
-- 'FM999G999G999'), ',', '.') || '₫'`; `COALESCE(o.owner_id, o.user_id)`).

-- ---------------------------------------------------------------------------
-- 1. cancel_booking() — host-cancelled branch now writes the correct reason.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cancel_booking(p_booking uuid, p_reason text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_authorized boolean;
  v_thread_id uuid;
  v_had_payment boolean;
  v_clean_reason text := trim(p_reason);
  v_host_initiated boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT b.* INTO v_booking FROM bookings b WHERE b.id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  v_is_authorized := (v_booking.user_id = auth.uid()) OR EXISTS(
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_booking.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  );

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_booking.status IN ('cancelled', 'expired', 'attended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_CANNOT_BE_CANCELLED');
  END IF;

  -- Captured from the pre-update snapshot: a booking already marked
  -- 'confirmed', or one a host had separately marked paid, had payment
  -- collected — the refund claim and the guest's notification both need to
  -- say so.
  v_had_payment := v_booking.status = 'confirmed' OR v_booking.paid_marked_at IS NOT NULL;
  -- The caller is already known to be authorized above (guest / host /
  -- admin) — anyone who isn't the booking's own guest is cancelling it on
  -- someone else's behalf, i.e. an organizer or admin acting as the host.
  -- This ONLY changes which `refund_reason` a refund claim gets; nothing
  -- else about guest-initiated cancellation changes.
  v_host_initiated := v_booking.user_id IS DISTINCT FROM auth.uid();

  UPDATE bookings
  SET status = 'cancelled',
      cancelled_at = now(),
      cancelled_by = auth.uid(),
      cancel_reason = COALESCE(p_reason, '')
  WHERE id = p_booking;

  IF v_had_payment THEN
    INSERT INTO refund_claims (booking_id, reservation_id, amount_vnd, reason, status)
    VALUES (
      v_booking.id, v_booking.id, v_booking.total_vnd,
      CASE WHEN v_host_initiated THEN 'host_cancelled' ELSE 'guest_cancelled' END,
      'owed'
    );
  END IF;

  SELECT id INTO v_thread_id
  FROM threads
  WHERE event_id = v_booking.event_id AND guest_id = v_booking.user_id;

  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(), 'Booking cancelled. Reason: ' || COALESCE(NULLIF(p_reason, ''), 'No reason provided') || '.', 'system');
  END IF;

  -- Notify the guest, unless they're the one who just cancelled it themselves.
  IF v_booking.user_id IS NOT NULL AND v_booking.user_id <> auth.uid() THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_booking.user_id,
      'booking_cancelled',
      'Vé của bạn đã bị huỷ',
      COALESCE(v_event.name, 'Sự kiện') || ' đã huỷ vé của bạn.'
        || (CASE WHEN v_had_payment THEN ' Khoản bạn đã thanh toán sẽ được hoàn lại.' ELSE '' END)
        || (CASE WHEN v_clean_reason <> '' THEN ' Lý do: ' || v_clean_reason ELSE '' END),
      jsonb_build_object('event_id', v_booking.event_id, 'booking_id', v_booking.id, 'reason', v_clean_reason, 'had_payment', v_had_payment)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'booking_id', p_booking);
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_booking(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION cancel_booking(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. mark_refund_sent() — host presses "Đã hoàn tiền" after transferring
--    the refund outside the app. owed -> host_marked_sent only.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_refund_sent(p_claim_id uuid, p_note text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_host boolean;
  v_note text := trim(p_note);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  SELECT EXISTS(
    SELECT 1 FROM organizers o
    WHERE o.id = v_event.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) INTO v_is_host;
  IF NOT v_is_host THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- Idempotent repeat tap: already at the target state — report it, don't
  -- re-notify or move anything.
  IF v_claim.status = 'host_marked_sent' THEN
    RETURN jsonb_build_object('success', true, 'status', v_claim.status, 'already', true);
  END IF;
  IF v_claim.status <> 'owed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;

  UPDATE refund_claims
  SET status = 'host_marked_sent',
      host_marked_at = now(),
      note = CASE WHEN v_note <> ''
                  THEN COALESCE(note || E'\n', '') || 'Host note: ' || v_note
                  ELSE note END
  WHERE id = p_claim_id;

  IF v_booking.user_id IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_booking.user_id, 'refund_marked_sent',
      'Người tổ chức đã báo hoàn tiền',
      COALESCE(v_event.name, 'Sự kiện') || ' báo đã hoàn '
        || replace(to_char(v_claim.amount_vnd, 'FM999G999G999'), ',', '.') || '₫ cho bạn.',
      jsonb_build_object('claim_id', v_claim.id, 'booking_id', v_booking.id, 'event_id', v_event.id, 'amount_vnd', v_claim.amount_vnd)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'host_marked_sent');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_refund_sent(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_refund_sent(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. confirm_refund_received() — guest presses "Đã nhận tiền".
--    host_marked_sent -> guest_confirmed only.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirm_refund_received(p_claim_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_recipient uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  IF NOT FOUND OR v_booking.user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_claim.status = 'guest_confirmed' THEN
    RETURN jsonb_build_object('success', true, 'status', v_claim.status, 'already', true);
  END IF;
  IF v_claim.status <> 'host_marked_sent' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;

  UPDATE refund_claims
  SET status = 'guest_confirmed',
      guest_confirmed_at = now()
  WHERE id = p_claim_id;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;
  SELECT * INTO v_org FROM organizers WHERE id = v_event.organizer_id;
  v_recipient := COALESCE(v_org.owner_id, v_org.user_id);

  IF v_recipient IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_recipient, 'refund_confirmed',
      'Khách đã xác nhận nhận được hoàn tiền',
      'Khách xác nhận đã nhận ' || replace(to_char(v_claim.amount_vnd, 'FM999G999G999'), ',', '.')
        || '₫ cho ' || COALESCE(v_event.name, 'sự kiện') || '.',
      jsonb_build_object('claim_id', v_claim.id, 'booking_id', v_booking.id, 'event_id', v_event.id, 'amount_vnd', v_claim.amount_vnd)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'guest_confirmed');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.confirm_refund_received(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.confirm_refund_received(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. dispute_refund() — guest presses "Chưa nhận được". Allowed from
--    owed or host_marked_sent (a guest can dispute either "you never sent
--    it" or "you said you sent it but I never got it").
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dispute_refund(p_claim_id uuid, p_reason text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_recipient uuid;
  v_reason text := trim(p_reason);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  IF NOT FOUND OR v_booking.user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_claim.status = 'disputed' THEN
    RETURN jsonb_build_object('success', true, 'status', v_claim.status, 'already', true);
  END IF;
  IF v_claim.status NOT IN ('owed', 'host_marked_sent') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;
  SELECT * INTO v_org FROM organizers WHERE id = v_event.organizer_id;
  v_recipient := COALESCE(v_org.owner_id, v_org.user_id);

  UPDATE refund_claims
  SET status = 'disputed',
      -- Append, never overwrite: a host may already have left a real
      -- reference/transfer note here (mark_refund_sent's own p_note) —
      -- this labels the guest's own addition instead of clobbering it.
      note = CASE WHEN v_reason <> ''
                  THEN COALESCE(note || E'\n', '') || 'Guest dispute: ' || v_reason
                  ELSE note END
  WHERE id = p_claim_id;

  -- disputes_open must go up exactly once per claim. If
  -- goc_flag_overdue_refunds() already flagged this claim (last_flagged_at
  -- set, because it sat 'owed' for 72h before the guest ever disputed it),
  -- that already counted it once — don't count it again here. Otherwise,
  -- count it now and mark it flagged, so the 72h job (whose own WHERE
  -- clause requires status = 'owed', already false the instant this
  -- commits) can never later double-count it either.
  IF v_recipient IS NOT NULL AND v_claim.last_flagged_at IS NULL THEN
    UPDATE organizers SET disputes_open = COALESCE(disputes_open, 0) + 1 WHERE id = v_org.id;
    UPDATE refund_claims SET last_flagged_at = now() WHERE id = p_claim_id;
  END IF;

  IF v_recipient IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_recipient, 'refund_disputed',
      'Khách báo chưa nhận được hoàn tiền',
      'Khách báo chưa nhận được ' || replace(to_char(v_claim.amount_vnd, 'FM999G999G999'), ',', '.')
        || '₫ cho ' || COALESCE(v_event.name, 'sự kiện') || '.'
        || (CASE WHEN v_reason <> '' THEN ' Lý do: ' || v_reason ELSE '' END),
      jsonb_build_object('claim_id', v_claim.id, 'booking_id', v_booking.id, 'event_id', v_event.id, 'amount_vnd', v_claim.amount_vnd, 'reason', v_reason)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'disputed');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.dispute_refund(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.dispute_refund(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. goc_flag_overdue_refunds() — same scoping as before (008), now also
--    tells the organizer, not just the internal counter.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION goc_flag_overdue_refunds()
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  v_count int := 0;
  v_row record;
  v_recipient uuid;
BEGIN
  FOR v_row IN
    SELECT rc.id AS claim_id, rc.booking_id, rc.amount_vnd,
           e.id AS event_id, e.name AS event_name, e.organizer_id,
           o.owner_id, o.user_id AS org_user_id
    FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    JOIN organizers o ON o.id = e.organizer_id
    WHERE rc.status = 'owed'
      AND rc.last_flagged_at IS NULL
      AND rc.created_at < now() - interval '72 hours'
      AND e.organizer_id IS NOT NULL
  LOOP
    UPDATE organizers
       SET disputes_open = COALESCE(disputes_open, 0) + 1
     WHERE id = v_row.organizer_id;

    UPDATE refund_claims
       SET last_flagged_at = now()
     WHERE id = v_row.claim_id;

    v_recipient := COALESCE(v_row.owner_id, v_row.org_user_id);
    IF v_recipient IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_recipient, 'refund_overdue',
        'Hoàn tiền quá hạn 72 giờ',
        'Khoản hoàn ' || replace(to_char(v_row.amount_vnd, 'FM999G999G999'), ',', '.')
          || '₫ cho ' || COALESCE(v_row.event_name, 'sự kiện') || ' vẫn chưa được xử lý sau 72 giờ.',
        jsonb_build_object('claim_id', v_row.claim_id, 'booking_id', v_row.booking_id, 'event_id', v_row.event_id, 'amount_vnd', v_row.amount_vnd)
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION goc_flag_overdue_refunds() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION goc_flag_overdue_refunds() FROM anon;
GRANT EXECUTE ON FUNCTION goc_flag_overdue_refunds() TO authenticated;
