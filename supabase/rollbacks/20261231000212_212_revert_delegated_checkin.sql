-- Revert 212: delegated check-in off for good. Puts check_in_guest back exactly as migration 151 defined it, drops the
-- delegate helpers and RPCs. The event_money_audit table is KEPT on purpose (its rows follow the booking, not the
-- feature); drop it by hand only if no delegated action was ever recorded.
DROP FUNCTION IF EXISTS public.get_event_checkin_names(text);
DROP FUNCTION IF EXISTS public.project_checkin_lookup(uuid);
DROP FUNCTION IF EXISTS public.project_extend_grants(text, timestamptz, uuid);

CREATE OR REPLACE FUNCTION public.check_in_guest(p_reservation_id uuid, p_source text DEFAULT 'manual')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_host boolean;
  v_is_admin boolean;
  v_checkin_id uuid;
  v_attendee uuid;
  v_att booking_attendees%ROWTYPE;
  v_has_attendees boolean;
BEGIN
  -- An attendee's own QR resolves to that attendee (migration 151).
  SELECT * INTO v_att FROM booking_attendees WHERE admission_token = p_reservation_id;
  IF FOUND THEN
    SELECT * INTO v_booking FROM bookings WHERE id = v_att.booking_id;
  ELSE
    -- Match either primary ID or admission_token
    SELECT * INTO v_booking FROM bookings
    WHERE id = p_reservation_id OR admission_token = p_reservation_id;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
  END IF;

  -- Superseded-QR rejection (scan only). gifting a single seat rotates that
  -- seat's admission_token, so a screenshot of the ticket taken beforehand no
  -- longer resolves to it.
  IF v_att.id IS NULL
     AND coalesce(p_source, 'manual') = 'scan'
     AND v_booking.recipient_name IS NOT NULL
     AND v_booking.admission_token IS NOT NULL
     AND p_reservation_id != v_booking.admission_token THEN
    RETURN jsonb_build_object('success', false, 'error', 'Credential invalidated');
  END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  SELECT EXISTS(
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_booking.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) INTO v_is_host;

  SELECT EXISTS(
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ) INTO v_is_admin;

  IF NOT v_is_host AND NOT v_is_admin THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;

  IF v_booking.status NOT IN ('confirmed', 'attended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking is not eligible for check-in');
  END IF;

  SELECT EXISTS (SELECT 1 FROM booking_attendees WHERE booking_id = v_booking.id) INTO v_has_attendees;

  IF v_att.id IS NOT NULL THEN
    -- Per-attendee admission: this one person, once.
    IF v_att.checked_in_at IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Guest already checked in');
    END IF;
    UPDATE booking_attendees SET checked_in_at = now(), checked_in_by = auth.uid()
    WHERE id = v_att.id;
  ELSIF v_has_attendees THEN
    -- A booking-level credential on a booking that has named attendees. A
    -- scanned booking id must never admit a whole party; only a host tapping
    -- their own guest list ('manual') may, and that admits everyone not yet in.
    IF coalesce(p_source, 'manual') = 'scan' THEN
      RETURN jsonb_build_object('success', false, 'error', 'Scan each attendee''s own QR');
    END IF;
    UPDATE booking_attendees SET checked_in_at = now(), checked_in_by = auth.uid()
    WHERE booking_id = v_booking.id AND checked_in_at IS NULL;
  END IF;

  -- The booking-level record is written ONCE, on the first person through.
  INSERT INTO check_ins (booking_id, reservation_id, event_id, checked_in_by)
  VALUES (v_booking.id, v_booking.id, v_booking.event_id, auth.uid())
  ON CONFLICT (booking_id) DO NOTHING
  RETURNING id INTO v_checkin_id;

  IF v_checkin_id IS NULL THEN
    IF v_att.id IS NOT NULL THEN
      -- Not the first attendee: admitted, nothing else to stamp or notify.
      RETURN jsonb_build_object('success', true, 'booking_id', v_booking.id, 'name', v_att.name);
    END IF;
    RETURN jsonb_build_object('success', false, 'error', 'Guest already checked in');
  END IF;

  UPDATE bookings SET status = 'attended' WHERE id = v_booking.id;

  -- Attendance counts for the person who actually walked through the door:
  -- the claiming recipient once they have imported it, otherwise whoever the
  -- account on the row is. Purchaser's attended_count must not rise for a
  -- seat they handed over.
  v_attendee := coalesce(v_booking.claimed_by_user_id, v_booking.user_id);
  IF v_attendee IS NOT NULL AND v_attendee <> v_booking.purchaser_id THEN
    UPDATE profiles SET attended_count = COALESCE(attended_count, 0) + 1 WHERE id = v_attendee;
  END IF;

  IF v_attendee IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_attendee,
      'checked_in',
      'Bạn đã được điểm danh',
      COALESCE(v_event.name, 'Sự kiện') || ' vừa xác nhận bạn đã có mặt.',
      jsonb_build_object('event_id', v_booking.event_id, 'booking_id', v_booking.id)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'booking_id', v_booking.id,
    'name', COALESCE(v_att.name, v_booking.recipient_name, '')
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.check_in_guest(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.check_in_guest(uuid, text) TO authenticated;

DROP FUNCTION IF EXISTS public.can_event_capability(text, text);
DROP FUNCTION IF EXISTS public.project_delegate_ok(text, text);
DROP FUNCTION IF EXISTS public.project_grant_end(text, public.event_project_members);
DROP FUNCTION IF EXISTS public.event_money_audit_add(text, uuid, uuid, text, text);
UPDATE public.app_feature_flag_defs SET description = 'Event Project Hub: team members with check-in access may check guests in (needs 212)'
 WHERE key = 'project_delegate_checkin';
