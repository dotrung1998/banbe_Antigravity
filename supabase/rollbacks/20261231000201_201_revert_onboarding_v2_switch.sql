-- Rollback for migration 201 (onboarding demo version switch). NOT in the migration chain.
-- Clients treat a missing `onboarding_v2` as Version 1, so removing it is safe.
BEGIN;
DELETE FROM public.app_feature_flags WHERE key = 'onboarding_v2';
DELETE FROM public.app_feature_flag_defs WHERE key = 'onboarding_v2';
COMMIT;
