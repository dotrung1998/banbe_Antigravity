-- 103: Account regression fix pass (2026-09-27), Item 3 — an admin
-- account's organizer-mode (host UI) toggle was silently a no-op:
-- set_organizer_mode()'s own `IF v_role = 'admin' THEN RETURN v_role; END
-- IF;` returned immediately, before ever touching anything, whenever the
-- caller's role was 'admin' — no error, just nothing happening, which is
-- exactly "the switch looks stuck on and every tap does nothing."
--
-- Root cause: `profiles.role` was doing double duty as BOTH the
-- account's real authorization level (participant/organizer/admin) AND,
-- for a non-admin, the host-UI preference (role flips between
-- 'organizer'/'participant' on every toggle). For an admin those two
-- concepts collide — flipping `role` away from 'admin' would be a real,
-- unacceptable authorization change, so the RPC just refused to do
-- anything at all instead. Fixed by giving the preference its OWN column
-- (`organizer_mode_enabled`), so an admin's role never moves and their
-- host-UI preference persists independently. Also switches the RPC's
-- return shape from bare `text` (role only) to jsonb (role +
-- organizer_mode), since a bare role string alone can no longer describe
-- "admin, but host UI off."

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS organizer_mode_enabled boolean NOT NULL DEFAULT true;

DROP FUNCTION IF EXISTS public.set_organizer_mode(boolean);

CREATE OR REPLACE FUNCTION public.set_organizer_mode(p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  INSERT INTO public.profiles (id, display_name, phone, locale, role, handle)
  VALUES (auth.uid(), '', '', 'vi', 'participant', left('u' || replace(auth.uid()::text, '-', ''), 13))
  ON CONFLICT (id) DO NOTHING;

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();

  IF v_role = 'admin' THEN
    -- The admin's role never changes here — only their own separate
    -- host-UI preference does. This is the actual fix: previously this
    -- branch returned without writing anything at all.
    UPDATE public.profiles SET organizer_mode_enabled = p_enabled WHERE id = auth.uid();
    RETURN jsonb_build_object('role', v_role, 'organizer_mode', p_enabled);
  END IF;

  v_role := CASE WHEN p_enabled THEN 'organizer' ELSE 'participant' END;

  PERFORM set_config('app.role_change_allowed', '1', true);
  UPDATE public.profiles SET role = v_role, organizer_mode_enabled = p_enabled WHERE id = auth.uid();
  PERFORM set_config('app.role_change_allowed', '0', true);

  UPDATE public.email_registrations
  SET role = v_role, updated_at = now()
  WHERE auth_user_id = auth.uid();

  RETURN jsonb_build_object('role', v_role, 'organizer_mode', p_enabled);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_organizer_mode(boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_organizer_mode(boolean) TO authenticated;
