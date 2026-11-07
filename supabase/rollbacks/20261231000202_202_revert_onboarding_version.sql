-- Rollback for migration 202 (onboarding Version 3 + admin_set_onboarding_version). NOT in the migration chain.
-- Clients treat a missing `onboarding_v3` as "not Version 3", so they fall back to onboarding_v2 (Version 1/2).
-- The audit rows stay (history), so app_feature_flags_audit keeps its onboarding_v3 entries.
BEGIN;
DROP FUNCTION IF EXISTS public.admin_set_onboarding_version(integer);
DELETE FROM public.app_feature_flags WHERE key = 'onboarding_v3';
DELETE FROM public.app_feature_flag_defs WHERE key = 'onboarding_v3';
COMMIT;
