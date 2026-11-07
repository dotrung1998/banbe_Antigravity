-- Migration: organizer mode is a self-service toggle, not a registration type.
--
-- Previously an account was *registered* as participant or organizer, and the
-- email-link endpoint refused to send a sign-in link whenever the account type
-- selected in the UI differed from the stored role. That made it impossible for
-- an organizer to log back in through the normal "Sign in" entry point (which
-- always asks for a participant link) and vice versa.
--
-- From here on every account is created as a participant and can turn
-- organizer mode on or off at any time via set_organizer_mode().

-- 1. New accounts are always participants.
--    raw_user_meta_data is client-supplied (signInWithOtp passes it straight
--    through), so honouring account_type here let a caller self-assign 'admin'.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    INSERT INTO public.profiles (id, display_name, phone, locale, role)
    VALUES (
      NEW.id,
      COALESCE(NEW.raw_user_meta_data->>'display_name', ''),
      COALESCE(NEW.phone, ''),
      'vi',
      'participant'
    )
    ON CONFLICT (id) DO NOTHING;

    IF NEW.email IS NOT NULL THEN
      INSERT INTO public.email_registrations (email, role, auth_user_id)
      VALUES (lower(NEW.email), 'participant', NEW.id)
      ON CONFLICT (email) DO UPDATE SET
        auth_user_id = EXCLUDED.auth_user_id,
        updated_at = now();
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 2. profiles_update_own lets a signed-in user PATCH their own profile row,
--    which included `role`. Now that role is a user-facing toggle, pin it:
--    only set_organizer_mode() (or the service role, whose auth.uid() is null)
--    may change it.
CREATE OR REPLACE FUNCTION public.guard_profile_role()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role
     AND auth.uid() IS NOT NULL
     AND COALESCE(current_setting('app.role_change_allowed', true), '') <> '1'
  THEN
    NEW.role := OLD.role;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_profile_role_change ON public.profiles;
CREATE TRIGGER on_profile_role_change
  BEFORE UPDATE OF role ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_role();

-- 3. The toggle itself. Admins keep their role; everyone else flips freely
--    between participant and organizer.
CREATE OR REPLACE FUNCTION public.set_organizer_mode(p_enabled boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
  IF v_role IS NULL THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
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
