-- 193: corrective, found by the production grant audit while applying 177-192 (2026-10-22, note 58).
-- 177 created public.rewards_tz_valid(text) without revoking EXECUTE, so anon and authenticated could call it.
-- It only checks a zone name against pg_timezone_names (no data), but no client needs it: its only callers are
-- set_my_reward_timezone (SECURITY DEFINER) and the reward_user_settings validation trigger, which runs inside
-- that function. Same rule as every other rewards_* helper: internal only.
-- ROLLBACK: supabase/rollbacks/20261228000193_193_revert_revoke_rewards_tz_valid.sql
REVOKE EXECUTE ON FUNCTION public.rewards_tz_valid(text) FROM PUBLIC, anon, authenticated;
