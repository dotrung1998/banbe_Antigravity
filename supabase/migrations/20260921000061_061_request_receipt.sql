-- .claude/notes/15-organizer-checkin.md follow-up (Bug 2):
--
-- request_receipt() — the guest's "Xem Receipt" button on Confirmed.jsx/
-- ConfirmedView.swift (the QR ticket screen), for the case where no
-- payment_documents receipt exists yet (08-payment-documents.md: receipts
-- are organizer-uploaded now, upload_payment_document(), not auto-issued —
-- there is no guarantee one exists the moment a booking is confirmed).
-- Modeled on nudge_organizer() (059): guest-only, a real cooldown column
-- rather than client-side debouncing (a determined guest could otherwise
-- spam the organizer's bell every time they reopen the ticket screen),
-- and the same in-app toast + bell `notifications` row this app always
-- uses in place of real push (07-notifications.md).
--
-- Deep-links the organizer straight into Check-in (Attendance.jsx/
-- AttendanceView.swift) for the exact event — openNotification()'s new
-- 'receipt_requested' branch also stashes the booking id so that guest's
-- own "Upload receipt" row can be auto-scrolled-to and highlighted,
-- mirroring the chatHighlight scroll/flash pattern DisputeChatPanel.jsx
-- already uses (07-notifications.md, 2026-09-16 entry) — the organizer
-- shouldn't have to hunt for one guest in a long list.

ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS receipt_requested_at timestamptz;

CREATE OR REPLACE FUNCTION public.request_receipt(p_booking uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_ev events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_recipient uuid;
  v_guest_name text;
  v_has_receipt boolean;
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

  -- Nothing to request before the organizer has even accepted the booking.
  IF v_b.payment_state != 'confirmed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_b.payment_state);
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM payment_documents
    WHERE booking_id = p_booking AND kind = 'receipt' AND superseded_at IS NULL
  ) INTO v_has_receipt;
  IF v_has_receipt THEN
    RETURN jsonb_build_object('success', false, 'error', 'RECEIPT_ALREADY_EXISTS');
  END IF;

  -- Real cooldown, not client debouncing — 30 minutes, generous enough
  -- that a guest re-checking soon after asking isn't blocked, but a
  -- reopened ticket screen can't re-notify the organizer every time.
  IF v_b.receipt_requested_at IS NOT NULL AND v_b.receipt_requested_at > now() - interval '30 minutes' THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_REQUESTED_RECENTLY',
                              'receipt_requested_at', v_b.receipt_requested_at);
  END IF;

  UPDATE bookings SET receipt_requested_at = now() WHERE id = p_booking RETURNING * INTO v_b;

  SELECT * INTO v_ev FROM events WHERE id = v_b.event_id;
  IF v_ev.organizer_id IS NOT NULL THEN
    SELECT * INTO v_org FROM organizers WHERE id = v_ev.organizer_id;
    SELECT COALESCE(v_org.owner_id, v_org.user_id) INTO v_recipient;
  END IF;

  IF v_recipient IS NOT NULL THEN
    SELECT display_name INTO v_guest_name FROM profiles WHERE id = auth.uid();
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_recipient, 'receipt_requested', 'Khách yêu cầu biên nhận',
      COALESCE(NULLIF(v_guest_name, ''), 'Một khách') || ' đang chờ biên nhận cho khoản đã thanh toán ▪︎ mã '
        || COALESCE(v_b.payment_ref, '') || '.',
      jsonb_build_object('booking_id', v_b.id, 'event_id', v_b.event_id)
    );
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.request_receipt(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.request_receipt(uuid) TO authenticated;
