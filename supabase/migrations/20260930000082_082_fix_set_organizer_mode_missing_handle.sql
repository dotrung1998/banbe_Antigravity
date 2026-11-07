-- Migration: fix the SECOND place a `profiles` INSERT omitted `handle`.
--
-- Migration 081 fixed `handle_new_user()`, but missed that
-- `set_organizer_mode()` (migration 017) ALSO does its own defensive
-- `INSERT ... ON CONFLICT (id) DO NOTHING` (a belt-and-suspenders guard for
-- an account whose profiles row somehow doesn't exist yet), and it too
-- never listed `handle`.
--
-- This is the actual, full explanation for why the organizer-toggle error
-- kept reproducing even after 081 backfilled the affected row and fixed
-- `handle_new_user()`: Postgres validates NOT NULL constraints while
-- building the proposed tuple for an INSERT, which happens BEFORE the
-- ON CONFLICT clause is evaluated — so this INSERT raised the exact same
-- `23502 null value in column "handle"` error on EVERY SINGLE call to
-- `set_organizer_mode()`, for every account, even ones whose row already
-- existed and already had a real handle (079's backfill made that no
-- longer visible for MOST accounts' OTHER reads/writes, but this one
-- specific RPC's own redundant INSERT tuple was built from scratch each
-- call and never had a handle value to give it, so it failed regardless of
-- what was already stored in the table).

CREATE OR REPLACE FUNCTION public.set_organizer_mode(p_enabled boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  INSERT INTO public.profiles (id, display_name, phone, locale, role, handle)
  VALUES (auth.uid(), '', '', 'vi', 'participant', left('u' || replace(auth.uid()::text, '-', ''), 13))
  ON CONFLICT (id) DO NOTHING;

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
  IF v_role = 'admin' THEN RETURN v_role; END IF;

  v_role := CASE WHEN p_enabled THEN 'organizer' ELSE 'participant' END;

  PERFORM set_config('app.role_change_allowed', '1', true);
  UPDATE public.profiles SET role = v_role WHERE id = auth.uid();
  PERFORM set_config('app.role_change_allowed', '0', true);

  UPDATE public.email_registrations
  SET role = v_role, updated_at = now()
  WHERE auth_user_id = auth.uid();

  RETURN v_role;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_organizer_mode(boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_organizer_mode(boolean) TO authenticated;
