-- Reverts migration 182 (email_registrations lockdown): re-grants the table privileges to anon and authenticated.
--
-- THIS RESTORES A LESS SAFE STATE: with the grant back, anon/authenticated can use the table again whenever RLS lets them
-- (RLS stays ENABLED with no policy, so they still see and write no rows; but the privilege itself is back). Do not run it
-- casually, and never on production without a written reason. It deliberately does NOT disable row level security.
-- Kept OUT of supabase/migrations/ so `db push` never runs it.
DO $$
BEGIN
  IF to_regclass('public.email_registrations') IS NOT NULL THEN
    GRANT ALL ON TABLE public.email_registrations TO anon, authenticated;
  END IF;
END;
$$;
