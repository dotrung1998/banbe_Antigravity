-- Reverts migration 187. Run by hand only. Clients treat a missing get_feature_flags() as "everything on", so
-- Rewards & badges reappears for everyone once this runs.
DROP FUNCTION IF EXISTS public.admin_set_feature_flag(text, boolean);
DROP FUNCTION IF EXISTS public.get_feature_flags();
DROP TABLE IF EXISTS public.app_feature_flags_audit;
DROP TABLE IF EXISTS public.app_feature_flags;
