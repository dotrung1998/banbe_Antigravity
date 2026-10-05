-- Migration 151: one named ticket per attendee.
--
-- A purchase of up to six tickets now records WHO each ticket is for (name +
-- date of birth) and gives each attendee their own admission QR and entry code,
-- so each can be downloaded and scanned on its own. Payment is unchanged and
-- still lives on the single booking row.
--
-- Pieces:
--   1. booking_attendees   — one row per attendee, with its own admission_token.
--   2. hold_seats_with_attendees() — validates the attendee list, calls the
--      existing hold_seats() and inserts the rows in ONE transaction, so a
--      booking can never exist half-named. hold_seats() itself is untouched.
--   3. get_checkin_guest_info() / check_in_guest() — a scanned attendee token
--      admits that one attendee; the booking becomes 'attended' on the first.
--   4. A guard stopping gifting/splitting a booking that has named attendees
--      (each attendee's PDF is already a per-person ticket).
--
-- Bookings made before this migration have no attendee rows and keep working
-- exactly as before (booking-level QR / check-in).

-- ============ 1. booking_attendees ============
CREATE TABLE IF NOT EXISTS public.booking_attendees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  event_id text NOT NULL,
  seat_no int NOT NULL CHECK (seat_no BETWEEN 1 AND 6),
  name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 2 AND 120),
  date_of_birth date NOT NULL,
  -- What this attendee's QR encodes. Never the booking id: leaking one PDF
  -- must admit one person, not the whole party.
  admission_token uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  ticket_code text NOT NULL,
  checked_in_at timestamptz,
  checked_in_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (booking_id, seat_no),
  UNIQUE (ticket_code)
);
CREATE INDEX IF NOT EXISTS idx_booking_attendees_booking ON public.booking_attendees(booking_id);

ALTER TABLE public.booking_attendees ENABLE ROW LEVEL SECURITY;

-- The buyer (and the account the booking sits on) can read their own party.
-- Hosts deliberately get NO direct read: a date of birth reaches a host only
-- through get_checkin_guest_info(), which is rate-limited and logged.
DROP POLICY IF EXISTS booking_attendees_select ON public.booking_attendees;
CREATE POLICY booking_attendees_select ON public.booking_attendees FOR SELECT TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.bookings b
          WHERE b.id = booking_attendees.booking_id
            AND (b.user_id = auth.uid() OR b.purchaser_id = auth.uid()))
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
);
-- No INSERT/UPDATE/DELETE policy: every write goes through a SECURITY DEFINER RPC.

-- ============ 2. hold_seats_with_attendees ============
CREATE OR REPLACE FUNCTION public.hold_seats_with_attendees(
  p_event text, p_attendees jsonb, p_note text DEFAULT NULL,
  p_ip text DEFAULT NULL, p_user_agent text DEFAULT NULL
)
RETURNS bookings
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_n int;
  v_item jsonb;
  v_name text;
  v_dob date;
  v_booking bookings%ROWTYPE;
  v_code text;
  i int := 0;
  v_names text[] := '{}';
  v_dobs date[] := '{}';
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_attendees IS NULL OR jsonb_typeof(p_attendees) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_ATTENDEES';
  END IF;
  v_n := jsonb_array_length(p_attendees);
  IF v_n < 1 OR v_n > 6 THEN RAISE EXCEPTION 'INVALID_QTY'; END IF;

  -- Validate everything BEFORE holding anything.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_attendees) LOOP
    v_name := btrim(COALESCE(v_item->>'name', ''));
    IF char_length(v_name) < 2 OR char_length(v_name) > 120 THEN
      RAISE EXCEPTION 'INVALID_ATTENDEE_NAME';
    END IF;
    BEGIN
      v_dob := (v_item->>'dob')::date;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'INVALID_ATTENDEE_DOB';
    END;
    IF v_dob IS NULL OR v_dob > current_date OR v_dob < current_date - interval '120 years' THEN
      RAISE EXCEPTION 'INVALID_ATTENDEE_DOB';
    END IF;
    v_names := v_names || v_name;
    v_dobs := v_dobs || v_dob;
  END LOOP;

  v_booking := public.hold_seats(p_event, v_n, p_note, p_ip, p_user_agent);
  v_code := COALESCE(NULLIF(v_booking.code, ''), upper(left(replace(v_booking.id::text, '-', ''), 6)));

  FOR i IN 1..v_n LOOP
    INSERT INTO booking_attendees (booking_id, event_id, seat_no, name, date_of_birth, ticket_code)
    VALUES (v_booking.id, v_booking.event_id, i, v_names[i], v_dobs[i], v_code || '-' || i);
  END LOOP;

  RETURN v_booking;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.hold_seats_with_attendees(text, jsonb, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.hold_seats_with_attendees(text, jsonb, text, text, text) TO authenticated;

-- ============ 3. Gifting/splitting is refused for named-attendee bookings ============
-- gift_ticket() either shrinks qty (multi-seat split) or stamps gifted_at
-- (single seat). Either would leave booking_attendees describing people who no
-- longer match the booking, so both are refused at the row.
CREATE OR REPLACE FUNCTION public.guard_named_attendee_booking()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.booking_attendees WHERE booking_id = NEW.id) THEN
    RAISE EXCEPTION 'BOOKING_HAS_NAMED_ATTENDEES';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS bookings_guard_named_attendees ON public.bookings;
CREATE TRIGGER bookings_guard_named_attendees
BEFORE UPDATE ON public.bookings
FOR EACH ROW
WHEN (NEW.qty < OLD.qty OR NEW.gifted_at IS DISTINCT FROM OLD.gifted_at)
EXECUTE FUNCTION public.guard_named_attendee_booking();

-- ============ 4. Check-in: a scanned attendee token admits ONE attendee ============
-- Both functions are migration 133's, with an attendee branch in front.

CREATE OR REPLACE FUNCTION public.get_checkin_guest_info(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_booking public.bookings%ROWTYPE;
  v_org text;
  v_allowed boolean;
  v_name text;
  v_dob date;
  v_att public.booking_attendees%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED');
  END IF;

  -- An attendee's own QR resolves to that attendee (migration 151).
  SELECT * INTO v_att FROM public.booking_attendees WHERE admission_token = p_booking_id;
  IF FOUND THEN
    SELECT * INTO v_booking FROM public.bookings WHERE id = v_att.booking_id;
  ELSE
    -- Match either primary ID or admission_token
    SELECT * INTO v_booking FROM public.bookings
    WHERE id = p_booking_id OR admission_token = p_booking_id;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  -- OLD-QR REJECTION:
  -- If ticket was gifted and the scanned credential is NOT the new admission_token
  IF v_att.id IS NULL
     AND v_booking.recipient_name IS NOT NULL
     AND v_booking.admission_token IS NOT NULL
     AND p_booking_id != v_booking.admission_token THEN
    RETURN jsonb_build_object('success', false, 'error', 'CREDENTIAL_INVALIDATED');
  END IF;

  SELECT e.organizer_id INTO v_org FROM public.events e WHERE e.id = v_booking.event_id;

  v_allowed := (v_org IS NOT NULL AND public.is_promo_host(v_org, v_uid))
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'admin');
  IF NOT v_allowed THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  IF v_booking.status NOT IN ('confirmed', 'attended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_ELIGIBLE');
  END IF;

  IF (SELECT count(*) FROM public.checkin_dob_views
       WHERE host_id = v_uid AND viewed_at > now() - interval '1 hour') >= 300 THEN
    RETURN jsonb_build_object('success', false, 'error', 'RATE_LIMITED');
  END IF;

  -- Attendee name and date of birth: use recipient details for gifted tickets
  IF v_att.id IS NOT NULL THEN
    v_name := v_att.name;
    v_dob := v_att.date_of_birth;
  ELSIF v_booking.recipient_name IS NOT NULL THEN
    v_name := v_booking.recipient_name;
    v_dob := v_booking.recipient_dob;
  ELSE
    SELECT nullif(p.display_name, '') INTO v_name FROM public.profiles p WHERE p.id = v_booking.user_id;
    SELECT d.date_of_birth INTO v_dob FROM public.user_private_dob d WHERE d.user_id = v_booking.user_id;
  END IF;

  INSERT INTO public.checkin_dob_views (host_id, booking_id, guest_id)
  VALUES (v_uid, v_booking.id, v_booking.user_id);

  RETURN jsonb_build_object(
    'success', true,
    'booking_id', v_booking.id,
    'status', v_booking.status,
    'name', coalesce(v_name, ''),
    'date_of_birth', v_dob,
    'attendee_id', v_att.id,
    'already_checked_in', v_att.checked_in_at IS NOT NULL
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_checkin_guest_info(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_checkin_guest_info(uuid) TO authenticated;

-- ============ 7. Update check_in_guest ============
-- p_source separates the two callers that both resolve a booking by uuid:
--   'scan'  — the value came out of a ticket QR, so the admission-credential
--              rule below applies and a superseded QR is refused.
--   'manual'— the host tapped a row in their OWN guest list for their OWN
--              event. Not a credential at all, so it must not be caught by
--              that rule: a gifted row's id IS still how the list addresses
--              it, and refusing it would make the recipient impossible to
--              admit by hand.
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
