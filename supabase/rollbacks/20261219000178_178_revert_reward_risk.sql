-- ROLLBACK for 178 (manual, NOT in the migration chain). Preferred "rollback" is a flag, not a drop:
--   select admin_set_reward_risk_config(false, null);
-- Use this file only to remove the objects; it loses ONLY risk flags/config (no ledger, badge, streak or unlock data).
BEGIN;
DROP FUNCTION IF EXISTS public.admin_set_reward_risk_config(boolean, jsonb);
DROP FUNCTION IF EXISTS public.admin_get_reward_risk_config();
DROP FUNCTION IF EXISTS public.admin_review_reward_risk_flag(uuid, text, text);
DROP FUNCTION IF EXISTS public.admin_list_reward_risk_flags(text, int);
DROP FUNCTION IF EXISTS public.admin_run_reward_risk_scan();
DROP FUNCTION IF EXISTS public.admin_reward_risk_preview();
DROP FUNCTION IF EXISTS public.rewards_risk_compute();
DROP FUNCTION IF EXISTS public.rewards_risk_cfg();
DROP FUNCTION IF EXISTS public.rewards_risk_defaults();
DROP TABLE IF EXISTS public.reward_risk_flags;
DROP TABLE IF EXISTS public.reward_risk_config;
COMMIT;
