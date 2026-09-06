-- Migration: RPC Functions for Booking, Host Management, and Check-ins

-- 1. claim_seats
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

-- 2. create_event_draft
CREATE OR REPLACE FUNCTION create_event_draft(
  p_name text, p_category text, p_description text, p_location text,
  p_event_date date, p_event_time time, p_price_vnd bigint, p_capacity int,
  p_organizer_name text, p_instagram text DEFAULT '', p_about text DEFAULT ''
) RETURNS events LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer organizers%ROWTYPE;
  v_event events%ROWTYPE;
  v_org_id text;
  v_event_id text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 OR p_capacity IS NULL OR p_capacity < 1 THEN RAISE EXCEPTION 'INVALID_EVENT'; END IF;

  UPDATE profiles SET role = CASE WHEN role = 'participant' OR role = 'goer' THEN 'organizer' ELSE role END WHERE id = auth.uid();

  SELECT * INTO v_organizer FROM organizers WHERE owner_id = auth.uid() OR user_id = auth.uid() ORDER BY created_at LIMIT 1;
  IF NOT FOUND THEN
    v_org_id := 'org_' || substr(md5(gen_random_uuid()::text), 1, 8);
    INSERT INTO organizers(id, owner_id, user_id, name, ig_handle, instagram, bio, about)
    VALUES (v_org_id, auth.uid(), auth.uid(), COALESCE(NULLIF(trim(p_organizer_name), ''), 'Organizer'), p_instagram, p_instagram, p_about, p_about)
    RETURNING * INTO v_organizer;
  ELSE
    UPDATE organizers SET name = COALESCE(NULLIF(trim(p_organizer_name), ''), name), instagram = COALESCE(p_instagram, instagram), about = COALESCE(p_about, about) WHERE id = v_organizer.id;
  END IF;

  v_event_id := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(md5(gen_random_uuid()::text), 1, 6);

  INSERT INTO events(id, key, slug, organizer_id, name, category, cat_key, cat_label, description, price_vnd, price_cents, capacity, seats_remaining, area, event_date, event_time, status, approval, visibility)
  VALUES (
    v_event_id,
    v_event_id,
    v_event_id,
    v_organizer.id,
    trim(p_name),
    p_category,
    p_category,
    p_category,
    COALESCE(p_description, ''),
    COALESCE(p_price_vnd, 0),
    COALESCE(p_price_vnd, 0) * 100,
    p_capacity,
    p_capacity,
    COALESCE(p_location, ''),
    p_event_date,
    p_event_time,
    'live',
    'host_approves',
    'public'
  )
  RETURNING * INTO v_event;

  RETURN v_event;
END;
$$;
REVOKE EXECUTE ON FUNCTION create_event_draft FROM anon;
GRANT EXECUTE ON FUNCTION create_event_draft TO authenticated;

-- 3. check_in_guest
CREATE OR REPLACE FUNCTION check_in_guest(p_reservation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_is_host boolean;
  v_is_admin boolean;
  v_checkin_id uuid;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_reservation_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
  END IF;

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

  INSERT INTO check_ins (booking_id, reservation_id, event_id, checked_in_by)
  VALUES (v_booking.id, v_booking.id, v_booking.event_id, auth.uid())
  ON CONFLICT (booking_id) DO NOTHING
  RETURNING id INTO v_checkin_id;

  IF v_checkin_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Guest already checked in');
  END IF;

  UPDATE bookings SET status = 'attended' WHERE id = v_booking.id;
  IF v_booking.user_id IS NOT NULL THEN
    UPDATE profiles SET attended_count = COALESCE(attended_count, 0) + 1 WHERE id = v_booking.user_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'booking_id', v_booking.id);
END;
$$;
REVOKE EXECUTE ON FUNCTION check_in_guest FROM anon;
GRANT EXECUTE ON FUNCTION check_in_guest TO authenticated;

-- 4. check_in (code or uuid)
CREATE OR REPLACE FUNCTION check_in(p_code_or_id text, p_no_show boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_is_authorized boolean;
  v_checkin_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT b.* INTO v_booking
  FROM bookings b
  WHERE (b.code = upper(trim(p_code_or_id)))
     OR (b.id::text = trim(p_code_or_id))
  LIMIT 1;

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

  IF v_booking.status NOT IN ('confirmed', 'attended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_CONFIRMED');
  END IF;

  IF p_no_show THEN
    UPDATE bookings SET status = 'no_show' WHERE id = v_booking.id;
    IF v_booking.user_id IS NOT NULL THEN
      UPDATE profiles SET no_show_count = COALESCE(no_show_count, 0) + 1 WHERE id = v_booking.user_id;
    END IF;
  ELSE
    UPDATE bookings SET status = 'attended' WHERE id = v_booking.id;
    INSERT INTO check_ins (booking_id, reservation_id, event_id, checked_in_by)
    VALUES (v_booking.id, v_booking.id, v_booking.event_id, auth.uid())
    ON CONFLICT (booking_id) DO NOTHING;
    IF v_booking.user_id IS NOT NULL THEN
      UPDATE profiles SET attended_count = COALESCE(attended_count, 0) + 1 WHERE id = v_booking.user_id;
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'booking_id', v_booking.id);
END;
$$;
REVOKE EXECUTE ON FUNCTION check_in FROM anon;
GRANT EXECUTE ON FUNCTION check_in TO authenticated;
