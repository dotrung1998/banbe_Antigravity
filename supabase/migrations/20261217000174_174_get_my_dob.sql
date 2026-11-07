-- 174: let the reserve form show the buyer's own profile birthday for a double check.
-- Replaces the boolean my_dob_on_file() from 173 (which stays harmless but is dropped here).
-- Returns the caller's OWN birthday, and only once the account gate is satisfied
-- (phone/DOB confirmed this session). No other account's birthday is reachable.
DROP FUNCTION IF EXISTS public.my_dob_on_file();

CREATE OR REPLACE FUNCTION public.get_my_dob()
RETURNS date LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT date_of_birth FROM public.user_private_dob
   WHERE user_id = auth.uid() AND (SELECT public.account_gate_ok());
$$;
REVOKE ALL ON FUNCTION public.get_my_dob() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_dob() TO authenticated;
