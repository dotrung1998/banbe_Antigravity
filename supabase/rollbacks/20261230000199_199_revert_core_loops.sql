-- Rollback for 199 (core loops). NOT a migration. Drops reminder log, follow-alert queue and guest feedback (feedback
-- is new data that only exists while event_recap was on). follows.created_at is kept unless dropped below.
SELECT cron.unschedule('bb_event_reminders') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bb_event_reminders');
SELECT cron.unschedule('bb_follow_alerts') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bb_follow_alerts');
DROP TRIGGER IF EXISTS events_on_ended ON public.events;
DROP TRIGGER IF EXISTS events_queue_follow_alerts ON public.events;
DROP FUNCTION IF EXISTS public.events_on_ended();
DROP FUNCTION IF EXISTS public.events_queue_follow_alerts();
DROP FUNCTION IF EXISTS public.send_follow_alerts(timestamptz);
DROP FUNCTION IF EXISTS public.user_local_zone(uuid);
DROP FUNCTION IF EXISTS public.send_event_reminders(timestamptz);
DROP FUNCTION IF EXISTS public.get_host_event_recap(text);
DROP FUNCTION IF EXISTS public.get_event_feedback_summary(text);
DROP FUNCTION IF EXISTS public.event_feedback_summary_of(text);
DROP FUNCTION IF EXISTS public.get_my_event_feedback(text);
DROP FUNCTION IF EXISTS public.submit_event_feedback(text, int, text);
DROP TABLE IF EXISTS public.follow_alert_queue;
DROP TABLE IF EXISTS public.event_feedback;
DROP TABLE IF EXISTS public.event_reminder_log;
DROP FUNCTION IF EXISTS public.kind_muted(uuid, text);
DROP FUNCTION IF EXISTS public.event_local_time_text(timestamptz, text, text);
DROP FUNCTION IF EXISTS public.booking_is_ticket(booking_status);
DELETE FROM public.notification_i18n_body_rules WHERE pos BETWEEN 210 AND 216;
DELETE FROM public.notification_i18n_titles WHERE vi IN ('Sự kiện ngày mai', 'Sắp bắt đầu', 'Sự kiện đã kết thúc', 'Tổng kết sự kiện', 'Mới từ host bạn theo dõi');
DELETE FROM public.app_feature_flags WHERE key IN ('event_reminders', 'event_recap', 'host_recap', 'follow_alerts');
DELETE FROM public.app_feature_flag_defs WHERE key IN ('event_reminders', 'event_recap', 'host_recap', 'follow_alerts');
-- ALTER TABLE public.follows DROP COLUMN IF EXISTS created_at;
