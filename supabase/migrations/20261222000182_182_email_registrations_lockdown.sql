-- 182: lock public.email_registrations away from the client roles.
--
-- NUMBERING NOTE. The R3/R5 staging write-ups call this patch "migration 181". The real number is 182: 181 was already
-- taken by 181_phone_bypass_all. Same patch, different file name.
--
-- ALREADY APPLIED BY HAND ON PRODUCTION. The statements below were run manually on production (RLS was already ON there;
-- the REVOKE was the change). This file exists so every other environment (local, staging, new projects) gets the same
-- state. It is idempotent, so on production it is a NO-OP: ENABLE ROW LEVEL SECURITY on a table that already has it, and
-- REVOKE of privileges that are already gone, change nothing.
--
-- WHY. The table (013/014) is the server-side email -> auth user registry (api/_lib/authLookup.js, the auth.users
-- triggers handle_new_user / handle_deleted_user, set_organizer_mode, upload_payment_document). It had RLS off and the
-- Supabase default grants, so the public anon key could read every registered email address. Every caller in this repo
-- uses the service role or a SECURITY DEFINER function owned by postgres (BYPASSRLS), so nothing legitimate needs the
-- client roles on it.
--
-- WHAT THIS DOES NOT DO. It creates NO policy: with RLS on and no policy, the client roles see and write nothing even if
-- a grant is later added by mistake. It does not touch service_role or postgres (their ACL entries stay).
--
-- ROLLBACK: supabase/rollbacks/20261222000182_182_revert_email_registrations_lockdown.sql only re-grants the table
-- privileges to anon/authenticated (a LESS SAFE state: do not run it casually). It deliberately leaves RLS enabled.

DO $$
BEGIN
  IF to_regclass('public.email_registrations') IS NOT NULL THEN
    ALTER TABLE public.email_registrations ENABLE ROW LEVEL SECURITY;
    REVOKE ALL ON TABLE public.email_registrations FROM anon, authenticated;
  END IF;
END;
$$;
