-- LOCAL TEST HARNESS ONLY — never deployed, never run against a real project.
-- Migration 191: removed-event reversal + restore, attendance window, server-side Rewards switch, legacy check_in.
-- Runs after the full chain + 01_seed.sql; self-contained fixtures (ids prefixed 7f / rf_), rolled back at the end.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', u::text, true) $$;
CREATE FUNCTION pg_temp.bal(u uuid) RETURNS int LANGUAGE sql AS $$ SELECT public.rewards_balance(u) $$;
CREATE FUNCTION pg_temp.mkuser(u uuid, email text, handle text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id,email,phone,phone_confirmed_at,raw_user_meta_data,confirmed_at)
  VALUES (u,email,'+8490002'||substr(handle,2,4),now(),jsonb_build_object('display_name',handle),now()) ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles (id,display_name,handle,role,phone,phone_verified)
  VALUES (u,handle,handle,'participant','+8490002'||substr(handle,2,4),true) ON CONFLICT (id) DO NOTHING;
  INSERT INTO account_phone_grandfathered(user_id,cohort) VALUES (u,'t') ON CONFLICT DO NOTHING;
END $$;
CREATE FUNCTION pg_temp.mkev(id text, org text, starts timestamptz, cat text DEFAULT 'music') RETURNS void LANGUAGE sql AS $$
  INSERT INTO events (id,key,name,organizer_id,status,price_vnd,capacity,starts_at,seats_remaining,cat_key)
  VALUES (id,id,'Event '||id,org,'live',0,50,starts,50,cat) ON CONFLICT (id) DO NOTHING $$;
CREATE FUNCTION pg_temp.mkbook(ev text, u uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE b uuid := gen_random_uuid();
BEGIN
  INSERT INTO bookings (id,event_id,user_id,purchaser_id,qty,total_vnd,code,status,payment_state,paid_marked_at)
  VALUES (b,ev,u,u,1,0,'RF-'||substr(b::text,1,8),'confirmed','confirmed',now());
  RETURN b;
END $$;
CREATE FUNCTION pg_temp.checkin(b uuid, as_uid uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN PERFORM pg_temp.as_user(as_uid); RETURN public.check_in_guest(b,'manual'); END $$;
CREATE FUNCTION pg_temp.last_reason(u uuid, ev text) RETURNS text LANGUAGE sql AS $$
  SELECT reason FROM public.reward_ledger WHERE user_id=u AND source_key LIKE 'attend:'||ev||':%' ORDER BY created_at DESC, source_key DESC LIMIT 1 $$;
CREATE FUNCTION pg_temp.badge(u uuid, code text) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN PERFORM pg_temp.as_user(u); RETURN (SELECT x FROM jsonb_array_elements(public.get_my_rewards()->'badges') x WHERE x->>'code'=code); END $$;

CREATE FUNCTION pg_temp.setstatus(ev text, st text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN  -- what admin_remove_events / admin_restore_events do (189): open the removal guard for this transaction
  PERFORM set_config('app.event_removal_allowed', '1', true);
  UPDATE events SET status = st::event_status, removed_at = CASE WHEN st = 'removed' THEN now() END WHERE id = ev;
  PERFORM set_config('app.event_removal_allowed', '', true);
END $$;

DO $t$
DECLARE
  host  uuid := '7f0a0001-0000-4000-8000-000000000001';
  g1    uuid := '7f0a0002-0000-4000-8000-000000000002';
  g2    uuid := '7f0a0003-0000-4000-8000-000000000003';
  b uuid; r jsonb; n int; n2 int; v0 int; i int;
BEGIN
  PERFORM pg_temp.mkuser(host,'rfh@test.dev','u7fh01'); PERFORM pg_temp.mkuser(g1,'rf1@test.dev','u7f102');
  PERFORM pg_temp.mkuser(g2,'rf2@test.dev','u7f203');
  INSERT INTO organizers (id,name,owner_id,user_id) VALUES ('rf_org','Org rf',host,host);

  -- ===== F0 rules / privileges
  PERFORM pg_temp.ok((SELECT count(*) FROM reward_rule_versions WHERE is_active) = 1, 'F0a exactly one active rules version');
  PERFORM pg_temp.ok((SELECT version = 2 AND rules ? 'attendance_window_before_hours' AND rules ? 'attendance_window_after_hours'
                        FROM reward_rule_versions WHERE is_active), 'F0b rules v2 carries the attendance window');
  PERFORM pg_temp.ok((SELECT rules - 'attendance_window_before_hours' - 'attendance_window_after_hours' FROM reward_rule_versions WHERE version = 2)
                     = (SELECT rules FROM reward_rule_versions WHERE version = 1), 'F0c v2 = v1 + window, nothing else changed');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.check_in(text, boolean)', 'EXECUTE'), 'F0d legacy check_in is no longer callable by clients');
  PERFORM pg_temp.ok(NOT has_function_privilege('anon', 'public.check_in(text, boolean)', 'EXECUTE'), 'F0e … nor by anon');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', 'public.check_in_guest(uuid, text)', 'EXECUTE'), 'F0f check_in_guest still callable');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.rewards_flag(text, boolean)', 'EXECUTE'), 'F0g flag helper is internal');

  -- ===== F1 attendance window
  PERFORM pg_temp.mkev('rf_now', 'rf_org', now());
  b := pg_temp.mkbook('rf_now', g1); r := pg_temp.checkin(b, host);
  PERFORM pg_temp.ok(pg_temp.bal(g1) = 20 AND pg_temp.last_reason(g1,'rf_now') = 'attendance', 'F1a check-in at the start pays 20');
  PERFORM pg_temp.mkev('rf_soon', 'rf_org', now() + interval '2 hours 50 minutes');
  b := pg_temp.mkbook('rf_soon', g1); r := pg_temp.checkin(b, host);
  PERFORM pg_temp.ok(pg_temp.bal(g1) = 40, 'F1b 2h50 before the start is inside the window');
  PERFORM pg_temp.mkev('rf_early', 'rf_org', now() + interval '3 hours 10 minutes');
  b := pg_temp.mkbook('rf_early', g1); r := pg_temp.checkin(b, host);
  PERFORM pg_temp.ok(pg_temp.bal(g1) = 40 AND pg_temp.last_reason(g1,'rf_early') = 'off_window', 'F1c 3h10 before the start pays 0 (off_window)');
  PERFORM pg_temp.ok((SELECT valid FROM reward_attendances WHERE user_id = g1 AND event_id = 'rf_early'), 'F1d … but it is still a valid attendance');
  PERFORM pg_temp.mkev('rf_late', 'rf_org', now() - interval '23 hours');
  b := pg_temp.mkbook('rf_late', g1); r := pg_temp.checkin(b, host);
  PERFORM pg_temp.ok(pg_temp.bal(g1) = 60, 'F1e 23h after the start is inside the window');
  PERFORM pg_temp.mkev('rf_old', 'rf_org', now() - interval '30 hours');
  b := pg_temp.mkbook('rf_old', g1); r := pg_temp.checkin(b, host);
  PERFORM pg_temp.ok(pg_temp.bal(g1) = 60 AND pg_temp.last_reason(g1,'rf_old') = 'off_window', 'F1f 30h after the start pays 0');
  PERFORM pg_temp.ok(public.rewards_month_paid_count(g1) = 3, 'F1g off-window zeros do not use up the monthly cap');
  PERFORM pg_temp.ok((pg_temp.badge(g1,'regular')->>'progress')::int = 5, 'F1h off-window attendances still count toward badges');
  INSERT INTO events (id,key,name,organizer_id,status,price_vnd,capacity,starts_at,seats_remaining,cat_key)
  VALUES ('rf_nostart','rf_nostart','No start','rf_org','live',0,50,NULL,50,'music');
  b := pg_temp.mkbook('rf_nostart', g1); r := pg_temp.checkin(b, host);
  PERFORM pg_temp.ok(pg_temp.bal(g1) = 80, 'F1i an event without starts_at is not judged');

  -- ===== F2 removed events reverse; restoring re-validates using the ORIGINAL check-in time
  v0 := pg_temp.bal(g2);
  PERFORM pg_temp.mkev('rf_rm', 'rf_org', now() - interval '30 hours');
  b := pg_temp.mkbook('rf_rm', g2); r := pg_temp.checkin(b, host);
  PERFORM pg_temp.ok(pg_temp.bal(g2) = v0 AND pg_temp.last_reason(g2,'rf_rm') = 'off_window', 'F2a late check-in (now) pays 0');
  UPDATE check_ins SET checked_in_at = (SELECT starts_at FROM events WHERE id = 'rf_rm') + interval '1 hour' WHERE booking_id = b;
  PERFORM pg_temp.setstatus('rf_rm','removed');
  PERFORM pg_temp.ok(NOT (SELECT valid FROM reward_attendances WHERE user_id = g2 AND event_id = 'rf_rm'), 'F2b removing the event invalidates the attendance');
  PERFORM pg_temp.setstatus('rf_rm','live');
  PERFORM pg_temp.ok((SELECT valid FROM reward_attendances WHERE user_id = g2 AND event_id = 'rf_rm'), 'F2c restoring it re-validates');
  PERFORM pg_temp.ok(pg_temp.bal(g2) = v0 + 20 AND pg_temp.last_reason(g2,'rf_rm') = 'attendance',
                     'F2d the restore is judged on the recorded check-in time (start + 1h) -> pays 20');

  PERFORM pg_temp.mkev('rf_rm2', 'rf_org', now());
  b := pg_temp.mkbook('rf_rm2', g2); r := pg_temp.checkin(b, host);
  n := pg_temp.bal(g2);
  PERFORM pg_temp.setstatus('rf_rm2','removed');
  PERFORM pg_temp.ok(pg_temp.bal(g2) = n - 20, 'F2e removing an event reverses its coins');
  PERFORM pg_temp.ok((SELECT count(*) FROM reward_ledger WHERE user_id = g2 AND entry_type = 'reversal' AND reason = 'attendance_reversed'
                       AND reverses_id IN (SELECT id FROM reward_ledger WHERE source_key LIKE 'attend:rf_rm2:%')) = 1, 'F2f exactly one reversal row');
  n2 := (SELECT count(*) FROM reward_ledger WHERE user_id = g2);
  PERFORM public.rewards_sync_booking(b);
  UPDATE events SET name = name || ' (edited)' WHERE id = 'rf_rm2';  -- no status change: trigger must not fire
  PERFORM pg_temp.ok((SELECT count(*) FROM reward_ledger WHERE user_id = g2) = n2, 'F2g re-syncing a removed event writes nothing');

  -- ===== F3 host milestone follows removal of an ENDED event
  FOR i IN 1..3 LOOP
    PERFORM pg_temp.mkev('rf_h'||i, 'rf_org', now());
    b := pg_temp.mkbook('rf_h'||i, g2); r := pg_temp.checkin(b, host);
    UPDATE events SET status = 'ended' WHERE id = 'rf_h'||i;
  END LOOP;
  PERFORM pg_temp.ok((pg_temp.badge(host,'host_milestone')->>'earned')::boolean, 'F3a 3 ended events with a guest -> host milestone');
  PERFORM pg_temp.setstatus('rf_h3','removed');
  PERFORM pg_temp.ok(NOT (pg_temp.badge(host,'host_milestone')->>'earned')::boolean, 'F3b removing one of them revokes it');
  PERFORM pg_temp.setstatus('rf_h3','ended');
  PERFORM pg_temp.ok((pg_temp.badge(host,'host_milestone')->>'earned')::boolean, 'F3c restoring it to ended earns it back');

  -- ===== F4 cancelled still reverses (regression)
  PERFORM pg_temp.mkev('rf_cx', 'rf_org', now());
  b := pg_temp.mkbook('rf_cx', g2); r := pg_temp.checkin(b, host);
  n := pg_temp.bal(g2);
  UPDATE events SET status = 'cancelled' WHERE id = 'rf_cx';
  PERFORM pg_temp.ok(pg_temp.bal(g2) = n - 20, 'F4 cancelling still reverses');

  -- ===== F5 server-side Rewards switch
  UPDATE app_feature_flags SET enabled = false WHERE key = 'rewards';
  PERFORM pg_temp.as_user(g1);
  PERFORM pg_temp.ok(public.redeem_reward('rwd-comet')->>'error' = 'NOT_AVAILABLE', 'F5a switch off: redeem refused');
  PERFORM pg_temp.ok(public.record_active_day('save','rf_now')->>'error' = 'NOT_AVAILABLE', 'F5b switch off: record_active_day refused');
  PERFORM pg_temp.ok(public.set_my_reward_timezone('America/Los_Angeles')->>'error' = 'NOT_AVAILABLE', 'F5c switch off: timezone change refused');
  PERFORM pg_temp.ok((public.get_my_rewards()->>'success')::boolean AND (public.get_my_reward_summary()->>'success')::boolean, 'F5d switch off: reads still answer');
  n := pg_temp.bal(g1);
  PERFORM pg_temp.mkev('rf_off', 'rf_org', now());
  b := pg_temp.mkbook('rf_off', g1); r := pg_temp.checkin(b, host);
  PERFORM pg_temp.ok(pg_temp.bal(g1) = n + 20, 'F5e switch off: awards still accrue on the server');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM reward_unlocks WHERE user_id = g1), 'F5f nothing was redeemed while off');
  DELETE FROM app_feature_flags WHERE key = 'rewards';
  PERFORM pg_temp.as_user(g1);
  PERFORM pg_temp.ok((public.redeem_reward('rwd-comet')->>'success')::boolean, 'F5g missing switch = on (same as the clients)');
  PERFORM pg_temp.ok(pg_temp.bal(g1) = n + 20 - 40, 'F5h … and the redemption was charged once');

  RAISE NOTICE 'FIXES RESULT: ALL PASS';
END
$t$;
ROLLBACK;
