-- ROLLBACK for 193 (manual, NOT in the migration chain): restores the default EXECUTE grant 177 left behind.
BEGIN;
GRANT EXECUTE ON FUNCTION public.rewards_tz_valid(text) TO PUBLIC;
COMMIT;
