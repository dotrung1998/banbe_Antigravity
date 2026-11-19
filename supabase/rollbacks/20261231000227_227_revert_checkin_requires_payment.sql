BEGIN;

DROP TRIGGER IF EXISTS check_ins_guard_payment ON public.check_ins;
DROP FUNCTION IF EXISTS public.check_ins_guard_payment();

-- The two lookups return to 212's bodies (status only).
CREATE OR REPLACE FUNCTION public.get_event_checkin_names(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.can_event_capability(p_event_id, 'checkin') THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  RETURN jsonb_build_object('success', true, 'guests', coalesce((SELECT jsonb_agg(g ORDER BY g->>'name', g->>'booking_id') FROM (
      SELECT jsonb_build_object('booking_id', b.id, 'attendee_id', a.id, 'name', a.name, 'party', 1, 'checked_in', a.checked_in_at IS NOT NULL) g
        FROM bookings b JOIN booking_attendees a ON a.booking_id = b.id
       WHERE b.event_id = p_event_id AND b.status IN ('confirmed', 'attended')
      UNION ALL
      SELECT jsonb_build_object('booking_id', b.id, 'attendee_id', NULL,
               'name', coalesce(nullif(b.recipient_name, ''), nullif(pr.display_name, ''), '—'), 'party', b.qty, 'checked_in', b.status = 'attended')
        FROM bookings b LEFT JOIN profiles pr ON pr.id = b.user_id
       WHERE b.event_id = p_event_id AND b.status IN ('confirmed', 'attended')
         AND NOT EXISTS (SELECT 1 FROM booking_attendees a WHERE a.booking_id = b.id)) t), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.project_checkin_lookup(p_code uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_att booking_attendees%ROWTYPE; v_b bookings%ROWTYPE; v_name text; v_dob date; v_min int; v_age int;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT * INTO v_att FROM booking_attendees WHERE admission_token = p_code;
  IF FOUND THEN SELECT * INTO v_b FROM bookings WHERE id = v_att.booking_id;
  ELSE SELECT * INTO v_b FROM bookings WHERE id = p_code OR admission_token = p_code; END IF;
  IF v_b.id IS NULL OR NOT public.can_event_capability(v_b.event_id, 'checkin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;
  IF v_att.id IS NULL AND v_b.recipient_name IS NOT NULL AND v_b.admission_token IS NOT NULL AND p_code <> v_b.admission_token THEN
    RETURN jsonb_build_object('success', false, 'error', 'CREDENTIAL_INVALIDATED');
  END IF;
  IF v_b.status NOT IN ('confirmed', 'attended') THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_ELIGIBLE'); END IF;
  IF v_att.id IS NOT NULL THEN v_name := v_att.name; v_dob := v_att.date_of_birth;
  ELSIF v_b.recipient_name IS NOT NULL THEN v_name := v_b.recipient_name; v_dob := v_b.recipient_dob;
  ELSE
    SELECT nullif(p.display_name, '') INTO v_name FROM profiles p WHERE p.id = v_b.user_id;
    SELECT d.date_of_birth INTO v_dob FROM user_private_dob d WHERE d.user_id = v_b.user_id;
  END IF;
  SELECT nullif(e.details ->> 'min_age', '')::int INTO v_min FROM events e WHERE e.id = v_b.event_id;
  v_age := CASE WHEN v_dob IS NULL THEN NULL ELSE extract(year FROM age(current_date, v_dob))::int END;
  RETURN jsonb_build_object('success', true, 'booking_id', v_b.id, 'attendee_id', v_att.id, 'name', coalesce(v_name, ''),
    'already_checked_in', CASE WHEN v_att.id IS NOT NULL THEN v_att.checked_in_at IS NOT NULL ELSE v_b.status = 'attended' END,
    'min_age', v_min, 'meets_min_age', CASE WHEN v_min IS NULL THEN NULL WHEN v_age IS NULL THEN false ELSE v_age >= v_min END);
END;
$$;

COMMIT;
