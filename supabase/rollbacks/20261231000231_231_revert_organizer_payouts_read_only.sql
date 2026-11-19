-- Rollback for 231: restore the pre-231 default privileges (ALL for authenticated).
-- This re-opens the auto-updatable view; only use it to diagnose a broken read path.

BEGIN;

REVOKE ALL ON public.organizer_payouts FROM PUBLIC, anon;
GRANT ALL ON public.organizer_payouts TO authenticated;

COMMIT;
