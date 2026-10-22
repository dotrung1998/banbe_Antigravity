-- LOCAL TEST HARNESS ONLY — never deployed, never run against a real project.
-- Migration 192: weekly streak (grace weeks, repair by attending), tiered + seasonal badges, next badge, monthly goal,
-- the 'rewards_v2' switch and payload compatibility. Runs after the full chain + 01_seed.sql; fixtures prefixed
-- 7v / rv_, rolled back at the end. Weeks are built relative to the current local Monday (Asia/Ho_Chi_Minh).
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', u::text, true) $$;
CREATE FUNCTION pg_temp.mkuser(u uuid, handle text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id,email,phone,phone_confirmed_at,raw_user_meta_data,confirmed_at)
  VALUES (u,handle||'@test.dev','+8490004'||substr(handle,2,4),now(),jsonb_build_object('display_name',handle),now()) ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles (id,display_name,handle,role,phone,phone_verified)
  VALUES (u,handle,handle,'participant','+8490004'||substr(handle,2,4),true) ON CONFLICT (id) DO NOTHING;
  INSERT INTO account_phone_grandfathered(user_id,cohort) VALUES (u,'t') ON CONFLICT DO NOTHING;
END $$;
-- Monday of the current local week, and active days / valid attendances on (Monday + offset days).
CREATE FUNCTION pg_temp.mon() RETURNS date LANGUAGE sql AS $$ SELECT date_trunc('week', (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date)::date $$;
CREATE FUNCTION pg_temp.days(u uuid, offs int[], src text DEFAULT 'save') RETURNS void LANGUAGE sql AS $$
  INSERT INTO reward_active_days (user_id, local_date, source) SELECT u, pg_temp.mon() + o, src FROM unnest(offs) o ON CONFLICT DO NOTHING $$;
CREATE FUNCTION pg_temp.attend_on(u uuid, ev text, off int, cat text DEFAULT 'music') RETURNS void LANGUAGE sql AS $$
  INSERT INTO reward_active_days (user_id, local_date, source) VALUES (u, pg_temp.mon() + off, 'attendance') ON CONFLICT DO NOTHING;
  INSERT INTO reward_attendances (user_id, event_id, cat_key, valid, first_valid_at)
  VALUES (u, ev, cat, true, ((pg_temp.mon() + off)::timestamp + interval '12 hours') AT TIME ZONE 'Asia/Ho_Chi_Minh') $$;
CREATE FUNCTION pg_temp.ws(u uuid) RETURNS jsonb LANGUAGE sql AS $$ SELECT public.rewards_week_streak_of(u) $$;
CREATE FUNCTION pg_temp.wk(n int) RETURNS int[] LANGUAGE sql AS $$ SELECT ARRAY[n * 7] $$;  -- one day (Monday) in week n
CREATE FUNCTION pg_temp.wks(a int, b int) RETURNS int[] LANGUAGE sql AS $$ SELECT array_agg(n * 7) FROM generate_series(a, b) n $$;
CREATE FUNCTION pg_temp.badge(u uuid, code text) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN PERFORM pg_temp.as_user(u); RETURN (SELECT x FROM jsonb_array_elements(public.get_my_rewards()->'badges') x WHERE x->>'code'=code); END $$;
CREATE FUNCTION pg_temp.set_flag(k text, v boolean) RETURNS void LANGUAGE sql AS $$
  INSERT INTO app_feature_flags (key, enabled) VALUES (k, v) ON CONFLICT (key) DO UPDATE SET enabled = v $$;
CREATE FUNCTION pg_temp.set_start(d date) RETURNS void LANGUAGE sql AS $$
  UPDATE reward_rule_versions SET rules = jsonb_set(rules, '{week_streak,start}', to_jsonb(to_char(d, 'YYYY-MM-DD'))) WHERE is_active $$;

DO $t$
DECLARE
  u uuid; r jsonb; i int; n int;
  ids uuid[] := ARRAY(SELECT ('7f1a00' || lpad(g::text, 2, '0') || '-0000-4000-8000-0000000000' || lpad(g::text, 2, '0'))::uuid FROM generate_series(1, 40) g);
BEGIN
  FOR i IN 1..40 LOOP PERFORM pg_temp.mkuser(ids[i], 'u7v' || lpad(i::text, 3, '0')); END LOOP;
  -- Grace/repair history needs to be after the v2 start; most cases use a start a year back.
  PERFORM pg_temp.set_start(pg_temp.mon() - 365);

  -- ===== W0 rules / privileges / switch
  PERFORM pg_temp.ok((SELECT version = 3 FROM reward_rule_versions WHERE is_active), 'W0a rules v3 active');
  PERFORM pg_temp.ok((SELECT (rules - 'week_streak') = (SELECT rules FROM reward_rule_versions WHERE version = 2) FROM reward_rule_versions WHERE version = 3),
                     'W0b v3 = v2 + week_streak, nothing else changed');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.rewards_week_streak_of(uuid)', 'EXECUTE'), 'W0c week streak helper is internal');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.rewards_goal_of(uuid)', 'EXECUTE'), 'W0d goal helper is internal');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', 'public.set_my_outing_goal(integer)', 'EXECUTE')
                     AND NOT has_function_privilege('anon', 'public.set_my_outing_goal(integer)', 'EXECUTE'), 'W0e goal RPC: authenticated only');
  PERFORM pg_temp.ok((SELECT NOT enabled FROM app_feature_flags WHERE key = 'rewards_v2'), 'W0f rewards_v2 seeded OFF');

  -- ===== W1 weekly streak basics
  u := ids[1];
  r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 0 AND (r->>'longest')::int = 0 AND NOT (r->>'this_week_active')::boolean, 'W1a nothing yet = 0');
  PERFORM pg_temp.days(u, ARRAY[0]); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 1 AND (r->>'this_week_active')::boolean, 'W1b one active day this week = 1, week done');
  u := ids[2]; PERFORM pg_temp.days(u, pg_temp.wk(-1)); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 1 AND NOT (r->>'this_week_active')::boolean, 'W1c last week only: still alive while this week is open');
  u := ids[3]; PERFORM pg_temp.days(u, pg_temp.wks(-3, -1)); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 3, 'W1d three weeks in a row = 3');
  u := ids[4]; PERFORM pg_temp.days(u, ARRAY[-1, 0]); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 2, 'W1e Sunday then Monday = two consecutive weeks');
  u := ids[5]; PERFORM pg_temp.days(u, ARRAY[-7, -6, -5, -4, -3, -2, -1]); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 1 AND (r->>'longest')::int = 1, 'W1f seven days in one week = 1 week (no daily farming)');
  u := ids[6]; PERFORM pg_temp.days(u, pg_temp.wk(-3) || pg_temp.wk(-1)); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 1 AND (r->>'grace_used')::int = 0, 'W1g a gap with no grace restarts at 1');
  u := ids[7]; PERFORM pg_temp.days(u, pg_temp.wks(-5, -2)); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 4 AND (r->>'grace_used')::int = 1, 'W1h … but one earned grace week covers a single miss');
  u := ids[8]; PERFORM pg_temp.days(u, pg_temp.wks(-5, -4)); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 0 AND (r->>'longest')::int = 2, 'W1i missed last week, no grace: current 0, longest kept');
  u := ids[9]; PERFORM pg_temp.days(u, ARRAY[30]); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 0, 'W1j a future-dated day never counts');

  -- ===== W2 grace weeks (earned every 4 active weeks, max 2 held, never bought)
  u := ids[10]; PERFORM pg_temp.days(u, pg_temp.wks(-9, -6) || pg_temp.wks(-4, -1)); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 8 AND (r->>'grace_used')::int = 1 AND (r->>'grace_held')::int = 1,
                     'W2a 4 weeks earn a grace, the miss uses it (length kept: 8), 4 more earn another');
  u := ids[11]; PERFORM pg_temp.days(u, pg_temp.wks(-12, -1)); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'grace_held')::int = 2 AND (r->'next_grace_in') = 'null'::jsonb, 'W2b at most 2 held; nothing to earn while full');
  u := ids[12]; PERFORM pg_temp.days(u, pg_temp.wks(-10, -7) || pg_temp.wk(-4)); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 0 AND (r->>'grace_used')::int = 1, 'W2c one grace covers one miss, the second miss breaks');
  u := ids[13]; PERFORM pg_temp.days(u, pg_temp.wks(-2, -1)); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'next_grace_in')::int = 2 AND (r->>'grace_held')::int = 0, 'W2d next grace in 2 more active weeks');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM reward_ledger WHERE user_id = ANY (ids)), 'W2e streaks and grace never write the ledger');

  -- ===== W3 repair by attending (streak >= 4, attendance within 14 days after the missed week)
  -- weeks -10..-7 active (1 grace), -6 missed (grace), -5 missed (break, 4 weeks), attendance in week -4 -> restored
  u := ids[14]; PERFORM pg_temp.days(u, pg_temp.wks(-10, -7) || pg_temp.wks(-3, -1)); PERFORM pg_temp.attend_on(u, 'rv_a1', -4 * 7 + 2);
  r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'repaired')::int = 1 AND (r->>'current')::int = 8, 'W3a an attendance within the window restores 4 + 4 = 8');
  u := ids[15]; PERFORM pg_temp.days(u, pg_temp.wks(-10, -7) || pg_temp.wks(-4, -1)); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'repaired')::int = 0 AND (r->>'current')::int = 4, 'W3b a save cannot repair (restarts at 1 -> 4)');
  u := ids[16]; PERFORM pg_temp.days(u, pg_temp.wks(-10, -7) || pg_temp.wk(-1)); PERFORM pg_temp.attend_on(u, 'rv_a2', -2 * 7);
  r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'repaired')::int = 0 AND (r->>'current')::int = 2, 'W3c an attendance after the window does not repair');
  u := ids[17]; PERFORM pg_temp.days(u, pg_temp.wks(-6, -5) || pg_temp.wk(-1)); PERFORM pg_temp.attend_on(u, 'rv_a3', -3 * 7);
  r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'repaired')::int = 0, 'W3d a 2-week streak is too short to repair');
  u := ids[18]; PERFORM pg_temp.days(u, pg_temp.wks(-7, -4)); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 0 AND (r->'repair'->>'weeks')::int = 4 AND (r->'repair'->>'until')::date >= pg_temp.mon(),
                     'W3e an open repair window is reported (4 weeks, a real date)');
  PERFORM pg_temp.attend_on(u, 'rv_a4', 0); r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'current')::int = 5 AND r->'repair' = 'null'::jsonb, 'W3f attending this week restores 4 + 1 = 5');
  UPDATE reward_attendances SET valid = false WHERE user_id = u AND event_id = 'rv_a4'; r := pg_temp.ws(u);
  PERFORM pg_temp.ok((r->>'repaired')::int = 0, 'W3g an attendance that is no longer valid repairs nothing');

  -- ===== W4 not retroactive: before week_streak.start nothing earns grace or opens a repair
  PERFORM pg_temp.set_start(pg_temp.mon());
  r := pg_temp.ws(ids[10]);
  PERFORM pg_temp.ok((r->>'grace_used')::int = 0 AND (r->>'current')::int = 4, 'W4a history before the start: no grace (miss breaks)');
  r := pg_temp.ws(ids[18]);
  PERFORM pg_temp.ok(r->'repair' = 'null'::jsonb OR (r->>'repaired')::int = 0, 'W4b history before the start: no repair window');
  PERFORM pg_temp.set_start(pg_temp.mon() - 365);

  -- ===== W5 user timezone (177) decides "today"
  u := ids[19];
  INSERT INTO reward_user_settings (user_id, tz) VALUES (u, 'America/Los_Angeles');
  PERFORM pg_temp.ok(pg_temp.ws(u)->>'timezone' = 'America/Los_Angeles', 'W5 week streak reports the user zone');

  -- ===== B badges: v1 view while rewards_v2 is off
  u := ids[20];
  FOR i IN 1..26 LOOP
    INSERT INTO reward_attendances (user_id, event_id, cat_key, valid, first_valid_at)
    VALUES (u, 'rv_b' || i, 'cat' || (i % 7), true, now() - make_interval(days => (i % 4) * 32));
  END LOOP;
  PERFORM public.rewards_refresh_badges(u);
  PERFORM pg_temp.as_user(u); r := public.get_my_rewards();
  PERFORM pg_temp.ok(jsonb_array_length(r->'badges') = 6, 'B1a switch off: only the 6 original badges are listed');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM reward_user_badges WHERE user_id = u AND badge_code = 'outings_25' AND revoked_at IS NULL),
                     'B1b … but v2 tiers are earned silently');
  PERFORM pg_temp.ok(r ? 'week_streak' AND r ? 'next_badge' AND r ? 'goal', 'B1c new keys are present');
  PERFORM pg_temp.ok((SELECT bool_and(r ? k) FROM unnest(ARRAY['success','balance','rules','streak','badges','history','catalog','offers',
                       'attendance_paid_this_month','timezone_settings']) k), 'B1d every old key is still there');
  PERFORM pg_temp.ok((SELECT bool_and(x ?& ARRAY['code','title_vi','title_en','desc_vi','desc_en','target','progress','earned','earned_at'])
                        FROM jsonb_array_elements(r->'badges') x), 'B1e every old badge field is still there');

  PERFORM pg_temp.set_flag('rewards_v2', true);
  PERFORM pg_temp.as_user(u); r := public.get_my_rewards();
  PERFORM pg_temp.ok(jsonb_array_length(r->'badges') = 15, 'B2a switch on: 15 badges (seasonal one hidden far from its window)');
  PERFORM pg_temp.ok((pg_temp.badge(u,'outings_25')->>'earned')::boolean AND NOT (pg_temp.badge(u,'outings_50')->>'earned')::boolean,
                     'B2b 26 attendances: tier 4 earned, tier 5 not');
  PERFORM pg_temp.ok((pg_temp.badge(u,'explorer_6')->>'earned')::boolean AND NOT (pg_temp.badge(u,'explorer_10')->>'earned')::boolean,
                     'B2c 7 categories: explorer tier 2 earned, tier 3 not');
  PERFORM pg_temp.ok((pg_temp.badge(u,'months_3')->>'earned')::boolean AND (pg_temp.badge(u,'months_3')->>'progress')::int = 3,
                     'B2d attendances in 4 different months -> months tier 1 (progress capped at target)');
  PERFORM pg_temp.ok(pg_temp.badge(u,'outings_25')->>'family' = 'outings' AND (pg_temp.badge(u,'outings_25')->>'tier')::int = 4, 'B2e family + tier fields');
  PERFORM pg_temp.ok(pg_temp.badge(u,'first_outing')->>'family' = 'outings' AND (pg_temp.badge(u,'community_regular')->>'tier')::int = 3,
                     'B2f original codes are tiers 1-3 of outings');
  UPDATE reward_attendances SET valid = false WHERE user_id = u AND event_id = 'rv_b1';
  UPDATE reward_attendances SET valid = false WHERE user_id = u AND event_id = 'rv_b2';
  PERFORM public.rewards_refresh_badges(u);
  PERFORM pg_temp.ok(NOT (pg_temp.badge(u,'outings_25')->>'earned')::boolean, 'B2g dropping under 25 valid attendances revokes the tier');

  -- next badge
  u := ids[21];
  PERFORM pg_temp.as_user(u); r := public.get_my_rewards();
  PERFORM pg_temp.ok(r->'next_badge'->>'code' = 'ready_to_explore' AND (r->'next_badge'->>'remaining')::int = 1, 'B3a new user: next badge = 1 step away');
  FOR i IN 1..4 LOOP INSERT INTO reward_attendances (user_id, event_id, cat_key, valid) VALUES (u, 'rv_n' || i, 'music', true); END LOOP;
  INSERT INTO reward_ledger (user_id, entry_type, amount, source_key, reason, rules_version) VALUES (u, 'award', 10, 'onboarding:preferences', 'onboarding', 3);
  PERFORM public.rewards_refresh_badges(u);
  PERFORM pg_temp.as_user(u); r := public.get_my_rewards();
  PERFORM pg_temp.ok(r->'next_badge'->>'code' = 'regular' AND (r->'next_badge'->>'remaining')::int = 1, 'B3b 4 of 5 attended: next = Regular, one event away');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'badges') x WHERE x->>'family' = 'host' AND x->>'code' = r->'next_badge'->>'code'),
                     'B3c a non-host is never pointed at a host badge');
  PERFORM pg_temp.ok(public.rewards_badge_progress_of('regular', public.rewards_badge_counts(u)) = 4, 'B3d the old progress_of(code, counts) still answers');

  -- seasonal
  u := ids[22];
  INSERT INTO events (id,key,name,organizer_id,status,price_vnd,capacity,starts_at,seats_remaining,cat_key)
  VALUES ('rv_tet','rv_tet','Tet','test_org_a','live',0,50,TIMESTAMPTZ '2027-02-01 19:00+07',50,'music'),
         ('rv_pre','rv_pre','Pre','test_org_a','live',0,50,TIMESTAMPTZ '2027-01-10 19:00+07',50,'music');
  INSERT INTO reward_attendances (user_id, event_id, cat_key, valid) VALUES (u, 'rv_pre', 'music', true);
  PERFORM public.rewards_refresh_badges(u);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM reward_user_badges WHERE user_id = u AND badge_code = 'season_tet_2027'), 'B4a an event before the window does not count');
  INSERT INTO reward_attendances (user_id, event_id, cat_key, valid) VALUES (u, 'rv_tet', 'music', true);
  PERFORM public.rewards_refresh_badges(u);
  PERFORM pg_temp.ok((pg_temp.badge(u,'season_tet_2027')->>'earned')::boolean, 'B4b an event inside the window earns it, and an earned one is listed');

  -- ===== G monthly goal
  u := ids[23];
  PERFORM pg_temp.set_flag('rewards_v2', false);
  PERFORM pg_temp.as_user(u);
  PERFORM pg_temp.ok(public.set_my_outing_goal(2)->>'error' = 'NOT_AVAILABLE', 'G1 switch off: goal refused');
  PERFORM pg_temp.set_flag('rewards_v2', true);
  PERFORM pg_temp.as_user(u);
  r := public.set_my_outing_goal(2);
  PERFORM pg_temp.ok((r->>'success')::boolean AND (r->'goal'->>'target')::int = 2 AND (r->'goal'->>'progress')::int = 0, 'G2a goal 2 set, progress 0');
  PERFORM pg_temp.ok(public.set_my_outing_goal(3)->>'error' = 'INVALID_GOAL', 'G2b only 1, 2 or 4');
  PERFORM pg_temp.ok(public.set_my_outing_goal(99999)->>'error' = 'INVALID_GOAL', 'G2c a huge number is refused, not an error');
  INSERT INTO reward_attendances (user_id, event_id, cat_key, valid) VALUES (u, 'rv_g1', 'music', true);
  INSERT INTO reward_attendances (user_id, event_id, cat_key, valid, first_valid_at) VALUES (u, 'rv_g0', 'music', true, now() - interval '62 days');
  PERFORM pg_temp.as_user(u);
  PERFORM pg_temp.ok((public.get_my_rewards()->'goal'->>'progress')::int = 1, 'G3 progress counts only this month');
  r := public.set_my_outing_goal(0);
  PERFORM pg_temp.ok((r->>'success')::boolean AND r->'goal'->'target' = 'null'::jsonb, 'G4 0 clears the goal');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM reward_ledger WHERE user_id = u), 'G5 a goal never writes the ledger');
  PERFORM pg_temp.set_flag('rewards', false);
  PERFORM pg_temp.as_user(u);
  PERFORM pg_temp.ok(public.set_my_outing_goal(1)->>'error' = 'NOT_AVAILABLE', 'G6 Rewards switch off: goal refused too');
  PERFORM pg_temp.set_flag('rewards', true);

  -- ===== S summary
  u := ids[3]; PERFORM pg_temp.as_user(u); r := public.get_my_reward_summary();
  PERFORM pg_temp.ok((r->>'week_streak')::int = 3 AND r ? 'week_active' AND r ?& ARRAY['success','balance','streak','active_today'],
                     'S1 summary adds week_streak/week_active and keeps its old keys');

  -- ===== A admin switch accepts the new key
  PERFORM set_config('app.role_change_allowed', '1', true);
  UPDATE profiles SET role = 'admin' WHERE id = ids[24];
  PERFORM set_config('app.role_change_allowed', '', true);
  PERFORM pg_temp.as_user(ids[24]);
  PERFORM pg_temp.ok((public.admin_set_feature_flag('rewards_v2', false)->>'success')::boolean, 'A1 admin can switch rewards_v2');
  PERFORM pg_temp.ok(public.admin_set_feature_flag('nope', true)->>'error' = 'INVALID_VALUE', 'A2 unknown keys still refused');

  RAISE NOTICE 'V2 RESULT: ALL PASS';
END
$t$;
ROLLBACK;
