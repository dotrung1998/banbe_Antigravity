-- 227 — the door admits a PAID seat, never a 30-minute hold.
--
-- Audit 2026-11-19 row 9 (P2). hold_seats (219) writes status='confirmed' for approval='instant' while payment_state is
-- still 'holding' — the seat is confirmed, the money is not. Every check-in path gated on `status IN
-- ('confirmed','attended')` alone, so an unpaid hold (or a pending transfer) could be scanned in at the door and counted
-- as attended:
--   * check_in_guest (212) — the admission itself,
--   * project_checkin_lookup (212) — the scanner's "who is this" answer,
--   * get_event_checkin_names (212) — the host's door list.
-- Fix: all three now require payment_state = 'confirmed' as well. check_in_guest is enforced at the write that makes an
-- admission (a BEFORE INSERT trigger on check_ins), which also covers any future check-in path; the two lookups filter
-- the same way so the list and the scanner never offer someone the door will refuse.
--
-- Free events are unaffected: hold_seats sets payment_state='confirmed' for them immediately. Legacy rows were
-- backfilled by migration 030.
--
-- Rollback: supabase/rollbacks/20261231000227_227_revert_checkin_requires_payment.sql
-- Tests: supabase/tests/227_checkin_payment/run.sh (throwaway stack only).

CREATE OR REPLACE FUNCTION public.check_ins_guard_payment()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE v_state public.payment_state;
BEGIN
  IF NEW.booking_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT b.payment_state INTO v_state FROM public.bookings b WHERE b.id = NEW.booking_id;
  IF v_state IS DISTINCT FROM 'confirmed' THEN
    RAISE EXCEPTION 'PAYMENT_NOT_CONFIRMED';
  END IF;
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.check_ins_guard_payment() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS check_ins_guard_payment ON public.check_ins;
CREATE TRIGGER check_ins_guard_payment
  BEFORE INSERT ON public.check_ins
  FOR EACH ROW
  EXECUTE FUNCTION public.check_ins_guard_payment();

-- The host's door list: paid seats only.
CREATE OR REPLACE FUNCTION public.get_event_checkin_names(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.can_event_capability(p_event_id, 'checkin') THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  RETURN jsonb_build_object('success', true, 'guests', coalesce((SELECT jsonb_agg(g ORDER BY g->>'name', g->>'booking_id') FROM (
      SELECT jsonb_build_object('booking_id', b.id, 'attendee_id', a.id, 'name', a.name, 'party', 1, 'checked_in', a.checked_in_at IS NOT NULL) g
        FROM bookings b JOIN booking_attendees a ON a.booking_id = b.id
       WHERE b.event_id = p_event_id AND b.status IN ('confirmed', 'attended') AND b.payment_state = 'confirmed'
      UNION ALL
      SELECT jsonb_build_object('booking_id', b.id, 'attendee_id', NULL,
               'name', coalesce(nullif(b.recipient_name, ''), nullif(pr.display_name, ''), '—'), 'party', b.qty, 'checked_in', b.status = 'attended')
        FROM bookings b LEFT JOIN profiles pr ON pr.id = b.user_id
       WHERE b.event_id = p_event_id AND b.status IN ('confirmed', 'attended') AND b.payment_state = 'confirmed'
         AND NOT EXISTS (SELECT 1 FROM booking_attendees a WHERE a.booking_id = b.id)) t), '[]'::jsonb));
END;
$$;

-- The scanner's answer: a booking that is not paid is NOT_ELIGIBLE, same as a cancelled one.
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
  IF v_b.status NOT IN ('confirmed', 'attended') OR v_b.payment_state IS DISTINCT FROM 'confirmed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_ELIGIBLE');
  END IF;
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

REVOKE ALL ON FUNCTION public.get_event_checkin_names(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.project_checkin_lookup(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_event_checkin_names(text), public.project_checkin_lookup(uuid) TO authenticated;
