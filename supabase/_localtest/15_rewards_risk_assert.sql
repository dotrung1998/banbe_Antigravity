-- LOCAL TEST HARNESS ONLY — never deployed, never run against a real project.
-- Migration 178: host–friend fraud flags (detect + flag only). Runs after the full chain + 01_seed.sql on the
-- throwaway local postgres (15_rewards_risk_run.sh). All fixtures are fake and rolled back at the end.
-- Thresholds are the UNCALIBRATED defaults: these tests prove the mechanism, not the right numbers.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', u::text, true) $$;
CREATE FUNCTION pg_temp.mkuser(u uuid, handle text, age_days int DEFAULT 0, phone text DEFAULT NULL, profile_phone text DEFAULT NULL, confirmed boolean DEFAULT true) RETURNS void LANGUAGE plpgsql AS $$
DECLARE ph text := COALESCE(phone, '+84' || lpad((abs(hashtext(handle)) % 1000000000)::text, 9, '0'));
BEGIN
  INSERT INTO auth.users (id,email,phone,phone_confirmed_at,raw_user_meta_data,confirmed_at)
  VALUES (u,handle||'@test.dev',ph,CASE WHEN confirmed THEN now() END,jsonb_build_object('display_name',handle),now()) ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles (id,display_name,handle,role,phone,phone_verified,created_at)
  VALUES (u,handle,handle,'participant',COALESCE(profile_phone,ph),true,now() - age_days * interval '1 day') ON CONFLICT (id) DO NOTHING;
  UPDATE profiles SET phone = COALESCE(profile_phone, ph), created_at = now() - age_days * interval '1 day' WHERE id = u;
  INSERT INTO account_phone_grandfathered(user_id,cohort) VALUES (u,'t') ON CONFLICT DO NOTHING;
END $$;
CREATE FUNCTION pg_temp.mkorg(o text, owner uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO organizers (id,name,owner_id,user_id) VALUES (o,'Org '||o,owner,owner) ON CONFLICT (id) DO NOTHING $$;
CREATE FUNCTION pg_temp.mkev(id text, org text, starts timestamptz) RETURNS void LANGUAGE sql AS $$
  INSERT INTO events (id,key,name,organizer_id,status,price_vnd,capacity,starts_at,seats_remaining,cat_key)
  VALUES (id,id,'Event '||id,org,'live',0,50,starts,50,'music') ON CONFLICT (id) DO NOTHING $$;
CREATE FUNCTION pg_temp.attend(ev text, u uuid, host uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE b uuid := gen_random_uuid(); r jsonb;
BEGIN
  INSERT INTO bookings (id,event_id,user_id,purchaser_id,qty,total_vnd,code,status,payment_state,paid_marked_at)
  VALUES (b,ev,u,u,1,0,'RK-'||substr(b::text,1,8),'confirmed','confirmed',now());
  PERFORM set_config('request.jwt.claim.sub', host::text, true);
  r := public.check_in_guest(b,'manual');
  IF NOT (r->>'success')::boolean THEN RAISE EXCEPTION 'check-in failed %', r; END IF;
  RETURN b;
END $$;
CREATE FUNCTION pg_temp.nflags(t text DEFAULT NULL, org text DEFAULT NULL) RETURNS int LANGUAGE sql AS $$
  SELECT count(*)::int FROM public.reward_risk_flags WHERE (t IS NULL OR flag_type = t) AND (org IS NULL OR organizer_id = org) $$;
CREATE FUNCTION pg_temp.ncand(t text, org text) RETURNS int LANGUAGE sql AS $$
  SELECT count(*)::int FROM public.rewards_risk_compute() c WHERE c.flag_type = t AND c.organizer_id = org $$;

DO $t$
DECLARE
  admin uuid := '7a000005-0000-4000-8000-000000000005';
  hostA uuid := '7a000002-0000-4000-8000-000000000002';   -- host of test_org_a: friends ring
  hostB uuid := '7b0b0001-0000-4000-8000-000000000001';   -- genuine host, many distinct old accounts
  hostC uuid := '7b0b0002-0000-4000-8000-000000000002';   -- ring, but every check-in is undone
  hostD uuid := '7b0b0003-0000-4000-8000-000000000003';   -- off-window + shared phone
  stranger uuid := '7a000004-0000-4000-8000-000000000004';
  u uuid; i int; j int; b uuid; r jsonb; n int; led int; bal int; cin int; since timestamptz := now() - interval '1 hour';
  ledger_before int; checkins_before int; hostmode text;
BEGIN
  PERFORM pg_temp.mkuser(hostB,'u7hb01',300); PERFORM pg_temp.mkuser(hostC,'u7hc02',300); PERFORM pg_temp.mkuser(hostD,'u7hd03',300);
  PERFORM pg_temp.mkorg('rk_org_b',hostB); PERFORM pg_temp.mkorg('rk_org_c',hostC); PERFORM pg_temp.mkorg('rk_org_d',hostD);
  PERFORM pg_temp.mkuser('7a0a0001-0000-4000-8000-000000000001'::uuid,'u7he04',300); PERFORM pg_temp.mkorg('rk_org_e','7a0a0001-0000-4000-8000-000000000001');

  -- ===== D: defaults
  PERFORM pg_temp.ok((SELECT enabled FROM public.reward_risk_config WHERE id=1) = false, 'D1 the flag is OFF by default');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.reward_risk_flags) = 0, 'D2 no flags exist on a fresh database');

  -- ===== A: host + 5 brand-new accounts, each confirmed at 3 of the host's events (in-window)
  FOR j IN 1..3 LOOP PERFORM pg_temp.mkev('rk_a'||j,'test_org_a',now() - interval '1 hour'); END LOOP;
  FOR i IN 1..5 LOOP
    u := ('7c0c000'||i||'-0000-4000-8000-00000000000'||i)::uuid; PERFORM pg_temp.mkuser(u,'u7ca0'||i,0);
    FOR j IN 1..3 LOOP PERFORM pg_temp.attend('rk_a'||j,u,hostA); END LOOP;
  END LOOP;

  -- ===== B: genuine host: 12 distinct old accounts over 4 events, nobody attends 3 of them, all in-window
  FOR j IN 1..4 LOOP PERFORM pg_temp.mkev('rk_b'||j,'rk_org_b',now() - interval '1 hour'); END LOOP;
  FOR i IN 1..12 LOOP
    u := ('7d0d00'||lpad(i::text,2,'0')||'-0000-4000-8000-0000000000'||lpad(i::text,2,'0'))::uuid; PERFORM pg_temp.mkuser(u,'u7db'||lpad(i::text,2,'0'),200);
    PERFORM pg_temp.attend('rk_b'||(1+(i%4)),u,hostB);
    IF i <= 4 THEN PERFORM pg_temp.attend('rk_b'||(1+((i+1)%4)),u,hostB); END IF;   -- a few come twice
  END LOOP;

  -- ===== C: ring of 5 new accounts x 3 events, then EVERY check-in is undone by the host
  FOR j IN 1..3 LOOP PERFORM pg_temp.mkev('rk_c'||j,'rk_org_c',now() - interval '1 hour'); END LOOP;
  FOR i IN 1..5 LOOP
    u := ('7e0e000'||i||'-0000-4000-8000-00000000000'||i)::uuid; PERFORM pg_temp.mkuser(u,'u7ec0'||i,0);
    FOR j IN 1..3 LOOP
      b := pg_temp.attend('rk_c'||j,u,hostC);
      PERFORM set_config('request.jwt.claim.sub', hostC::text, true);
      r := public.undo_check_in(b,'mistake');
    END LOOP;
  END LOOP;

  -- ===== D: off-window (event 10 days away, 3 check-ins now) + two accounts sharing a phone
  PERFORM pg_temp.mkev('rk_d_future','rk_org_d',now() + interval '10 days');
  PERFORM pg_temp.mkev('rk_d_now','rk_org_d',now() - interval '1 hour');
  FOR i IN 1..3 LOOP
    u := ('7f1f000'||i||'-0000-4000-8000-00000000000'||i)::uuid; PERFORM pg_temp.mkuser(u,'u7fd0'||i,100, CASE WHEN i<=2 THEN '+84900009999' ELSE NULL END);
    PERFORM pg_temp.attend('rk_d_future',u,hostD);
  END LOOP;
  PERFORM pg_temp.attend('rk_d_now','7f1f0001-0000-4000-8000-000000000001',hostD);

  -- ===== SP: the signal must read the VERIFIED auth phone, not the client-writable profile phone
  PERFORM pg_temp.mkev('rk_e1','rk_org_e',now() - interval '1 hour');
  PERFORM pg_temp.mkuser('7a0a0011-0000-4000-8000-000000000011','u7sp11',100,NULL,'+84911111111');   -- profile phones typed identical, auth phones differ
  PERFORM pg_temp.mkuser('7a0a0012-0000-4000-8000-000000000012','u7sp12',100,NULL,'+84911111111');
  PERFORM pg_temp.mkuser('7a0a0013-0000-4000-8000-000000000013','u7sp13',100,'+84922222222',NULL,false); -- same auth phone, never confirmed
  PERFORM pg_temp.mkuser('7a0a0014-0000-4000-8000-000000000014','u7sp14',100,'+84922222222',NULL,false);
  PERFORM pg_temp.mkuser('7a0a0015-0000-4000-8000-000000000015','u7sp15',100,'+84933333333',NULL,true);  -- confirmed, two formats
  PERFORM pg_temp.mkuser('7a0a0016-0000-4000-8000-000000000016','u7sp16',100,'84933333333',NULL,true);
  FOR i IN 11..16 LOOP PERFORM pg_temp.attend('rk_e1',('7a0a00'||i||'-0000-4000-8000-0000000000'||i)::uuid,'7a0a0001-0000-4000-8000-000000000001'); END LOOP;
  PERFORM pg_temp.ok((SELECT count(*) FROM public.rewards_risk_compute() c WHERE c.flag_type='shared_phone' AND c.organizer_id='rk_org_e') = 1
                 AND (SELECT jsonb_array_length(metrics->'user_ids') FROM public.rewards_risk_compute() c WHERE c.flag_type='shared_phone' AND c.organizer_id='rk_org_e') = 2,
                 'SP shared_phone reads the verified auth.users phone (digits-normalised); spoofed profile phones and unconfirmed auth phones raise nothing');

  -- ===== P: preview works while disabled, writes nothing, and ranks the right hosts
  PERFORM pg_temp.as_user(admin);
  r := public.admin_reward_risk_preview();
  PERFORM pg_temp.ok((r->>'success')::boolean AND (r->>'written')::int = 0 AND (r->>'enabled')::boolean = false, 'P1 preview is allowed while disabled and reports written=0');
  PERFORM pg_temp.ok(pg_temp.nflags() = 0, 'P2 preview wrote nothing');
  PERFORM pg_temp.ok(pg_temp.ncand('new_accounts','test_org_a') = 1 AND pg_temp.ncand('repeat_guests','test_org_a') = 1, 'P3 host + 5 new accounts: new_accounts and repeat_guests candidates');
  PERFORM pg_temp.ok((SELECT jsonb_array_length(metrics->'user_ids') FROM public.rewards_risk_compute() c WHERE c.flag_type='new_accounts' AND c.organizer_id='test_org_a') = 5, 'P4 all 5 accounts identified for the admin');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.rewards_risk_compute() c WHERE c.organizer_id = 'rk_org_b'), 'P5 genuine host with many different old guests is NOT flagged (false-positive guard)');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.rewards_risk_compute() c WHERE c.organizer_id = 'rk_org_c'), 'P6 undone check-ins are not counted (ring C raises nothing)');
  PERFORM pg_temp.ok(pg_temp.ncand('off_window','rk_org_d') = 1 AND NOT EXISTS (SELECT 1 FROM public.rewards_risk_compute() c WHERE c.event_id IN ('rk_d_now','rk_a1','rk_b1')), 'P7 only the far-from-start event is off-window; in-window events are not');
  PERFORM pg_temp.ok(pg_temp.ncand('shared_phone','rk_org_d') = 1, 'P8 two attendee accounts sharing a phone');

  -- ===== O: flag OFF => scan writes nothing
  r := public.admin_run_reward_risk_scan();
  PERFORM pg_temp.ok((r->>'success')::boolean AND (r->>'enabled')::boolean = false AND (r->>'written')::int = 0 AND pg_temp.nflags() = 0, 'O1 disabled: scan writes nothing');

  -- ===== auth: admin only
  PERFORM pg_temp.as_user(stranger);
  PERFORM pg_temp.ok(public.admin_reward_risk_preview()->>'error' = 'NOT_ADMIN' AND public.admin_run_reward_risk_scan()->>'error' = 'NOT_ADMIN'
                 AND public.admin_list_reward_risk_flags()->>'error' = 'NOT_ADMIN' AND public.admin_get_reward_risk_config()->>'error' = 'NOT_ADMIN'
                 AND public.admin_set_reward_risk_config(true, NULL)->>'error' = 'NOT_ADMIN' AND public.admin_review_reward_risk_flag(gen_random_uuid(),'dismissed')->>'error' = 'NOT_ADMIN', 'X1 every RPC refuses a non-admin');
  PERFORM pg_temp.ok((SELECT enabled FROM public.reward_risk_config WHERE id=1) = false, 'X2 a non-admin could not enable it');
  PERFORM pg_temp.as_user(hostA);
  PERFORM pg_temp.ok(public.admin_list_reward_risk_flags()->>'error' = 'NOT_ADMIN', 'X3 even the flagged host cannot read flags');
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM count(*) FROM public.reward_risk_flags; RESET ROLE; RAISE EXCEPTION 'X4a flags readable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM count(*) FROM public.reward_risk_config; RESET ROLE; RAISE EXCEPTION 'X4b config readable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM public.rewards_risk_compute(); RESET ROLE; RAISE EXCEPTION 'X4c compute callable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE anon;
  BEGIN PERFORM public.admin_reward_risk_preview(); RESET ROLE; RAISE EXCEPTION 'X4d anon'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  PERFORM pg_temp.ok(true, 'X4 tables/helpers closed to clients, anon refused');

  -- ===== E: enable, scan, idempotence, review
  PERFORM pg_temp.as_user(admin);
  r := public.admin_set_reward_risk_config(true, NULL);
  PERFORM pg_temp.ok((r->>'success')::boolean, 'E1 admin can enable');
  SELECT count(*) INTO ledger_before FROM public.reward_ledger; SELECT count(*) INTO checkins_before FROM public.check_ins;
  r := public.admin_run_reward_risk_scan();
  PERFORM pg_temp.ok((r->>'enabled')::boolean AND (r->>'written')::int = pg_temp.nflags() AND pg_temp.nflags() = 5, 'E2 scan wrote exactly the 5 expected flags (A: new_accounts + repeat_guests; D: off_window + shared_phone; E: shared_phone)');
  PERFORM pg_temp.ok(pg_temp.nflags('new_accounts','test_org_a') = 1 AND pg_temp.nflags('repeat_guests','test_org_a') = 1 AND pg_temp.nflags('off_window','rk_org_d') = 1 AND pg_temp.nflags('shared_phone','rk_org_d') = 1, 'E3 flags are the ones previewed');
  PERFORM pg_temp.ok(pg_temp.nflags(NULL,'rk_org_b') = 0 AND pg_temp.nflags(NULL,'rk_org_c') = 0, 'E4 genuine host and undone ring have no flags');
  r := public.admin_run_reward_risk_scan();
  PERFORM pg_temp.ok(pg_temp.nflags() = 5, 'E5 re-running does not duplicate flags');
  -- review lifecycle
  b := (SELECT id FROM public.reward_risk_flags WHERE flag_type='shared_phone' AND organizer_id='rk_org_d');
  r := public.admin_review_reward_risk_flag(b,'dismissed','same family');
  PERFORM pg_temp.ok((r->>'success')::boolean AND (SELECT status FROM public.reward_risk_flags WHERE id=b) = 'dismissed' AND (SELECT reviewed_by FROM public.reward_risk_flags WHERE id=b) = admin, 'E6 admin can dismiss with a note');
  PERFORM public.admin_run_reward_risk_scan();
  PERFORM pg_temp.ok((SELECT status FROM public.reward_risk_flags WHERE id=b) = 'dismissed', 'E7 a dismissed flag is not reopened by the next scan');
  PERFORM pg_temp.ok(public.admin_review_reward_risk_flag(b,'banned')->>'error' = 'INVALID_STATUS' AND public.admin_review_reward_risk_flag(gen_random_uuid(),'open')->>'error' = 'NOT_FOUND', 'E8 invalid status / unknown id refused');
  PERFORM pg_temp.ok(jsonb_array_length(public.admin_list_reward_risk_flags('open')->'flags') = 4 AND NOT (public.admin_list_reward_risk_flags('open')->'flags'->0 ? 'dedupe_key'), 'E9 admin list returns the open flags without internals');

  -- ===== N: flags never act
  SELECT count(*) INTO n FROM public.reward_ledger;
  PERFORM pg_temp.ok(n = ledger_before, 'N1 scan/review created no ledger row (no automatic reversal)');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.check_ins) = checkins_before, 'N2 no check-in was removed');
  PERFORM pg_temp.ok(public.rewards_balance('7c0c0001-0000-4000-8000-000000000001') = 60, 'N3 a flagged account keeps its coins (3 x 20)');
  PERFORM pg_temp.mkev('rk_a_after','test_org_a',now() - interval '1 hour');
  b := pg_temp.attend('rk_a_after','7c0c0001-0000-4000-8000-000000000001',hostA);
  PERFORM pg_temp.ok(b IS NOT NULL, 'N4 a flagged host can still check guests in, with the flag ON');
  PERFORM pg_temp.ok(public.rewards_balance('7c0c0001-0000-4000-8000-000000000001') = 80, 'N5 and the guest is still rewarded normally');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM pg_trigger tg JOIN pg_proc p ON p.oid = tg.tgfoid WHERE NOT tg.tgisinternal AND p.proname LIKE '%risk%'), 'N6 no trigger runs risk code (the check-in path is untouched)');

  -- ===== T: thresholds live in the config table
  PERFORM pg_temp.as_user(admin);
  PERFORM pg_temp.ok(public.admin_set_reward_risk_config(NULL, '{"nonsense": 3}')->>'error' = 'INVALID_THRESHOLDS'
                 AND public.admin_set_reward_risk_config(NULL, '{"repeat_ratio": 2}')->>'error' = 'INVALID_THRESHOLDS'
                 AND public.admin_set_reward_risk_config(NULL, '{"off_min_checkins": -1}')->>'error' = 'INVALID_THRESHOLDS'
                 AND public.admin_set_reward_risk_config(NULL, '{"off_min_checkins": "3"}')->>'error' = 'INVALID_THRESHOLDS', 'T1 unknown / out-of-range / non-numeric thresholds refused');
  PERFORM public.admin_set_reward_risk_config(NULL, '{"new_account_cluster_min": 6}');
  PERFORM pg_temp.ok(pg_temp.ncand('new_accounts','test_org_a') = 0 AND (public.admin_get_reward_risk_config()->'config'->>'new_account_cluster_min')::int = 6
                 AND (public.admin_get_reward_risk_config()->>'calibrated')::boolean = false, 'T2 raising the threshold in the table changes the result (no code change); reported as not calibrated');
  r := public.admin_set_reward_risk_config(false, NULL);
  r := public.admin_run_reward_risk_scan();
  PERFORM pg_temp.ok((r->>'written')::int = 0 AND (r->>'enabled')::boolean = false, 'T3 turning the flag off stops all writes again');

  RAISE NOTICE 'RISK RESULT: ALL PASS';
END $t$;
ROLLBACK;
