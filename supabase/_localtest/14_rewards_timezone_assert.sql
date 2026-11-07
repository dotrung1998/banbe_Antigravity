-- LOCAL TEST HARNESS ONLY — never deployed, never run against a real project.
-- Migration 177: per-user rewards timezone. Runs AFTER the full chain (13_rewards_run.sh resets + applies it),
-- on the same throwaway database, so legacy-shaped rows and new users coexist. Rolled back at the end.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', u::text, true) $$;
CREATE FUNCTION pg_temp.mkuser(u uuid, email text, handle text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id,email,phone,phone_confirmed_at,raw_user_meta_data,confirmed_at)
  VALUES (u,email,'+8490002'||substr(handle,2,4),now(),jsonb_build_object('display_name',handle),now()) ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles (id,display_name,handle,role,phone,phone_verified)
  VALUES (u,handle,handle,'participant','+8490002'||substr(handle,2,4),true) ON CONFLICT (id) DO NOTHING;
  INSERT INTO account_phone_grandfathered(user_id,cohort) VALUES (u,'t') ON CONFLICT DO NOTHING;
END $$;
CREATE FUNCTION pg_temp.setz(u uuid, z text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.reward_user_settings (user_id, tz) VALUES (u, z) ON CONFLICT (user_id) DO UPDATE SET tz = EXCLUDED.tz $$;
CREATE FUNCTION pg_temp.ld(u uuid, t text) RETURNS date LANGUAGE sql AS $$ SELECT public.rewards_user_local_date(u, t::timestamptz) $$;

DO $t$
DECLARE
  uvn uuid := '7f0a0001-0000-4000-8000-000000000001';  -- never chose a zone (legacy behaviour)
  upac uuid := '7f0a0002-0000-4000-8000-000000000002'; -- America/Los_Angeles
  uest uuid := '7f0a0003-0000-4000-8000-000000000003'; -- America/New_York
  uset uuid := '7f0a0004-0000-4000-8000-000000000004'; -- uses the RPC
  ustr uuid := '7f0a0005-0000-4000-8000-000000000005'; -- streak through a change
  ulg  uuid := '7f0a0006-0000-4000-8000-000000000006'; -- legacy-shaped ledger rows
  r jsonb; n int; today_vn date; old_n int; keys_before text[]; k text;
BEGIN
  PERFORM pg_temp.mkuser(uvn,'tzv@test.dev','u7fv01');  PERFORM pg_temp.mkuser(upac,'tzp@test.dev','u7fp02');
  PERFORM pg_temp.mkuser(uest,'tze@test.dev','u7fe03'); PERFORM pg_temp.mkuser(uset,'tzs@test.dev','u7fs04');
  PERFORM pg_temp.mkuser(ustr,'tzt@test.dev','u7ft05'); PERFORM pg_temp.mkuser(ulg,'tzl@test.dev','u7fl06');
  PERFORM pg_temp.setz(upac,'America/Los_Angeles'); PERFORM pg_temp.setz(uest,'America/New_York');

  -- ===== V: Vietnamese / never-chosen user behaves exactly like 165
  PERFORM pg_temp.ok(public.rewards_user_tz(uvn) = 'Asia/Ho_Chi_Minh', 'V1 no row -> Asia/Ho_Chi_Minh');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM generate_series(0, 400) h
      WHERE public.rewards_user_local_date(uvn, timestamptz '2026-12-30 00:00+00' + h * interval '37 minutes')
         <> public.rewards_local_date(timestamptz '2026-12-30 00:00+00' + h * interval '37 minutes')), 'V2 local date identical to the legacy function over 400 instants (incl. year end)');
  PERFORM pg_temp.setz(uvn, NULL);
  PERFORM pg_temp.ok(public.rewards_user_tz(uvn) = 'Asia/Ho_Chi_Minh', 'V3 row with NULL tz -> legacy default');
  PERFORM pg_temp.ok(pg_temp.ld(uvn,'2026-10-07 16:59:59+00') = DATE '2026-10-07' AND pg_temp.ld(uvn,'2026-10-07 17:00:00+00') = DATE '2026-10-08', 'V4 midnight boundary VN (17:00Z)');

  -- ===== U: US users
  PERFORM pg_temp.ok(pg_temp.ld(upac,'2026-10-08 06:59:59+00') = DATE '2026-10-07' AND pg_temp.ld(upac,'2026-10-08 07:00:00+00') = DATE '2026-10-08', 'U1 Pacific midnight (PDT = UTC-7) boundary');
  PERFORM pg_temp.ok(pg_temp.ld(uest,'2026-10-08 03:59:59+00') = DATE '2026-10-07' AND pg_temp.ld(uest,'2026-10-08 04:00:00+00') = DATE '2026-10-08', 'U2 Eastern midnight (EDT = UTC-4) boundary');
  PERFORM pg_temp.ok(pg_temp.ld(upac,'2026-12-01 07:59:59+00') = DATE '2026-11-30' AND pg_temp.ld(upac,'2026-12-01 08:00:00+00') = DATE '2026-12-01', 'U3 Pacific month boundary in PST (UTC-8)');
  PERFORM pg_temp.ok(pg_temp.ld(uest,'2027-01-01 04:59:59+00') = DATE '2026-12-31' AND pg_temp.ld(uest,'2027-01-01 05:00:00+00') = DATE '2027-01-01', 'U4 Eastern year boundary in EST (UTC-5)');
  -- DST: spring forward 2027-03-14 (02:00 -> 03:00 PST->PDT), fall back 2026-11-01 (02:00 -> 01:00 PDT->PST)
  PERFORM pg_temp.ok(pg_temp.ld(upac,'2027-03-14 09:59:59+00') = DATE '2027-03-14' AND pg_temp.ld(upac,'2027-03-14 10:00:00+00') = DATE '2027-03-14' AND pg_temp.ld(upac,'2027-03-15 06:59:59+00') = DATE '2027-03-14' AND pg_temp.ld(upac,'2027-03-15 07:00:00+00') = DATE '2027-03-15', 'U5 DST spring-forward day is one local date, next midnight at 07:00Z');
  PERFORM pg_temp.ok(pg_temp.ld(upac,'2026-11-01 08:30:00+00') = DATE '2026-11-01' AND pg_temp.ld(upac,'2026-11-01 09:30:00+00') = DATE '2026-11-01' AND pg_temp.ld(upac,'2026-11-02 07:59:59+00') = DATE '2026-11-01' AND pg_temp.ld(upac,'2026-11-02 08:00:00+00') = DATE '2026-11-02', 'U6 DST fall-back repeats 01:30 but stays one local date');

  -- ===== L: ledger stamping + monthly cap, old and new rows in one DB
  INSERT INTO public.reward_ledger (user_id,entry_type,amount,source_key,rules_version,reason,ref,created_at)  -- legacy shape: NULL period_month
  SELECT ulg,'award',20,'attend:lg'||i||':1',1,'attendance',jsonb_build_object('event_id','lg'||i), now() FROM generate_series(1,3) i;
  PERFORM public.rewards_add_entry(ulg,'award',0,'t:stamp',NULL,'probe','{}');
  PERFORM pg_temp.ok((SELECT period_month FROM public.reward_ledger WHERE user_id=ulg AND source_key='t:stamp') = date_trunc('month', now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
                 AND (SELECT tz_used FROM public.reward_ledger WHERE user_id=ulg AND source_key='t:stamp') = 'Asia/Ho_Chi_Minh', 'L1 new row for a default user stamps VN month + zone');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.reward_ledger WHERE user_id=ulg AND period_month IS NULL) = 3 AND public.rewards_month_paid_count(ulg) = 3, 'L2 legacy rows stay NULL and are still counted by their VN month');
  PERFORM public.rewards_add_entry(upac,'award',20,'attend:p1:1',NULL,'attendance','{"event_id":"p1"}');
  PERFORM pg_temp.ok((SELECT tz_used FROM public.reward_ledger WHERE user_id=upac AND source_key='attend:p1:1') = 'America/Los_Angeles'
                 AND (SELECT period_month FROM public.reward_ledger WHERE user_id=upac AND source_key='attend:p1:1') = date_trunc('month', now() AT TIME ZONE 'America/Los_Angeles')::date, 'L3 Pacific user: new row stamped with the Pacific month + zone');
  -- a row stamped with another month is not this month's
  INSERT INTO public.reward_ledger (user_id,entry_type,amount,source_key,rules_version,reason,ref,period_month,tz_used)
  VALUES (upac,'award',20,'attend:p0:1',1,'attendance','{"event_id":"p0"}', (date_trunc('month', now() AT TIME ZONE 'America/Los_Angeles') - interval '1 month')::date,'America/Los_Angeles');
  PERFORM pg_temp.ok(public.rewards_month_paid_count(upac) = 1, 'L4 a row of last month (by period_month) does not count toward this month');
  -- cap equality: for every default-zone user the new counter equals the 165 formula
  PERFORM pg_temp.ok(public.rewards_month_paid_count(ulg) = (SELECT count(*)::int FROM public.reward_ledger a
      WHERE a.user_id=ulg AND a.entry_type='award' AND a.amount>0 AND a.source_key LIKE 'attend:%'
        AND date_trunc('month', a.created_at AT TIME ZONE public.rewards_tz()) = date_trunc('month', now() AT TIME ZONE public.rewards_tz())
        AND NOT EXISTS (SELECT 1 FROM public.reward_ledger r WHERE r.reverses_id=a.id)), 'L5 default-zone counter == the 165 query');

  -- ===== S: set_my_reward_timezone
  PERFORM pg_temp.as_user(uset);
  PERFORM pg_temp.ok(public.set_my_reward_timezone('EST')->>'error' = 'INVALID_TIMEZONE', 'S1a abbreviation rejected');
  PERFORM pg_temp.ok(public.set_my_reward_timezone('Foo/Bar')->>'error' = 'INVALID_TIMEZONE', 'S1b unknown zone rejected');
  PERFORM pg_temp.ok(public.set_my_reward_timezone('')->>'error' = 'INVALID_TIMEZONE' AND public.set_my_reward_timezone(NULL)->>'error' = 'INVALID_TIMEZONE', 'S1c empty/NULL rejected');
  PERFORM pg_temp.ok(public.set_my_reward_timezone('posix/Asia/Tokyo')->>'error' = 'INVALID_TIMEZONE', 'S1d posix/ alias rejected');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.reward_user_settings WHERE user_id=uset AND (tz IS NOT NULL OR pending_tz IS NOT NULL)), 'S1e rejected calls stored nothing');
  r := public.set_my_reward_timezone('America/New_York');
  PERFORM pg_temp.ok((r->>'success')::boolean AND (r->>'changed')::boolean, 'S2a valid zone accepted');
  PERFORM pg_temp.ok(public.rewards_user_tz(uset) = 'Asia/Ho_Chi_Minh', 'S2b NOT effective yet: still the old zone today');
  PERFORM pg_temp.ok((SELECT pending_from_ts FROM public.reward_user_settings WHERE user_id=uset) = ((now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date + 1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh', 'S2c effective at the start of the next local day (old zone)');
  PERFORM pg_temp.ok(public.rewards_user_tz(uset, now() + interval '25 hours') = 'America/New_York', 'S2d effective once that instant has passed');
  PERFORM pg_temp.ok(public.get_my_rewards() -> 'timezone_settings' ->> 'pending_tz' = 'America/New_York', 'S2e get_my_rewards exposes the pending change');
  r := public.set_my_reward_timezone('Asia/Ho_Chi_Minh');
  PERFORM pg_temp.ok((r->>'success')::boolean AND NOT (r->>'changed')::boolean AND (r->'timezone_settings'->>'pending_tz') IS NULL, 'S3 going back to the zone in force cancels the pending change and is free');
  r := public.set_my_reward_timezone('America/Chicago'); r := public.set_my_reward_timezone('America/Denver');
  PERFORM pg_temp.ok((r->>'success')::boolean AND public.rewards_tz_settings(uset)->>'changes_left' = '1', 'S4a replacing a not-yet-effective request is the same change (1 counted, not 2)');
  UPDATE public.reward_user_settings SET pending_from_ts = now() - interval '1 hour' WHERE user_id = uset;   -- Denver is now in force
  r := public.set_my_reward_timezone('America/Phoenix');
  PERFORM pg_temp.ok((r->>'success')::boolean AND public.rewards_user_tz(uset) = 'America/Denver', 'S4b second effective change within 30 days allowed');
  UPDATE public.reward_user_settings SET pending_from_ts = now() - interval '1 hour' WHERE user_id = uset;
  r := public.set_my_reward_timezone('Europe/Paris');
  PERFORM pg_temp.ok(r->>'error' = 'TZ_CHANGE_LIMIT' AND r->>'next_change_at' IS NOT NULL, 'S4c third effective change within 30 days refused with next_change_at');
  PERFORM pg_temp.ok(public.rewards_tz_settings(uset)->>'changes_left' = '0', 'S4d changes_left = 0');
  -- direct access is closed
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM count(*) FROM public.reward_user_settings; RESET ROLE; RAISE EXCEPTION 'S5a table readable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE authenticated;
  BEGIN UPDATE public.reward_user_settings SET tz='America/Chicago'; RESET ROLE; RAISE EXCEPTION 'S5b table writable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM public.rewards_user_tz(uset); RESET ROLE; RAISE EXCEPTION 'S5c helper callable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE anon;
  BEGIN PERFORM public.set_my_reward_timezone('America/Chicago'); RESET ROLE; RAISE EXCEPTION 'S5d anon rpc'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  BEGIN INSERT INTO public.reward_user_settings (user_id, tz) VALUES (uvn,'Mars/Base') ON CONFLICT (user_id) DO UPDATE SET tz = EXCLUDED.tz; RAISE EXCEPTION 'S5e bad tz stored';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM pg_temp.ok(true, 'S5 table closed to clients, helpers closed, anon refused, trigger rejects bad zones even for a superuser');

  -- ===== B: bridge dates only for eastward moves
  PERFORM pg_temp.mkuser('7f0a0007-0000-4000-8000-000000000007','tzb@test.dev','u7fb07');
  PERFORM pg_temp.setz('7f0a0007-0000-4000-8000-000000000007','America/Los_Angeles');
  PERFORM pg_temp.as_user('7f0a0007-0000-4000-8000-000000000007');
  PERFORM public.set_my_reward_timezone('Asia/Ho_Chi_Minh');
  PERFORM pg_temp.ok((SELECT pending_bridge FROM public.reward_user_settings WHERE user_id='7f0a0007-0000-4000-8000-000000000007') IS NOT NULL, 'B1 eastward (LA -> VN) records a bridge date');
  PERFORM pg_temp.mkuser('7f0a0008-0000-4000-8000-000000000008','tzw@test.dev','u7fw08');
  PERFORM pg_temp.as_user('7f0a0008-0000-4000-8000-000000000008');
  PERFORM public.set_my_reward_timezone('America/Los_Angeles');
  PERFORM pg_temp.ok((SELECT pending_bridge FROM public.reward_user_settings WHERE user_id='7f0a0008-0000-4000-8000-000000000008') IS NULL, 'B2 westward (VN -> LA) needs none');
  PERFORM pg_temp.mkuser('7f0a0009-0000-4000-8000-000000000009','tzx@test.dev','u7fx09');
  PERFORM pg_temp.as_user('7f0a0009-0000-4000-8000-000000000009');
  PERFORM public.set_my_reward_timezone('Asia/Bangkok');
  PERFORM pg_temp.ok((SELECT pending_bridge FROM public.reward_user_settings WHERE user_id='7f0a0009-0000-4000-8000-000000000009') IS NULL, 'B3 same offset (VN -> Bangkok) gives no free day');

  -- ===== T: streak survives a zone change
  today_vn := public.rewards_user_local_date(ustr, now());
  INSERT INTO public.reward_active_days (user_id, local_date, source) SELECT ustr, today_vn - d, 'save' FROM unnest(ARRAY[1,2,3]) d;
  PERFORM pg_temp.ok((public.rewards_streak_of(ustr)->>'current')::int = 3, 'T1 baseline streak 3 (VN)');
  PERFORM pg_temp.as_user(ustr);
  PERFORM public.set_my_reward_timezone('America/Los_Angeles');
  PERFORM pg_temp.ok((public.rewards_streak_of(ustr)->>'current')::int = 3 AND (public.rewards_streak_of(ustr)->>'timezone') = 'Asia/Ho_Chi_Minh', 'T2 requesting a change leaves today (and the streak) untouched');
  -- simulate the change having taken effect: the Pacific date is <= the VN date, so alive-through-yesterday still holds
  UPDATE public.reward_user_settings SET pending_from_ts = now() - interval '1 hour' WHERE user_id = ustr;
  PERFORM pg_temp.ok((public.rewards_streak_of(ustr)->>'timezone') = 'America/Los_Angeles' AND (public.rewards_streak_of(ustr)->>'current')::int = 3, 'T3 after a westward change the existing streak is intact');
  PERFORM pg_temp.ok((public.rewards_streak_of(ustr)->>'longest')::int = 3, 'T4 longest unchanged');
  -- eastward: the bridge keeps a one-date gap from killing the run (and is not counted as an active day)
  DELETE FROM public.reward_active_days WHERE user_id = ustr;
  UPDATE public.reward_user_settings SET pending_tz = NULL, pending_from_ts = NULL, pending_bridge = NULL, tz = 'Asia/Ho_Chi_Minh', bridge_dates = '{}' WHERE user_id = ustr;
  today_vn := public.rewards_user_local_date(ustr, now());
  INSERT INTO public.reward_active_days (user_id, local_date, source) SELECT ustr, today_vn - d, 'save' FROM unnest(ARRAY[2,3]) d;  -- nothing yesterday
  PERFORM pg_temp.ok((public.rewards_streak_of(ustr)->>'current')::int = 0, 'T5a without a bridge a skipped yesterday ends the run');
  UPDATE public.reward_user_settings SET bridge_dates = ARRAY[today_vn - 1] WHERE user_id = ustr;
  PERFORM pg_temp.ok((public.rewards_streak_of(ustr)->>'current')::int = 2 AND (public.rewards_streak_of(ustr)->>'longest')::int = 2, 'T5b with the bridge date the run survives and still counts 2 real days');
  PERFORM pg_temp.ok((public.rewards_streak_of(ustr)->>'active_today')::boolean = false, 'T5c a bridge is not an active day');

  -- ===== F: flip-flopping zones cannot stretch a streak or earn coins from a bridge
  PERFORM pg_temp.mkuser('7f0a000a-0000-4000-8000-00000000000a','tzf@test.dev','u7ff0a');
  PERFORM pg_temp.setz('7f0a000a-0000-4000-8000-00000000000a','America/Los_Angeles');
  PERFORM pg_temp.as_user('7f0a000a-0000-4000-8000-00000000000a');
  n := (SELECT count(*) FROM public.reward_ledger WHERE user_id='7f0a000a-0000-4000-8000-00000000000a');
  r := public.set_my_reward_timezone('Asia/Ho_Chi_Minh');                                   -- east (LA -> VN): bridge
  UPDATE public.reward_user_settings SET pending_from_ts = now() - interval '1 hour' WHERE user_id='7f0a000a-0000-4000-8000-00000000000a';
  r := public.set_my_reward_timezone('America/Los_Angeles');                                -- west: none
  UPDATE public.reward_user_settings SET pending_from_ts = now() - interval '1 hour' WHERE user_id='7f0a000a-0000-4000-8000-00000000000a';
  r := public.set_my_reward_timezone('Asia/Ho_Chi_Minh');                                   -- east again: refused (2 per 30 days)
  PERFORM pg_temp.ok(r->>'error' = 'TZ_CHANGE_LIMIT', 'F1 east -> west -> east: the third effective change is refused');
  PERFORM pg_temp.ok(cardinality((SELECT bridge_dates FROM public.reward_user_settings WHERE user_id='7f0a000a-0000-4000-8000-00000000000a')) = 1
                 AND (SELECT pending_bridge FROM public.reward_user_settings WHERE user_id='7f0a000a-0000-4000-8000-00000000000a') IS NULL, 'F2 exactly one bridge date exists after the flip-flop');
  -- a bridge never extends beyond the real days: run of 2 real days + 1 bridge still reads 2, and coins/active_today untouched
  PERFORM pg_temp.setz('7f0a000a-0000-4000-8000-00000000000a','Asia/Ho_Chi_Minh');
  UPDATE public.reward_user_settings SET pending_tz=NULL, pending_from_ts=NULL, pending_bridge=NULL WHERE user_id='7f0a000a-0000-4000-8000-00000000000a';
  today_vn := public.rewards_user_local_date('7f0a000a-0000-4000-8000-00000000000a', now());
  INSERT INTO public.reward_active_days (user_id, local_date, source) SELECT '7f0a000a-0000-4000-8000-00000000000a', today_vn - d, 'save' FROM unnest(ARRAY[3,2]) d;
  UPDATE public.reward_user_settings SET bridge_dates = ARRAY[today_vn - 1] WHERE user_id='7f0a000a-0000-4000-8000-00000000000a';
  PERFORM pg_temp.ok((public.rewards_streak_of('7f0a000a-0000-4000-8000-00000000000a')->>'current')::int = 2
                 AND (public.rewards_streak_of('7f0a000a-0000-4000-8000-00000000000a')->>'longest')::int = 2, 'F3 bridge forgives the gap but adds 0 to current/longest');
  -- two bridges in one run (max 2 per 30 days) still never count as days
  UPDATE public.reward_user_settings SET bridge_dates = ARRAY[today_vn - 1, today_vn - 4] WHERE user_id='7f0a000a-0000-4000-8000-00000000000a';
  PERFORM pg_temp.ok((public.rewards_streak_of('7f0a000a-0000-4000-8000-00000000000a')->>'current')::int = 2, 'F4 a second bridge date cannot add days either');
  -- a bridge with no real day before it protects nothing (cannot start or revive a streak)
  DELETE FROM public.reward_active_days WHERE user_id='7f0a000a-0000-4000-8000-00000000000a';
  INSERT INTO public.reward_active_days (user_id, local_date, source) VALUES ('7f0a000a-0000-4000-8000-00000000000a', today_vn - 3, 'save');
  UPDATE public.reward_user_settings SET bridge_dates = ARRAY[today_vn - 1] WHERE user_id='7f0a000a-0000-4000-8000-00000000000a';
  PERFORM pg_temp.ok((public.rewards_streak_of('7f0a000a-0000-4000-8000-00000000000a')->>'current')::int = 0, 'F5 a bridge not adjacent to a real active day does not revive a dead streak');
  UPDATE public.reward_user_settings SET bridge_dates = ARRAY[today_vn] WHERE user_id='7f0a000a-0000-4000-8000-00000000000a';
  DELETE FROM public.reward_active_days WHERE user_id='7f0a000a-0000-4000-8000-00000000000a';
  PERFORM pg_temp.ok((public.rewards_streak_of('7f0a000a-0000-4000-8000-00000000000a')->>'current')::int = 0
                 AND NOT (public.rewards_streak_of('7f0a000a-0000-4000-8000-00000000000a')->>'active_today')::boolean, 'F6 a bridge alone is never an active day');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.reward_ledger WHERE user_id='7f0a000a-0000-4000-8000-00000000000a') = n
                 AND public.rewards_balance('7f0a000a-0000-4000-8000-00000000000a') = 0, 'F7 no ledger row and no coin came from any zone change or bridge');
  -- two eastward effective hops (LA -> NY -> VN) = at most two bridges, then blocked
  PERFORM pg_temp.mkuser('7f0a000b-0000-4000-8000-00000000000b','tzg@test.dev','u7fg0b');
  PERFORM pg_temp.setz('7f0a000b-0000-4000-8000-00000000000b','America/Los_Angeles');
  PERFORM pg_temp.as_user('7f0a000b-0000-4000-8000-00000000000b');
  r := public.set_my_reward_timezone('America/New_York');
  UPDATE public.reward_user_settings SET pending_from_ts = now() - interval '1 hour' WHERE user_id='7f0a000b-0000-4000-8000-00000000000b';
  r := public.set_my_reward_timezone('Asia/Ho_Chi_Minh');
  UPDATE public.reward_user_settings SET pending_from_ts = now() - interval '1 hour' WHERE user_id='7f0a000b-0000-4000-8000-00000000000b';
  r := public.set_my_reward_timezone('America/Los_Angeles');
  PERFORM pg_temp.ok(r->>'error' = 'TZ_CHANGE_LIMIT'
                 AND cardinality((SELECT bridge_dates FROM public.reward_user_settings WHERE user_id='7f0a000b-0000-4000-8000-00000000000b')) + (SELECT (pending_bridge IS NOT NULL)::int FROM public.reward_user_settings WHERE user_id='7f0a000b-0000-4000-8000-00000000000b') <= 2,
                 'F8 two eastward hops yield at most two bridges per 30 days, a third change is refused');

  -- ===== C: compatibility of the four client RPCs
  PERFORM pg_temp.as_user(uvn);
  r := public.get_my_reward_summary();
  PERFORM pg_temp.ok(r ?& ARRAY['active_today','balance','streak','success']
                     AND ARRAY(SELECT jsonb_object_keys(r) ORDER BY 1) <@ ARRAY['active_today','balance','streak','success','week_active','week_streak'],
                     'C1 get_my_reward_summary: old keys unchanged, only 192''s additive keys besides');
  r := public.get_my_rewards();
  FOREACH k IN ARRAY ARRAY['success','balance','rules','streak','badges','history','catalog','attendance_paid_this_month'] LOOP
    PERFORM pg_temp.ok(r ? k, 'C2 get_my_rewards still has '||k);
  END LOOP;
  PERFORM pg_temp.ok(r ? 'timezone_settings' AND r->'streak' ?& ARRAY['current','longest','last_active_date','active_today','timezone'], 'C3 only additive: timezone_settings added, streak keys intact');
  PERFORM pg_temp.ok((r->'rules'->>'timezone') = 'Asia/Ho_Chi_Minh' AND (r->'streak'->>'timezone') = 'Asia/Ho_Chi_Minh' AND (r->'timezone_settings'->>'chosen')::boolean = false, 'C4 default user reports the legacy zone, not "chosen"');
  PERFORM pg_temp.ok((public.record_active_day('open', NULL)->>'error') = 'UNSUPPORTED_SOURCE' AND (public.redeem_reward('nope')->>'error') IS NOT NULL, 'C5 record_active_day / redeem_reward signatures + errors unchanged');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.reward_catalog WHERE active) = 3, 'C6 catalog intact');

  RAISE NOTICE 'TZ RESULT: ALL PASS';
END $t$;
ROLLBACK;
