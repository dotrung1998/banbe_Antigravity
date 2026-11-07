-- Migration 125: what the host sees when scanning a goer's ticket at check-in.
--
-- The check-in popup shows the goer's NAME and DATE OF BIRTH so door staff can
-- verify age on arrival. The stored DOB is otherwise unreadable by any client
-- (migration 123), so this is ONE narrow server function:
--   * caller must pass the account gate;
--   * caller must host the booking's event (owner / accepted team member) or be
--     an admin — the same people who may call check_in_guest();
--   * the booking must be a real ticket (confirmed or already attended);
--   * every successful call is written to checkin_dob_views (audit), and a host
--     is capped at 300 lookups per hour;
--   * only name + DOB come back — never the phone, email or anything else.
-- A goer with no DOB on file (legacy account) simply returns null.

CREATE TABLE IF NOT EXISTS public.checkin_dob_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  booking_id uuid NOT NULL,
  guest_id uuid,
  viewed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_checkin_dob_views_host ON public.checkin_dob_views (host_id, viewed_at);
ALTER TABLE public.checkin_dob_views ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.checkin_dob_views FROM anon, authenticated;

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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED');
  END IF;

  SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;
  SELECT e.organizer_id INTO v_org FROM public.events e WHERE e.id = v_booking.event_id;

  v_allowed := (v_org IS NOT NULL AND public.is_promo_host(v_org, v_uid))
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'admin');
  IF NOT v_allowed THEN
    -- Same answer as "no such booking": don't confirm a ticket exists.
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  IF v_booking.status NOT IN ('confirmed', 'attended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_ELIGIBLE');
  END IF;

  IF (SELECT count(*) FROM public.checkin_dob_views
       WHERE host_id = v_uid AND viewed_at > now() - interval '1 hour') >= 300 THEN
    RETURN jsonb_build_object('success', false, 'error', 'RATE_LIMITED');
  END IF;

  SELECT nullif(p.display_name, '') INTO v_name FROM public.profiles p WHERE p.id = v_booking.user_id;
  SELECT d.date_of_birth INTO v_dob FROM public.user_private_dob d WHERE d.user_id = v_booking.user_id;

  INSERT INTO public.checkin_dob_views (host_id, booking_id, guest_id)
  VALUES (v_uid, v_booking.id, v_booking.user_id);

  RETURN jsonb_build_object(
    'success', true,
    'status', v_booking.status,
    'name', coalesce(v_name, ''),
    'date_of_birth', v_dob   -- ISO "YYYY-MM-DD" or null
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_checkin_guest_info(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_checkin_guest_info(uuid) TO authenticated;
