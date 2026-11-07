-- Migration: repair the two account-detection failures reported against
-- superdeutsche98@gmail.com:
--
-- 1. Login claimed "No account exists for this email" for an email that had
--    just registered successfully. The API's fallback lookup (paging the
--    Auth Admin user list) silently swallowed any failure and treated it the
--    same as "no such user". This migration adds an authoritative,
--    single-round-trip RPC over auth.users that the API tries before falling
--    back to the Admin API, and — paired with the API fix in this same
--    change — a lookup that fails now returns "could not check" instead of
--    "does not exist".
--
-- 2. Organizer mode looked like it "turned itself back off" right after being
--    enabled. set_organizer_mode() raised PROFILE_NOT_FOUND for any account
--    whose profiles row did not exist yet (created before handle_new_user
--    covered every path, or the row was never backfilled), the RPC call
--    failed, and the client rolled the toggle back. Auto-creating the row on
--    demand — the same thing handle_new_user does — removes that failure
--    mode entirely.

-- ---------------------------------------------------------------------------
-- 1. Authoritative "does this email have an account?" lookup, callable only
--    by the service role (never by anon/authenticated from the browser).
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
-- 2. Keep the registry accurate when an auth user is deleted, so a stale
--    auth_user_id can never make a deleted account look "still registered".
-- ---------------------------------------------------------------------------
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
-- 3. set_organizer_mode: create the profile row on demand instead of failing
--    when it is missing, so the toggle can never silently roll itself back.
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
