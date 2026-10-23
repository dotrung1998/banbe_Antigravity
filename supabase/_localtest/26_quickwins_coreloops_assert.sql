-- LOCAL TEST HARNESS ONLY — never deployed, never run against a real project.
-- Migrations 198 (Q2 host confirmation time, Q6 translations) and 199 (L1 reminders, L2 recap + feedback, L3 host
-- recap, L4 follow alerts). Runs after the full chain + 01_seed.sql; rolled back at the end.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', coalesce(u::text, ''), true) $$;
CREATE FUNCTION pg_temp.flag(k text, v boolean) RETURNS void LANGUAGE sql AS $$ UPDATE app_feature_flags SET enabled = v WHERE key = k $$;
CREATE FUNCTION pg_temp.mkuser(u uuid, handle text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, email, phone, phone_confirmed_at, raw_user_meta_data, confirmed_at)
  VALUES (u, handle || '@people.dev', '+8492' || substr(replace(u::text, '-', ''), 1, 7), now(), jsonb_build_object('display_name', handle), now())
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles (id, display_name, handle, role, phone, phone_verified)
  VALUES (u, handle, handle, 'participant', '+8492' || substr(replace(u::text, '-', ''), 1, 7), true) ON CONFLICT (id) DO NOTHING;
END $$;

DO $t$
DECLARE
  goer uuid := '7a000001-0000-4000-8000-000000000001';
  host uuid := '7a000002-0000-4000-8000-000000000002';
  other uuid := '7a000003-0000-4000-8000-000000000003';
  g uuid[] := ARRAY(SELECT ('7f1d00' || lpad(i::text, 2, '0') || '-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid FROM generate_series(1, 6) i);
  r jsonb; n int; i int; b uuid;
BEGIN
  UPDATE profiles SET role = 'organizer' WHERE id = host;
  FOR i IN 1..6 LOOP PERFORM pg_temp.mkuser(g[i], 'q7d' || i); END LOOP;

  -- ===== S0 switches + privileges
  PERFORM pg_temp.ok((SELECT string_agg(key || '=' || enabled, ',' ORDER BY key) FROM app_feature_flags
                       WHERE key IN ('event_reminders', 'event_recap', 'host_recap', 'follow_alerts'))
                     = 'event_recap=false,event_reminders=true,follow_alerts=false,host_recap=false', 'S0a reminders ON, the rest OFF');
  PERFORM pg_temp.ok(NOT has_table_privilege('authenticated', 'public.event_feedback', 'SELECT')
                     AND NOT has_table_privilege('authenticated', 'public.follow_alert_queue', 'SELECT')
                     AND NOT has_table_privilege('authenticated', 'public.event_reminder_log', 'SELECT'), 'S0b new tables closed to clients');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.send_event_reminders(timestamp with time zone)', 'EXECUTE')
                     AND NOT has_function_privilege('authenticated', 'public.send_follow_alerts(timestamp with time zone)', 'EXECUTE')
                     AND NOT has_function_privilege('authenticated', 'public.event_feedback_summary_of(text)', 'EXECUTE'), 'S0c jobs + helpers internal');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', 'public.submit_event_feedback(text,integer,text)', 'EXECUTE')
                     AND NOT has_function_privilege('anon', 'public.submit_event_feedback(text,integer,text)', 'EXECUTE')
                     AND has_function_privilege('authenticated', 'public.get_host_confirmation_time(text)', 'EXECUTE')
                     AND NOT has_function_privilege('anon', 'public.get_host_confirmation_time(text)', 'EXECUTE'), 'S0d client RPCs signed-in only');

  -- ===== Q2 typical confirmation time (n >= 5 or nothing)
  PERFORM pg_temp.as_user(goer);
  r := public.get_host_confirmation_time('test_evt_a');
  PERFORM pg_temp.ok((r->>'success')::boolean AND r->'median_minutes' = 'null'::jsonb, 'Q2a fewer than 5 confirmations: no time shown');
  FOR i IN 1..5 LOOP
    INSERT INTO bookings (event_id, user_id, qty, total_vnd, status, proof_submitted_at, verified_at)
    VALUES ('test_evt_a', g[i], 1, 150000, 'confirmed', now() - interval '2 days', now() - interval '2 days' + (i * 10 || ' minutes')::interval);
  END LOOP;
  r := public.get_host_confirmation_time('test_evt_a');
  PERFORM pg_temp.ok((r->>'n')::int = 5 AND (r->>'median_minutes')::int = 30, 'Q2b 5 confirmations: median 30 minutes');

  -- ===== Q6 translations
  UPDATE profiles SET locale = 'en' WHERE id = other;
  INSERT INTO notifications (recipient_id, kind, title, body)
  VALUES (other, 'not_found_expired', 'Vé đã được trả lại', 'Hết 2 ngày mà người tổ chức chưa xác nhận khoản chuyển khoản. Vé đã được trả lại kho.');
  PERFORM pg_temp.ok((SELECT title = 'Ticket returned' AND body LIKE 'Two days passed%' FROM notifications WHERE recipient_id = other ORDER BY created_at DESC LIMIT 1),
                     'Q6a English user gets English title + body');
  INSERT INTO notifications (recipient_id, kind, title, body) VALUES (other, 'event_announcement', 'Thông báo từ host', 'Cửa mở lúc 19:00');
  PERFORM pg_temp.ok((SELECT title = 'Message from the host' AND body = 'Cửa mở lúc 19:00' FROM notifications WHERE recipient_id = other AND kind = 'event_announcement'),
                     'Q6b host announcement: title translated, the host''s own words untouched');

  -- ===== L1 reminders
  PERFORM pg_temp.as_user(NULL);
  UPDATE events SET status = 'live', starts_at = now() + interval '24 hours', tz = 'Asia/Ho_Chi_Minh', country_code = 'VN', area = 'Quận 1' WHERE id = 'test_evt_b';
  UPDATE bookings SET created_at = now() - interval '2 days' WHERE event_id = 'test_evt_b';
  n := public.send_event_reminders();
  PERFORM pg_temp.ok(n = 1 AND EXISTS (SELECT 1 FROM notifications WHERE recipient_id = goer AND kind = 'event_reminder_day'
                       AND body = 'Beta Jazz Evening bắt đầu lúc ' || to_char((now() + interval '24 hours') AT TIME ZONE 'Asia/Ho_Chi_Minh', 'HH24:MI')
                                  || ' ngày mai tại Quận 1. Vé của bạn có trong ứng dụng.'),
                     'L1a day-before reminder for the ticket holder, time in the event zone');
  PERFORM pg_temp.ok(public.send_event_reminders() = 0, 'L1b never twice');
  UPDATE events SET starts_at = now() + interval '3 hours' WHERE id = 'test_evt_b';
  UPDATE profiles SET muted_notification_kinds = ARRAY['event_reminder_soon'] WHERE id = goer;
  PERFORM public.send_event_reminders();
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM notifications WHERE recipient_id = goer AND kind = 'event_reminder_soon'), 'L1c muted kind: no reminder');
  UPDATE profiles SET muted_notification_kinds = '{}' WHERE id = goer;
  UPDATE profiles SET locale = 'en' WHERE id = goer;
  DELETE FROM event_reminder_log;
  UPDATE events SET starts_at = now() + interval '3 hours', country_code = 'US', tz = 'America/Los_Angeles', area = '' , city = '' WHERE id = 'test_evt_b';
  PERFORM public.send_event_reminders();
  PERFORM pg_temp.ok((SELECT title = 'Starting soon'
                             AND body = 'Beta Jazz Evening starts at ' || to_char((now() + interval '3 hours') AT TIME ZONE 'America/Los_Angeles', 'FMHH12:MI AM')
                                        || '. Your ticket is in the app.'
                        FROM notifications WHERE recipient_id = goer AND kind = 'event_reminder_soon'),
                     'L1d US event: English, 12-hour clock, in the venue zone');
  UPDATE events SET status = 'cancelled', cancelled_at = now() WHERE id = 'test_evt_b';
  DELETE FROM event_reminder_log;
  PERFORM pg_temp.ok(public.send_event_reminders() = 0, 'L1e cancelled event: no reminders');
  PERFORM pg_temp.flag('event_reminders', false);
  UPDATE events SET status = 'live', cancelled_at = NULL WHERE id = 'test_evt_b';
  PERFORM pg_temp.ok(public.send_event_reminders() = 0, 'L1f switch off: nothing');
  PERFORM pg_temp.flag('event_reminders', true);

  -- ===== L2 recap + feedback (switch OFF first)
  UPDATE profiles SET locale = 'vi' WHERE id = goer;
  UPDATE events SET status = 'ended', starts_at = now() - interval '13 hours' WHERE id = 'test_evt_b';
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM notifications WHERE kind = 'event_recap'), 'L2a switch off: no recap');
  PERFORM pg_temp.as_user(goer);
  PERFORM pg_temp.ok(public.submit_event_feedback('test_evt_b', 1, 'great')->>'error' = 'NOT_AVAILABLE', 'L2b switch off: feedback closed');
  PERFORM pg_temp.as_user(NULL);
  PERFORM pg_temp.flag('event_recap', true);
  PERFORM pg_temp.flag('host_recap', true);
  UPDATE events SET status = 'live' WHERE id = 'test_evt_a';
  UPDATE events SET status = 'ended', starts_at = now() - interval '13 hours' WHERE id = 'test_evt_a';
  PERFORM pg_temp.ok((SELECT count(*) FROM notifications WHERE kind = 'event_recap' AND data->>'event_id' = 'test_evt_a') = 5,
                     'L2c each ticket holder gets one recap (cancelled booking excluded)');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM notifications WHERE kind = 'host_event_recap' AND recipient_id = host AND data->>'event_id' = 'test_evt_a'),
                     'L3a the host gets the recap notice');
  PERFORM pg_temp.as_user(g[1]);
  PERFORM pg_temp.ok((public.submit_event_feedback('test_evt_a', 1, 'Loved the music')->>'success')::boolean, 'L2d a ticket holder can answer');
  r := public.submit_event_feedback('test_evt_a', -1, 'Too loud');
  PERFORM pg_temp.ok((r->>'success')::boolean AND (SELECT rating = -1 FROM event_feedback WHERE user_id = g[1]), 'L2e and change the answer');
  PERFORM pg_temp.as_user(other);
  PERFORM pg_temp.ok(public.submit_event_feedback('test_evt_a', 1, '')->>'error' = 'NO_TICKET', 'L2f no ticket: refused');
  PERFORM pg_temp.as_user(g[2]);
  PERFORM pg_temp.ok(public.submit_event_feedback('test_evt_a', 3, '')->>'error' = 'INVALID_VALUE', 'L2g rating is up or down only');
  PERFORM public.submit_event_feedback('test_evt_a', 1, '');
  PERFORM pg_temp.as_user(host);
  r := public.get_event_feedback_summary('test_evt_a');
  PERFORM pg_temp.ok((r->>'hidden')::boolean AND (r->>'responses')::int = 2 AND NOT r ? 'notes', 'L2h host sees nothing under 3 answers');
  PERFORM pg_temp.as_user(g[3]);
  PERFORM public.submit_event_feedback('test_evt_a', 1, 'Nice host');
  PERFORM pg_temp.as_user(host);
  r := public.get_event_feedback_summary('test_evt_a');
  PERFORM pg_temp.ok(NOT (r->>'hidden')::boolean AND (r->>'up')::int = 2 AND (r->>'down')::int = 1 AND jsonb_array_length(r->'notes') = 2
                     AND NOT (r::text LIKE '%' || g[1]::text || '%'), 'L2i from 3 answers: counts and notes, no names or ids');
  PERFORM pg_temp.as_user(goer);
  PERFORM pg_temp.ok(public.get_event_feedback_summary('test_evt_a')->>'error' = 'NOT_AUTHORIZED', 'L2j guests cannot read the summary');

  -- ===== L3 host recap
  INSERT INTO follows (user_id, organizer_id) VALUES (g[4], 'test_org_a');
  PERFORM pg_temp.as_user(host);
  UPDATE events SET submitted_at = now() - interval '5 days' WHERE id = 'test_evt_a';
  r := public.get_host_event_recap('test_evt_a');
  PERFORM pg_temp.ok((r->>'success')::boolean AND (r->>'confirmed_seats')::int = 5 AND (r->>'new_followers')::int = 1
                     AND (r->'feedback'->>'responses')::int = 3, 'L3b recap: seats, new followers, feedback summary');
  PERFORM pg_temp.as_user(goer);
  PERFORM pg_temp.ok(public.get_host_event_recap('test_evt_a')->>'error' = 'NOT_AUTHORIZED', 'L3c only the host');

  -- ===== L4 follow alerts
  PERFORM pg_temp.as_user(NULL);
  PERFORM pg_temp.flag('follow_alerts', true);
  INSERT INTO follows (user_id, organizer_id) VALUES (g[5], 'test_org_a'), (host, 'test_org_a') ON CONFLICT DO NOTHING;
  INSERT INTO events (id, key, name, organizer_id, status, visibility, price_vnd, capacity, starts_at)
  VALUES ('fa_1', 'fa_1', 'Follow One', 'test_org_a', 'review', 'public', 0, 10, now() + interval '5 days'),
         ('fa_2', 'fa_2', 'Follow Two', 'test_org_a', 'review', 'public', 0, 10, now() + interval '6 days');
  UPDATE events SET status = 'live' WHERE id IN ('fa_1', 'fa_2');
  PERFORM pg_temp.ok((SELECT count(*) FROM follow_alert_queue WHERE user_id = g[5]) = 2
                     AND NOT EXISTS (SELECT 1 FROM follow_alert_queue WHERE user_id = host), 'L4a followers queued, never the host');
  UPDATE reward_user_settings SET tz = NULL WHERE user_id = g[5];
  UPDATE profiles SET market = 'VN' WHERE id = g[5];
  n := public.send_follow_alerts((date_trunc('day', now() AT TIME ZONE 'Asia/Ho_Chi_Minh') + interval '10 hours') AT TIME ZONE 'Asia/Ho_Chi_Minh');
  PERFORM pg_temp.ok((SELECT count(*) FROM notifications WHERE recipient_id = g[5] AND kind = 'follow_alert') = 1
                     AND (SELECT body FROM notifications WHERE recipient_id = g[5] AND kind = 'follow_alert') = '2 sự kiện mới từ Alpha Events.',
                     'L4b ONE bundled alert for two new events');
  INSERT INTO events (id, key, name, organizer_id, status, visibility, price_vnd, capacity, starts_at)
  VALUES ('fa_3', 'fa_3', 'Follow Three', 'test_org_a', 'review', 'public', 0, 10, now() + interval '7 days');
  UPDATE events SET status = 'live' WHERE id = 'fa_3';
  PERFORM public.send_follow_alerts((date_trunc('day', now() AT TIME ZONE 'Asia/Ho_Chi_Minh') + interval '11 hours') AT TIME ZONE 'Asia/Ho_Chi_Minh');
  PERFORM pg_temp.ok((SELECT count(*) FROM notifications WHERE recipient_id = g[5] AND kind = 'follow_alert') = 1, 'L4c at most one a day');
  DELETE FROM notifications WHERE recipient_id = g[5] AND kind = 'follow_alert';
  PERFORM public.send_follow_alerts((date_trunc('day', now() AT TIME ZONE 'Asia/Ho_Chi_Minh') + interval '23 hours') AT TIME ZONE 'Asia/Ho_Chi_Minh');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM notifications WHERE recipient_id = g[5] AND kind = 'follow_alert'), 'L4d not at 23:00 local');
  UPDATE profiles SET muted_notification_kinds = ARRAY['follow_alert'] WHERE id = g[5];
  PERFORM public.send_follow_alerts((date_trunc('day', now() AT TIME ZONE 'Asia/Ho_Chi_Minh') + interval '10 hours') AT TIME ZONE 'Asia/Ho_Chi_Minh');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM notifications WHERE recipient_id = g[5] AND kind = 'follow_alert')
                     AND NOT EXISTS (SELECT 1 FROM follow_alert_queue WHERE user_id = g[5]), 'L4e muted: dropped, not sent');
  PERFORM pg_temp.flag('follow_alerts', false);
  INSERT INTO events (id, key, name, organizer_id, status, visibility, price_vnd, capacity, starts_at)
  VALUES ('fa_4', 'fa_4', 'Follow Four', 'test_org_a', 'review', 'public', 0, 10, now() + interval '8 days');
  UPDATE events SET status = 'live' WHERE id = 'fa_4';
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM follow_alert_queue WHERE event_id = 'fa_4'), 'L4f switch off: nothing queued');

  RAISE NOTICE 'LOOPS RESULT: ALL PASS';
END $t$;

ROLLBACK;
