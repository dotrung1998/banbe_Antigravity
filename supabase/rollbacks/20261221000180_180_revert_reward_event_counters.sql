-- ROLLBACK for 180 (manual, NOT in the migration chain). Data-safe.
-- Always turns the flag off. Drops the new objects ONLY if the counter table is empty; with data it stops there
-- (the counters are aggregate and non-identifying, but are never deleted by a rollback).
BEGIN;
UPDATE public.reward_feature_flags SET enabled = false WHERE flag = 'reward_events';
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.reward_event_counters) THEN
    RAISE NOTICE 'reward_event_counters has data: flag turned off, objects kept.';
  ELSE
    DROP FUNCTION IF EXISTS public.admin_reward_event_report(date, date, boolean);
    DROP FUNCTION IF EXISTS public.record_reward_event(text, text, text);
    DROP FUNCTION IF EXISTS public.rewards_bump_event_counter(text, text, text);
    DROP TABLE IF EXISTS public.reward_event_counters;
    DROP TABLE IF EXISTS public.reward_event_config;
    DELETE FROM public.reward_feature_flags WHERE flag = 'reward_events';
  END IF;
END $$;
COMMIT;
