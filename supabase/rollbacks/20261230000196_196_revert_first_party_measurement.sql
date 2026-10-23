-- Rollback for 196 (first-party measurement). NOT a migration. Drops the measurement data (app_events) on purpose:
-- it is product telemetry, not user content. profiles.market is kept (harmless) unless you also drop it below.
SELECT cron.unschedule('bb_purge_app_events') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bb_purge_app_events');
DROP FUNCTION IF EXISTS public.admin_retention_report(date, date);
DROP FUNCTION IF EXISTS public.report_k(bigint);
DROP FUNCTION IF EXISTS public.report_test_user_ids();
DROP TABLE IF EXISTS public.report_excluded_users;
DROP FUNCTION IF EXISTS public.purge_old_app_events();
DROP FUNCTION IF EXISTS public.log_app_events(jsonb, text);
DROP TABLE IF EXISTS public.app_events;
DROP TABLE IF EXISTS public.app_event_names;
DROP TRIGGER IF EXISTS bookings_profile_market ON public.bookings;
DROP TRIGGER IF EXISTS events_profile_market ON public.events;
DROP FUNCTION IF EXISTS public.profile_market_from_event();
DELETE FROM public.app_feature_flags WHERE key = 'app_events';
DELETE FROM public.app_feature_flag_defs WHERE key = 'app_events';
-- ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_market_check, DROP COLUMN IF EXISTS market;
