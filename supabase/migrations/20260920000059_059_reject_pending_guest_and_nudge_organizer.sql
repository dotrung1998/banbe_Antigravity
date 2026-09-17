-- .claude/notes/14-organizer-checkin.md follow-up (Bugs 1-2):
--
-- 1. nudge_organizer() — the guest's ONE actionable control on the
--    read-only "awaiting the organizer's confirm window" screen (replacing
--    the wrongly-reachable organizer Verifications screen — see the client
--    fix in GocContext.jsx/AppState+Data.swift's openNotification()).
--    Rate-limited to 2 uses per hold via a real counter column, not
--    debouncing — a client-side debounce resets on reload/reinstall and a
--    determined guest could just keep tapping.
--
-- 2. reject_pending_guest() — the organizer's "Có nhận khách này không?" ▪
--    "Từ chối" path. Modeled directly on cancel_booking() (022) — same
--    organizer-authorization shape as reject_payment() (042) — but unlike
--    cancel_booking() (which only ever sets `status`), this ALSO sets
--    `payment_state = 'cancelled'`: v_pending_verifications (041) filters
--    strictly on `payment_state = 'pending_verification'`, so leaving that
--    column untouched would have left a "rejected" booking still showing up
--    in the organizer's own Verifications queue. `hold_expires_at`/
--    `verify_due_at` are both cleared too — halts every pending timer, not
--    just the visible status. booking_holds_seat() (026:112) already
--    returns false for `status IN ('cancelled','expired')` regardless of
--    payment_state, so clearing `status` alone already frees the seat back
--    to the pool; setting payment_state to the same 'cancelled' value is
--    purely about dropping out of v_pending_verifications, not the seat
--    count.

ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS nudge_count int NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.nudge_organizer(p_booking uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_ev events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_recipient uuid;
  v_guest_name text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  IF v_b.user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- Only meaningful while the organizer's own confirm window is actually
  -- running — nudging before proof is even submitted, or after the booking
  -- already resolved one way or another, has nothing to nudge.
  IF v_b.payment_state != 'pending_verification' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_b.payment_state);
  END IF;

  IF v_b.nudge_count >= 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'NUDGE_LIMIT_REACHED', 'nudge_count', v_b.nudge_count);
  END IF;

  UPDATE bookings SET nudge_count = nudge_count + 1 WHERE id = p_booking RETURNING * INTO v_b;

  SELECT * INTO v_ev FROM events WHERE id = v_b.event_id;
  IF v_ev.organizer_id IS NOT NULL THEN
    SELECT * INTO v_org FROM organizers WHERE id = v_ev.organizer_id;
    SELECT COALESCE(v_org.owner_id, v_org.user_id) INTO v_recipient;
  END IF;

  IF v_recipient IS NOT NULL THEN
    SELECT display_name INTO v_guest_name FROM profiles WHERE id = auth.uid();
    -- This app has no real push infra (07-notifications.md: no device-token
    -- table, no APNs key) — "push notification" here means the same
    -- in-app toast + bell `notifications` row every other event in this
    -- lifecycle already uses, which the toast poller surfaces proactively
    -- within one 5s cycle either way.
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_recipient, 'payment_verification_nudge', 'Khách đang chờ xác nhận',
      COALESCE(NULLIF(v_guest_name, ''), 'Một khách') || ' nhắc bạn xác nhận khoản thanh toán ▪︎ mã '
        || COALESCE(v_b.payment_ref, '') || '.',
      jsonb_build_object('booking_id', v_b.id, 'event_id', v_b.event_id, 'nudge_count', v_b.nudge_count)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'nudge_count', v_b.nudge_count);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.nudge_organizer(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.nudge_organizer(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.reject_pending_guest(p_booking uuid, p_reason text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_ev events%ROWTYPE;
  v_authorized boolean;
  v_thread_id uuid;
  v_clean_reason text := left(trim(COALESCE(p_reason, '')), 400);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT * INTO v_ev FROM events WHERE id = v_b.event_id;

  SELECT EXISTS(
    SELECT 1 FROM organizers o
    WHERE o.id = v_ev.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) INTO v_authorized;
  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- Only a still-open request can be rejected — an already-confirmed,
  -- already-cancelled, or already-disputed booking has moved past this
  -- decision entirely (a confirmed guest is handled via "Huỷ vé" instead,
  -- which already exists and already asks for a reason).
  IF v_b.payment_state NOT IN ('holding', 'pending_verification') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_b.payment_state);
  END IF;

  UPDATE bookings SET
    status = 'cancelled',
    payment_state = 'cancelled',
    cancelled_at = now(),
    cancelled_by = auth.uid(),
    cancel_reason = v_clean_reason,
    hold_expires_at = NULL,
    verify_due_at = NULL
  WHERE id = p_booking
  RETURNING * INTO v_b;

  PERFORM log_payment_event(
    p_booking, 'T_organizer_rejected', 'pending_verification', 'cancelled',
    auth.uid(), 'organizer', NULL, NULL,
    jsonb_build_object('reason', v_clean_reason)
  );

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Người tổ chức không nhận yêu cầu đặt chỗ này'
            || COALESCE(': ' || NULLIF(v_clean_reason, ''), '')
            || '. Chỗ đã được mở lại cho người khác.',
            'system');
  END IF;

  IF v_b.user_id IS NOT NULL THEN
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_b.user_id, 'booking_declined', 'Yêu cầu đặt chỗ không được nhận',
      COALESCE(v_ev.name, 'Sự kiện') || ' đã từ chối yêu cầu đặt chỗ của bạn.'
        || CASE WHEN v_clean_reason <> '' THEN ' Lý do: ' || v_clean_reason ELSE '' END,
      jsonb_build_object('event_id', v_b.event_id, 'booking_id', v_b.id, 'reason', v_clean_reason)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'booking_id', p_booking);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.reject_pending_guest(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reject_pending_guest(uuid, text) TO authenticated;
