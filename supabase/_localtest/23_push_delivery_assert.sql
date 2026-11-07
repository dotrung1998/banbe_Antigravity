-- LOCAL TEST HARNESS ONLY — never deployed, never run against a real project.
-- Migration 194: switch defs table, push_enabled switch, token environment/zone, server-side mute, promotional opt-in,
-- quiet hours, claim/complete incl. dry-run rows, expiry, kick. Runs after the full chain + 01_seed.sql; rolled back.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', coalesce(u::text, ''), true) $$;
CREATE FUNCTION pg_temp.notify(u uuid, k text) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO notifications (recipient_id, kind, title, body, data) VALUES (u, k, 'T ' || k, 'B', '{"booking_id":"b1"}') RETURNING id $$;
CREATE FUNCTION pg_temp.push_on(v boolean) RETURNS void LANGUAGE sql AS $$
  UPDATE app_feature_flags SET enabled = v WHERE key = 'push_enabled' $$;
-- A real zone that is between 07:00 and 21:59 right now, so "due now" checks never depend on the clock.
CREATE FUNCTION pg_temp.awake_zone() RETURNS text LANGUAGE sql AS $$
  SELECT z FROM unnest(ARRAY['Asia/Ho_Chi_Minh','Europe/London','America/New_York','America/Los_Angeles','Pacific/Kiritimati','Asia/Tokyo']) z
   WHERE extract(hour FROM now() AT TIME ZONE z) BETWEEN 7 AND 21 LIMIT 1 $$;
CREATE FUNCTION pg_temp.err(sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $$;

DO $t$
DECLARE
  goer uuid := '7a000001-0000-4000-8000-000000000001';
  host uuid := '7a000002-0000-4000-8000-000000000002';
  other uuid := '7a000003-0000-4000-8000-000000000003';
  tok text := repeat('ab', 32);
  r jsonb; n uuid; n2 uuid; c int; t timestamptz;
BEGIN
  -- ===== P0 switches + privileges
  PERFORM pg_temp.ok((SELECT NOT enabled FROM app_feature_flags WHERE key = 'push_enabled'), 'P0a push_enabled seeded OFF');
  PERFORM pg_temp.ok((SELECT count(*) = 4 FROM app_feature_flag_defs WHERE key IN ('rewards', 'admin_event_wipe', 'rewards_v2', 'push_enabled')),
                     'P0b switch defs hold the old keys + push_enabled');
  PERFORM pg_temp.ok(pg_temp.err($q$INSERT INTO app_feature_flags (key, enabled) VALUES ('not_a_switch', true)$q$) IS NOT NULL,
                     'P0c an unknown switch key is refused (FK)');
  PERFORM pg_temp.ok(NOT has_table_privilege('authenticated', 'public.app_feature_flag_defs', 'SELECT'), 'P0d defs not readable by clients');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', 'public.register_push_token(text,text,text,text,text)', 'EXECUTE')
                     AND NOT has_function_privilege('anon', 'public.register_push_token(text,text,text,text,text)', 'EXECUTE'), 'P0e register: authenticated only');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', 'public.unregister_push_token(text)', 'EXECUTE')
                     AND NOT has_function_privilege('anon', 'public.unregister_push_token(text)', 'EXECUTE'), 'P0f unregister: authenticated only');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.push_claim(integer)', 'EXECUTE')
                     AND NOT has_function_privilege('anon', 'public.push_claim(integer)', 'EXECUTE')
                     AND has_function_privilege('service_role', 'public.push_claim(integer)', 'EXECUTE'), 'P0g claim: service_role only');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.push_complete(jsonb)', 'EXECUTE')
                     AND has_function_privilege('service_role', 'public.push_complete(jsonb)', 'EXECUTE'), 'P0h complete: service_role only');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.push_kick()', 'EXECUTE')
                     AND NOT has_function_privilege('authenticated', 'public.push_drain_tick()', 'EXECUTE')
                     AND NOT has_function_privilege('authenticated', 'public.app_flag(text,boolean)', 'EXECUTE')
                     AND NOT has_function_privilege('authenticated', 'public.push_quiet_until(text,timestamp with time zone)', 'EXECUTE'), 'P0i helpers internal');
  PERFORM pg_temp.ok(NOT has_table_privilege('authenticated', 'public.push_outbox', 'SELECT')
                     AND NOT has_table_privilege('anon', 'public.push_outbox', 'SELECT')
                     AND NOT has_table_privilege('authenticated', 'public.notification_preferences', 'SELECT'), 'P0j outbox + prefs not readable by clients');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bb_push_drain_tick' AND schedule = '* * * * *'), 'P0k per-minute tick scheduled');

  -- ===== P1 token registration
  PERFORM pg_temp.as_user(NULL);
  PERFORM pg_temp.ok(public.register_push_token(tok)->>'error' = 'AUTH_REQUIRED', 'P1a signed out refused');
  PERFORM pg_temp.as_user(host);
  r := public.register_push_token(upper(tok), 'ios', 'sandbox', 'com.banbe.ios', 'America/Los_Angeles');
  PERFORM pg_temp.ok((r->>'success')::boolean, 'P1b register ok');
  PERFORM pg_temp.ok((SELECT environment = 'sandbox' AND app_id = 'com.banbe.ios' AND timezone = 'America/Los_Angeles' AND user_id = host
                        FROM device_push_tokens WHERE token = tok), 'P1c stored lowercased with environment, app id, zone');
  PERFORM pg_temp.ok(public.register_push_token(tok, 'ios', 'staging')->>'error' = 'INVALID_VALUE', 'P1d unknown environment refused');
  r := public.register_push_token(p_token => repeat('cd', 32), p_platform => 'ios');
  PERFORM pg_temp.ok((r->>'success')::boolean
                     AND (SELECT environment = 'production' AND timezone IS NULL FROM device_push_tokens WHERE token = repeat('cd', 32)),
                     'P1e old 2-arg call still works (production, no zone)');
  r := public.register_push_token(repeat('cd', 32), 'ios', 'production', NULL, 'Mars/Olympus');
  PERFORM pg_temp.ok((r->>'success')::boolean AND (SELECT timezone IS NULL FROM device_push_tokens WHERE token = repeat('cd', 32)),
                     'P1f unknown zone is dropped, not an error');
  PERFORM pg_temp.as_user(goer);
  PERFORM public.register_push_token(repeat('ef', 32), 'ios', 'production', 'com.banbe.ios', pg_temp.awake_zone());

  -- ===== P2 switch OFF: nothing queued, nothing claimed
  PERFORM pg_temp.as_user(NULL);
  n := pg_temp.notify(goer, 'payment_confirmed');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM push_outbox WHERE notification_id = n), 'P2a switch off: nothing queued');
  PERFORM pg_temp.push_on(true);
  n := pg_temp.notify(goer, 'payment_confirmed');
  PERFORM pg_temp.push_on(false);
  PERFORM pg_temp.ok(jsonb_array_length(public.push_claim(10)) = 0
                     AND (SELECT status = 'pending' FROM push_outbox WHERE notification_id = n), 'P2b switch off: drain claims nothing');
  DELETE FROM push_outbox;
  PERFORM pg_temp.push_on(true);

  -- ===== P3 enqueue rules (switch ON)
  n := pg_temp.notify(goer, 'payment_confirmed');
  PERFORM pg_temp.ok((SELECT status = 'pending' AND attempts = 0 FROM push_outbox WHERE notification_id = n), 'P3a queued for a device owner');
  n2 := pg_temp.notify(other, 'payment_confirmed');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM push_outbox WHERE notification_id = n2), 'P3b no device token: nothing queued');
  UPDATE profiles SET muted_notification_kinds = ARRAY['new_message'] WHERE id = goer;
  n2 := pg_temp.notify(goer, 'new_message');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM push_outbox WHERE notification_id = n2), 'P3c muted kind: nothing queued (server-side)');
  n2 := pg_temp.notify(goer, 'weekly_digest');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM push_outbox WHERE notification_id = n2), 'P3d promotional kind without opt-in: nothing queued');
  PERFORM pg_temp.as_user(goer);
  PERFORM pg_temp.ok((public.get_my_notification_preferences()->>'promo_push')::boolean = false, 'P3e promo push defaults OFF');
  PERFORM public.set_my_promo_push(true);
  PERFORM pg_temp.as_user(NULL);
  n2 := pg_temp.notify(goer, 'weekly_digest');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM push_outbox WHERE notification_id = n2), 'P3f promotional kind after opt-in: queued');
  DELETE FROM push_outbox WHERE notification_id = n2;
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM net.http_request_queue), 'P3g no Vault secrets: nothing is called');

  -- ===== P4 quiet hours (device zone)
  PERFORM pg_temp.ok(public.push_quiet_until('Asia/Ho_Chi_Minh', timestamptz '2027-03-06T16:30:00Z') = timestamptz '2027-03-07T00:00:00Z',
                     'P4a 23:30 in Saigon waits until 07:00 there');
  PERFORM pg_temp.ok(public.push_quiet_until('Asia/Ho_Chi_Minh', timestamptz '2027-03-06T20:00:00Z') = timestamptz '2027-03-07T00:00:00Z',
                     'P4b 03:00 in Saigon waits until 07:00 the same morning');
  PERFORM pg_temp.ok(public.push_quiet_until('Asia/Ho_Chi_Minh', timestamptz '2027-03-06T12:00:00Z') = timestamptz '2027-03-06T12:00:00Z',
                     'P4c 19:00 in Saigon goes now');
  PERFORM pg_temp.ok(public.push_quiet_until('America/Los_Angeles', timestamptz '2027-03-07T07:00:00Z') = timestamptz '2027-03-07T15:00:00Z',
                     'P4d 23:00 in Los Angeles waits until 07:00 PST');
  PERFORM pg_temp.ok(public.push_quiet_until(NULL, timestamptz '2027-03-06T16:30:00Z') = timestamptz '2027-03-07T00:00:00Z',
                     'P4e no zone known: Saigon default');
  t := public.push_quiet_until('America/Los_Angeles', now());
  n2 := pg_temp.notify(host, 'booking_requested');
  PERFORM pg_temp.ok((SELECT not_before = t FROM push_outbox WHERE notification_id = n2), 'P4f queued row waits for the device''s own morning when needed');
  UPDATE push_outbox SET not_before = now() + interval '3 hours' WHERE notification_id = n2;
  r := public.push_claim(10);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE (x->>'notification_id')::uuid = n2)
                     AND (SELECT status = 'pending' FROM push_outbox WHERE notification_id = n2), 'P4g a quiet-hours row is not claimed early');
  PERFORM public.push_complete((SELECT jsonb_agg(jsonb_build_object('id', x->>'id', 'status', 'failed')) FROM jsonb_array_elements(r) x));
  UPDATE push_outbox SET not_before = now() - interval '1 minute' WHERE status = 'pending';

  -- ===== P5 claim
  r := public.push_claim(10);
  PERFORM pg_temp.ok(jsonb_array_length(r) = 2, 'P5a claims both due pushes');
  PERFORM pg_temp.ok((SELECT x->>'title' = 'T booking_requested' AND (x->>'badge')::int >= 1
                             AND jsonb_array_length(x->'tokens') = 2 AND x->'data'->>'booking_id' = 'b1'
                        FROM jsonb_array_elements(r) x WHERE (x->>'notification_id')::uuid = n2), 'P5b item has title, badge, routing data, both host tokens');
  PERFORM pg_temp.ok((SELECT bool_and(status = 'sending') FROM push_outbox WHERE status <> 'expired'), 'P5c claimed rows are sending');
  r := public.push_claim(10);
  PERFORM pg_temp.ok(jsonb_array_length(r) = 0, 'P5d a second drain claims nothing (no double send)');

  -- ===== P6 complete: sent + gone + moved; dry-run rows; failed back to pending
  r := public.push_complete(jsonb_build_array(
    jsonb_build_object('id', (SELECT id FROM push_outbox WHERE notification_id = n2), 'status', 'sent',
                       'gone_tokens', jsonb_build_array(repeat('cd', 32)),
                       'moved_tokens', jsonb_build_array(jsonb_build_object('token', tok, 'environment', 'production'))),
    jsonb_build_object('id', (SELECT id FROM push_outbox WHERE notification_id = n), 'status', 'failed', 'error', '503:ServiceUnavailable')));
  PERFORM pg_temp.ok((SELECT status = 'sent' AND finished_at IS NOT NULL FROM push_outbox WHERE notification_id = n2), 'P6a sent recorded');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM device_push_tokens WHERE token = repeat('cd', 32)), 'P6b gone token deleted');
  PERFORM pg_temp.ok((SELECT environment = 'production' FROM device_push_tokens WHERE token = tok), 'P6c moved token environment fixed');
  PERFORM pg_temp.ok((SELECT status = 'pending' AND last_error LIKE '503%' AND not_before > now() FROM push_outbox WHERE notification_id = n),
                     'P6d failed goes back to pending, after a backoff');
  r := public.push_claim(10);
  PERFORM pg_temp.ok(jsonb_array_length(r) = 0, 'P6e backoff: not retried in the same drain pass');
  UPDATE push_outbox SET not_before = now() WHERE notification_id = n;
  r := public.push_claim(10);
  PERFORM public.push_complete(jsonb_build_array(jsonb_build_object('id', (SELECT id FROM push_outbox WHERE notification_id = n),
                                                                    'status', 'skipped_no_credentials', 'error', 'dry_run')));
  PERFORM pg_temp.ok((SELECT status = 'skipped_no_credentials' AND finished_at IS NOT NULL FROM push_outbox WHERE notification_id = n),
                     'P6f dry run (no credentials) closes the row as skipped_no_credentials');

  -- ===== P7 retries, read, stale, muted later
  n := pg_temp.notify(goer, 'booking_cancelled');
  FOR c IN 1..3 LOOP
    r := public.push_claim(10);
    PERFORM public.push_complete(jsonb_build_array(jsonb_build_object('id', (SELECT id FROM push_outbox WHERE notification_id = n), 'status', 'failed')));
    UPDATE push_outbox SET not_before = now() WHERE notification_id = n;   -- skip the backoff wait
  END LOOP;
  r := public.push_claim(10);
  PERFORM pg_temp.ok(jsonb_array_length(r) = 0 AND (SELECT status = 'expired' FROM push_outbox WHERE notification_id = n), 'P7a gives up after 3 attempts');
  n := pg_temp.notify(goer, 'event_approved');
  UPDATE notifications SET read_at = now() WHERE id = n;
  r := public.push_claim(10);
  PERFORM pg_temp.ok(jsonb_array_length(r) = 0 AND (SELECT status = 'skipped' FROM push_outbox WHERE notification_id = n), 'P7b already read in the app: not pushed');
  n := pg_temp.notify(goer, 'event_approved');
  UPDATE push_outbox SET not_before = now() - interval '16 minutes' WHERE notification_id = n;
  PERFORM public.push_drain_tick();
  PERFORM pg_temp.ok((SELECT status = 'expired' FROM push_outbox WHERE notification_id = n), 'P7c stale push expires (no flood when switched on later)');
  n := pg_temp.notify(goer, 'event_approved');
  UPDATE profiles SET muted_notification_kinds = ARRAY['event_approved'] WHERE id = goer;
  r := public.push_claim(10);
  PERFORM pg_temp.ok(jsonb_array_length(r) = 0 AND (SELECT status = 'skipped' FROM push_outbox WHERE notification_id = n), 'P7d muted after queueing: not pushed');

  -- ===== P8 unregister (sign-out); account deletion cascades
  PERFORM pg_temp.as_user(other);
  r := public.unregister_push_token(tok);
  PERFORM pg_temp.ok((r->>'removed')::int = 0 AND EXISTS (SELECT 1 FROM device_push_tokens WHERE token = tok), 'P8a someone else cannot remove my token');
  PERFORM pg_temp.as_user(host);
  r := public.unregister_push_token(upper(tok));
  PERFORM pg_temp.ok((r->>'removed')::int = 1 AND NOT EXISTS (SELECT 1 FROM device_push_tokens WHERE token = tok), 'P8b owner removes it on sign-out');
  PERFORM pg_temp.ok((SELECT confdeltype = 'c' FROM pg_constraint WHERE conrelid = 'public.device_push_tokens'::regclass AND contype = 'f'),
                     'P8c tokens cascade with the account');

  -- ===== P9 kick with Vault secrets: one request per transaction, bearer from Vault
  PERFORM vault.create_secret('http://127.0.0.1:9/api/cron?job=push-drain', 'push_drain_url');
  PERFORM vault.create_secret('test-secret', 'push_drain_secret');
  PERFORM pg_temp.as_user(NULL);
  UPDATE profiles SET muted_notification_kinds = '{}' WHERE id = goer;
  PERFORM pg_temp.notify(goer, 'payment_confirmed');
  PERFORM pg_temp.notify(goer, 'booking_cancelled');
  SELECT count(*) INTO c FROM net.http_request_queue WHERE url = 'http://127.0.0.1:9/api/cron?job=push-drain';
  PERFORM pg_temp.ok(c = 1, 'P9a two pushes in one transaction wake the drain once');
  PERFORM pg_temp.ok((SELECT headers->>'Authorization' = 'Bearer test-secret' FROM net.http_request_queue LIMIT 1), 'P9b bearer comes from Vault');

  -- ===== P10 a broken push path never blocks the notification itself
  ALTER TABLE push_outbox RENAME TO push_outbox_hidden;
  n := pg_temp.notify(goer, 'payment_confirmed');
  ALTER TABLE push_outbox_hidden RENAME TO push_outbox;
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM notifications WHERE id = n), 'P10 notification inserted even when enqueue fails');

  RAISE NOTICE 'PUSH RESULT: ALL PASS';
END $t$;

ROLLBACK;
