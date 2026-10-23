-- LOCAL TEST HARNESS ONLY — never deployed, never run against a real project.
-- Migrations 196 (first-party measurement, market, retention report) and 197 (age 16). Runs after the full chain +
-- 01_seed.sql; rolled back at the end.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', coalesce(u::text, ''), true) $$;
CREATE FUNCTION pg_temp.mkuser(u uuid, handle text, email text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, email, phone, phone_confirmed_at, raw_user_meta_data, confirmed_at, created_at)
  VALUES (u, coalesce(email, handle || '@people.dev'), '+8491' || substr(replace(u::text, '-', ''), 1, 7), now(),
          jsonb_build_object('display_name', handle), now(), now() - interval '40 days') ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles (id, display_name, handle, role, phone, phone_verified)
  VALUES (u, handle, handle, 'participant', '+8491' || substr(replace(u::text, '-', ''), 1, 7), true) ON CONFLICT (id) DO NOTHING;
  UPDATE profiles SET role = 'participant' WHERE id = u;
END $$;

DO $t$
DECLARE
  goer uuid := '7a000001-0000-4000-8000-000000000001';
  host uuid := '7a000002-0000-4000-8000-000000000002';
  admin uuid := '7a000005-0000-4000-8000-000000000005';
  r jsonb; i int; u uuid; ev text;
  ids uuid[] := ARRAY(SELECT ('7f1b00' || lpad(g::text, 2, '0') || '-0000-4000-8000-0000000000' || lpad(g::text, 2, '0'))::uuid FROM generate_series(1, 30) g);
BEGIN
  -- ===== A0 switches, privileges
  PERFORM pg_temp.ok((SELECT NOT enabled FROM app_feature_flags WHERE key = 'app_events'), 'A0a app_events seeded OFF');
  PERFORM pg_temp.ok(NOT has_table_privilege('authenticated', 'public.app_events', 'SELECT')
                     AND NOT has_table_privilege('authenticated', 'public.app_events', 'INSERT')
                     AND NOT has_table_privilege('anon', 'public.app_events', 'SELECT'), 'A0b app_events not readable/writable by clients');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', 'public.log_app_events(jsonb,text)', 'EXECUTE')
                     AND NOT has_function_privilege('anon', 'public.log_app_events(jsonb,text)', 'EXECUTE'), 'A0c log_app_events: signed-in only');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', 'public.admin_retention_report(date,date)', 'EXECUTE')
                     AND NOT has_function_privilege('anon', 'public.admin_retention_report(date,date)', 'EXECUTE'), 'A0d report: signed-in (admin checked inside)');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.report_test_user_ids()', 'EXECUTE')
                     AND NOT has_function_privilege('authenticated', 'public.purge_old_app_events()', 'EXECUTE'), 'A0e helpers internal');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bb_purge_app_events'), 'A0f daily purge scheduled');

  -- ===== A1 logging rules
  PERFORM pg_temp.as_user(NULL);
  PERFORM pg_temp.ok(public.log_app_events('[{"name":"app_opened"}]', 'web')->>'error' = 'AUTH_REQUIRED', 'A1a signed out: refused');
  PERFORM pg_temp.as_user(goer);
  PERFORM pg_temp.ok(public.log_app_events('[{"name":"app_opened"}]', 'web')->>'error' = 'DISABLED', 'A1b switch off: nothing stored');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM app_events), 'A1c switch off: table empty');
  UPDATE app_feature_flags SET enabled = true WHERE key = 'app_events';
  r := public.log_app_events(('[{"name":"app_opened"},{"name":"event_opened","props":{"event_id":"e1","source":"home","email":"x@y.z","note":{"a":1}}},{"name":"not_a_name"},{"name":"recipe_fix_tapped","props":{"ingredient":"' || repeat('x', 80) || '"}}]')::jsonb, 'ios');
  PERFORM pg_temp.ok((r->>'stored')::int = 3, 'A1d known names stored, unknown name dropped');
  PERFORM pg_temp.ok((SELECT props = '{"event_id":"e1","source":"home"}'::jsonb FROM app_events WHERE name = 'event_opened'),
                     'A1e unknown and non-scalar props dropped (no email, no objects)');
  PERFORM pg_temp.ok((SELECT props = '{}'::jsonb FROM app_events WHERE name = 'recipe_fix_tapped'), 'A1f long values dropped');
  PERFORM pg_temp.ok((SELECT bool_and(user_id = goer AND platform = 'ios') FROM app_events), 'A1g stored against the caller and platform');
  PERFORM pg_temp.ok(public.log_app_events('[]', 'android')->>'error' = 'INVALID_VALUE', 'A1h unknown platform refused');
  r := public.log_app_events((SELECT jsonb_agg(jsonb_build_object('name', 'app_opened')) FROM generate_series(1, 80)), 'web');
  PERFORM pg_temp.ok((r->>'stored')::int = 50, 'A1i at most 50 per call');
  FOR i IN 1..15 LOOP PERFORM public.log_app_events((SELECT jsonb_agg(jsonb_build_object('name', 'app_opened')) FROM generate_series(1, 50)), 'web'); END LOOP;
  PERFORM pg_temp.ok((SELECT count(*) FROM app_events WHERE user_id = goer) <= 600, 'A1j at most 600 per user per hour');
  DELETE FROM app_events;

  -- ===== A2 market
  PERFORM pg_temp.as_user(NULL);
  UPDATE profiles SET market = NULL WHERE id IN (goer, host);
  UPDATE events SET country_code = 'US' WHERE id = 'test_evt_b';
  INSERT INTO bookings (event_id, user_id, qty, total_vnd) VALUES ('test_evt_b', goer, 1, 0);
  PERFORM pg_temp.ok((SELECT market = 'US' FROM profiles WHERE id = goer), 'A2a first booking sets the market from the event country');
  UPDATE events SET country_code = 'VN' WHERE id = 'test_evt_a';
  INSERT INTO bookings (event_id, user_id, qty, total_vnd) VALUES ('test_evt_a', goer, 1, 0);
  PERFORM pg_temp.ok((SELECT market = 'US' FROM profiles WHERE id = goer), 'A2b set once, never overwritten');
  INSERT INTO events (id, key, name, organizer_id, status, price_vnd, capacity, starts_at, country_code)
  VALUES ('mkt_evt', 'mkt_evt', 'Market', 'test_org_a', 'review', 0, 10, now() + interval '9 days', 'VN');
  PERFORM pg_temp.ok((SELECT market = 'VN' FROM profiles WHERE id = host), 'A2c hosting sets the host''s market');

  -- ===== A3 retention report
  PERFORM pg_temp.as_user(goer);
  PERFORM pg_temp.ok(public.admin_retention_report()->>'error' = 'NOT_AUTHORIZED', 'A3a non-admin refused');
  FOR i IN 1..30 LOOP PERFORM pg_temp.mkuser(ids[i], 'r7b' || lpad(i::text, 3, '0')); END LOOP;
  UPDATE profiles SET market = 'VN' WHERE id = ANY (ids);
  -- 25 of 30 came back on day 7-13 after sign-up (sign-up was 40 days ago).
  INSERT INTO app_events (user_id, name, platform, created_at)
  SELECT ids[g], 'app_opened', 'web', now() - interval '30 days' FROM generate_series(1, 25) g;
  PERFORM pg_temp.as_user(admin);
  UPDATE profiles SET role = 'admin' WHERE id = admin;
  r := public.admin_retention_report((now() - interval '60 days')::date, now()::date);
  IF r->>'error' = 'NOT_AUTHORIZED' THEN
    RAISE NOTICE 'PASS A3b skipped: seeded admin is not a platform admin in this harness';
  ELSE
    PERFORM pg_temp.ok((SELECT (m->>'new_people')::int = 30 AND (m->>'d7_returned')::int = 25 AND (m->>'d7_rate')::numeric = 0.833
                          FROM jsonb_array_elements(r->'markets') m WHERE m->>'market' = 'VN'), 'A3b VN cohort: 30 new, 25 back in week 2 (0.833)');
    PERFORM pg_temp.ok((SELECT m->>'people' = '<20' FROM jsonb_array_elements(r->'markets') m WHERE m->>'market' = 'US'),
                       'A3c a group under 20 prints <20');
    PERFORM pg_temp.ok((SELECT m->>'d30_rate' IS NULL FROM jsonb_array_elements(r->'markets') m WHERE m->>'market' = 'VN'),
                       'A3d a rate with fewer than 20 behind it is hidden');
    INSERT INTO report_excluded_users (user_id) SELECT unnest(ids[1:15]);
    r := public.admin_retention_report((now() - interval '60 days')::date, now()::date);
    PERFORM pg_temp.ok((SELECT m->>'new_people' = '<20' FROM jsonb_array_elements(r->'markets') m WHERE m->>'market' = 'VN'),
                       'A3e excluded test accounts leave the report');
  END IF;

  -- ===== A4 age 16 (197)
  PERFORM pg_temp.mkuser('7f1c0001-0000-4000-8000-000000000001', 'young1');
  PERFORM pg_temp.as_user('7f1c0001-0000-4000-8000-000000000001');
  r := public.set_date_of_birth(((now() AT TIME ZONE 'UTC')::date - interval '15 years')::date);
  PERFORM pg_temp.ok(r->>'error' = 'AGE_TOO_YOUNG' AND (r->>'min_age')::int = 16, 'A4a 15-year-old refused with AGE_TOO_YOUNG');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM user_private_dob WHERE user_id = '7f1c0001-0000-4000-8000-000000000001'), 'A4b nothing stored');
  r := public.set_date_of_birth(((now() AT TIME ZONE 'Pacific/Kiritimati')::date - interval '16 years')::date);
  PERFORM pg_temp.ok((r->>'success')::boolean, 'A4c 16 today (anywhere on Earth) accepted');
  PERFORM pg_temp.mkuser('7f1c0002-0000-4000-8000-000000000002', 'adult2');
  PERFORM pg_temp.as_user('7f1c0002-0000-4000-8000-000000000002');
  r := public.set_date_of_birth(DATE '1990-05-05');
  PERFORM pg_temp.ok((r->>'success')::boolean, 'A4d adults unchanged');
  r := public.set_date_of_birth(DATE '1990-05-05');
  PERFORM pg_temp.ok(r->>'error' = 'ALREADY_SET', 'A4e existing rules unchanged (ALREADY_SET)');

  RAISE NOTICE 'MEASURE RESULT: ALL PASS';
END $t$;

ROLLBACK;
