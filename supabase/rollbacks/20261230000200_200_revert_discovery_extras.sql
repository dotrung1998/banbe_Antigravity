-- Rollback for 200. NOT a migration. Keeps notification_consent_log (consent records must be kept >= 1 year,
-- Decree 91/2020) and the digest_opt_in column's history in it; drops the digest machinery and the switches.
SELECT cron.unschedule('bb_weekly_digest') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bb_weekly_digest');
DROP FUNCTION IF EXISTS public.send_weekly_digests(timestamptz);
DROP FUNCTION IF EXISTS public.digest_candidates(uuid, timestamptz);
DROP TABLE IF EXISTS public.weekly_digest_log;
DROP FUNCTION IF EXISTS public.set_my_digest_opt_in(boolean);
DELETE FROM public.notification_i18n_body_rules WHERE pos IN (220, 221);
DELETE FROM public.notification_i18n_titles WHERE vi = 'Cuối tuần này';
DELETE FROM public.app_feature_flags WHERE key IN ('weekly_digest', 'intent_foryou', 'live_activity', 'market_share');
DELETE FROM public.app_feature_flag_defs WHERE key IN ('weekly_digest', 'intent_foryou', 'live_activity', 'market_share');
-- get_my_notification_preferences / set_my_promo_push keep their 200 bodies (same signature, one extra key, a log row).
