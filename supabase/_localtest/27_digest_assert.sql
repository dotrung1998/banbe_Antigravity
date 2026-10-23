-- LOCAL TEST HARNESS ONLY — never deployed, never run against a real project.
-- Migration 200: weekly digest opt-in, consent log, Thursday 18:00 local, never empty, once a week; new switches.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', coalesce(u::text, ''), true) $$;
CREATE FUNCTION pg_temp.err(sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $$;
-- Thursday 18:30 in Saigon of the current week, as an instant.
CREATE FUNCTION pg_temp.thu1830() RETURNS timestamptz LANGUAGE sql AS $$
  SELECT ((date_trunc('week', now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date + 3) + time '18:30') AT TIME ZONE 'Asia/Ho_Chi_Minh' $$;

DO $t$
DECLARE
  goer uuid := '7a000001-0000-4000-8000-000000000001';
  r jsonb; n int; t timestamptz := pg_temp.thu1830();
BEGIN
  PERFORM pg_temp.ok((SELECT string_agg(key || '=' || enabled, ',' ORDER BY key) FROM app_feature_flags
                       WHERE key IN ('weekly_digest', 'intent_foryou', 'live_activity', 'market_share'))
                     = 'intent_foryou=false,live_activity=false,market_share=false,weekly_digest=false', 'D0a all four switches OFF');
  PERFORM pg_temp.ok(NOT has_table_privilege('authenticated', 'public.notification_consent_log', 'SELECT')
                     AND NOT has_function_privilege('authenticated', 'public.send_weekly_digests(timestamp with time zone)', 'EXECUTE')
                     AND has_function_privilege('authenticated', 'public.set_my_digest_opt_in(boolean)', 'EXECUTE'), 'D0b privileges');
  PERFORM pg_temp.as_user(goer);
  r := public.set_my_digest_opt_in(true);
  PERFORM pg_temp.ok(r->>'error' = 'NOT_AVAILABLE', 'D1a cannot opt in while the digest switch is off');
  r := public.set_my_digest_opt_in(false);
  PERFORM pg_temp.ok((r->>'success')::boolean, 'D1b opting out always works');
  UPDATE app_feature_flags SET enabled = true WHERE key = 'weekly_digest';
  r := public.set_my_digest_opt_in(true);
  PERFORM pg_temp.ok((r->>'success')::boolean AND (public.get_my_notification_preferences()->>'digest_opt_in')::boolean, 'D1c opt in');
  PERFORM pg_temp.ok((SELECT count(*) FROM notification_consent_log WHERE user_id = goer AND consent = 'digest_opt_in') = 2,
                     'D1d every change is logged');
  PERFORM pg_temp.ok(pg_temp.err($q$UPDATE notification_consent_log SET enabled = false$q$) LIKE 'APPEND_ONLY%', 'D1e consent log is append-only');
  PERFORM public.set_my_promo_push(true);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM notification_consent_log WHERE user_id = goer AND consent = 'promo_push'), 'D1f promo push consent logged too');

  PERFORM pg_temp.as_user(NULL);
  UPDATE profiles SET market = 'VN' WHERE id = goer;
  UPDATE events SET status = 'ended' WHERE status = 'live';
  PERFORM pg_temp.ok(public.send_weekly_digests(t) = 0 AND NOT EXISTS (SELECT 1 FROM notifications WHERE kind = 'weekly_digest'),
                     'D2a nothing this weekend: nothing sent');
  INSERT INTO events (id, key, name, organizer_id, status, visibility, price_vnd, capacity, starts_at, country_code, cat_key)
  VALUES ('dg_1', 'dg_1', 'Weekend Jazz', 'test_org_a', 'live', 'public', 0, 10, t + interval '2 days', 'VN', 'music'),
         ('dg_2', 'dg_2', 'Weekend Pop-up', 'test_org_a', 'live', 'public', 0, 10, t + interval '3 days', 'VN', 'popup'),
         ('dg_us', 'dg_us', 'LA Night', 'test_org_a', 'live', 'public', 0, 10, t + interval '2 days', 'US', 'music');
  PERFORM pg_temp.ok(public.send_weekly_digests(t - interval '1 hour') = 0, 'D2b not at 17:30');
  PERFORM pg_temp.ok(public.send_weekly_digests(t) = 1, 'D2c Thursday 18:30 local: one digest');
  PERFORM pg_temp.ok((SELECT body = '2 sự kiện cuối tuần này, có Weekend Jazz.' FROM notifications WHERE kind = 'weekly_digest'),
                     'D2d counts only the person''s market, names one real event');
  PERFORM pg_temp.ok(public.send_weekly_digests(t + interval '10 minutes') = 0, 'D2e once per week');
  UPDATE app_feature_flags SET enabled = false WHERE key = 'weekly_digest';
  DELETE FROM weekly_digest_log;
  PERFORM pg_temp.ok(public.send_weekly_digests(t) = 0, 'D2f switch off: nothing');
  RAISE NOTICE 'DIGEST RESULT: ALL PASS';
END $t$;
ROLLBACK;
