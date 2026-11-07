-- 173: reservation uses the buyer's profile birthday + optional email per attendee.
--  * Ticket 1 (the person who taps Reserve) may send use_profile_dob=true; the
--    server copies the birthday from user_private_dob, so it never reaches the client.
--  * Each attendee may carry an optional email (stored on booking_attendees.email,
--    readable only by the buyer/admin under the existing select policy).
--  * my_dob_on_file(): boolean only, so the form knows whether to hide the date picker.

ALTER TABLE public.booking_attendees ADD COLUMN IF NOT EXISTS email text;

CREATE OR REPLACE FUNCTION public.my_dob_on_file()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_private_dob WHERE user_id = auth.uid());
$$;
REVOKE ALL ON FUNCTION public.my_dob_on_file() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_dob_on_file() TO authenticated;

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
  v_emails text[] := '{}';
  v_email text;
  v_profile_dob date;
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
    -- The buyer's own ticket can take the birthday already on their profile
    -- (it never leaves the server) instead of a typed one.
    IF COALESCE((v_item->>'use_profile_dob')::boolean, false) THEN
      SELECT date_of_birth INTO v_profile_dob FROM public.user_private_dob WHERE user_id = auth.uid();
      v_dob := v_profile_dob;
    ELSE
      BEGIN
        v_dob := (v_item->>'dob')::date;
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'INVALID_ATTENDEE_DOB';
      END;
    END IF;
    IF v_dob IS NULL OR v_dob > current_date OR v_dob < current_date - interval '120 years' THEN
      RAISE EXCEPTION 'INVALID_ATTENDEE_DOB';
    END IF;
    -- Optional email, so the buyer can note who each ticket is for.
    v_email := lower(btrim(COALESCE(v_item->>'email', '')));
    IF v_email <> '' AND (char_length(v_email) > 254 OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') THEN
      RAISE EXCEPTION 'INVALID_ATTENDEE_EMAIL';
    END IF;
    v_emails := v_emails || NULLIF(v_email, '');
    v_names := v_names || v_name;
    v_dobs := v_dobs || v_dob;
  END LOOP;

  v_booking := public.hold_seats(p_event, v_n, p_note, p_ip, p_user_agent);
  v_code := COALESCE(NULLIF(v_booking.code, ''), upper(left(replace(v_booking.id::text, '-', ''), 6)));

  FOR i IN 1..v_n LOOP
    INSERT INTO booking_attendees (booking_id, event_id, seat_no, name, date_of_birth, ticket_code, email)
    VALUES (v_booking.id, v_booking.event_id, i, v_names[i], v_dobs[i], v_code || '-' || i, v_emails[i]);
  END LOOP;

  RETURN v_booking;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.hold_seats_with_attendees(text, jsonb, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.hold_seats_with_attendees(text, jsonb, text, text, text) TO authenticated;
