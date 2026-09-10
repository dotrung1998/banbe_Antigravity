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
--
-- This migration is deliberately standalone: it creates everything it touches,
-- so it repairs a database that never received migrations 013-015.

-- ---------------------------------------------------------------------------
-- 0. The email registry (also created by 013/014; repeated here so this
--    migration can stand on its own).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.email_registrations (
  email text PRIMARY KEY,
  role text NOT NULL DEFAULT 'participant',
  auth_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.email_registrations ADD COLUMN IF NOT EXISTS auth_user_id uuid;
ALTER TABLE public.email_registrations ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'participant';
ALTER TABLE public.email_registrations ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- The registry is written only by the service role and by SECURITY DEFINER
-- triggers, and it maps emails to accounts, so no client may read it.
ALTER TABLE public.email_registrations ENABLE ROW LEVEL SECURITY;

-- Profiles for auth users that predate the trigger, then link the registry.
INSERT INTO public.profiles (id, display_name, phone, locale, role)
SELECT u.id, COALESCE(u.raw_user_meta_data->>'display_name', ''), COALESCE(u.phone, ''), 'vi', 'participant'
FROM auth.users u
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.email_registrations (email, role, auth_user_id)
SELECT lower(u.email), COALESCE(p.role, 'participant'), u.id
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE u.email IS NOT NULL
ON CONFLICT (email) DO UPDATE SET
  auth_user_id = EXCLUDED.auth_user_id,
  updated_at = now();

-- ---------------------------------------------------------------------------
-- 1. New accounts are always participants.
--    raw_user_meta_data is client-supplied (signInWithOtp passes it straight
--    through), so honouring account_type here let a caller self-assign 'admin'.
-- ---------------------------------------------------------------------------
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

CREATE OR REPLACE FUNCTION handle_deleted_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.email_registrations
  SET auth_user_id = NULL, updated_at = now()
  WHERE auth_user_id = OLD.id;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_deleted ON auth.users;
CREATE TRIGGER on_auth_user_deleted
  AFTER DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_deleted_user();

-- ---------------------------------------------------------------------------
-- 2. Authoritative "does this email have an account?" lookup.
--    The API used to answer this by paging the Auth Admin user list, which
--    fails closed: any error there became "no account exists for this email".
--    Reading auth.users directly is exact, is one round trip, and cannot be
--    called by a browser (execute is granted to service_role only).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.find_auth_user_by_email(p_email text)
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT id
  FROM auth.users
  WHERE lower(email) = lower(trim(p_email))
  ORDER BY created_at
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.find_auth_user_by_email(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_auth_user_by_email(text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.find_auth_user_by_email(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 3. profiles_update_own lets a signed-in user PATCH their own profile row,
--    which included `role`. Now that role is a user-facing toggle, pin it:
--    only set_organizer_mode() (or the service role, whose auth.uid() is null)
--    may change it.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 4. The toggle itself. Admins keep their role; everyone else flips freely
--    between participant and organizer. The profile row is created on demand
--    so an account that predates handle_new_user() can still switch on.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_organizer_mode(p_enabled boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  INSERT INTO public.profiles (id, display_name, phone, locale, role)
  VALUES (auth.uid(), '', '', 'vi', 'participant')
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
