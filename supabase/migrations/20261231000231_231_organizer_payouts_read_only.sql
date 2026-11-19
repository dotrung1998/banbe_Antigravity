-- 231 — organizer_payouts is a read-only projection for clients.
--
-- Audit 2026-11-19 row 2 follow-up. 223 created the view to move bank/tax/QR columns off
-- `organizers`, but Supabase's default privileges granted ALL on the new view to `authenticated`
-- (relacl `authenticated=arwdDxtm`), while 223 only revoked PUBLIC and anon. PostgreSQL reports
-- the view as auto-updatable (pg_relation_is_updatable = 28: INSERT/UPDATE/DELETE), so a signed-in
-- guest holding a booking on a host could UPDATE that host's bank/tax columns through the view,
-- with the view owner's rights, bypassing the organizers column grants and its RLS.
--
-- The view is a read surface only; every write goes through the existing RPCs. Revoke everything,
-- then grant SELECT back.
--
-- Rollback: supabase/rollbacks/20261231000231_231_revert_organizer_payouts_read_only.sql

BEGIN;

REVOKE ALL ON public.organizer_payouts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.organizer_payouts TO authenticated;

COMMIT;

-- Verification (after `supabase db push`):
--   select has_table_privilege('authenticated','public.organizer_payouts','SELECT'); -- true
--   select has_table_privilege('authenticated','public.organizer_payouts','UPDATE'); -- false
--   as an authenticated guest: update public.organizer_payouts set bank_name = bank_name;
--     -> permission denied for view organizer_payouts
