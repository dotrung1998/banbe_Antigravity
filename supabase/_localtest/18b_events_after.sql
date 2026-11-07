-- LOCAL TEST HARNESS ONLY. Same DB after migration 180 was applied (committed). Fixtures are removed at the end.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', u::text, false) $$;
CREATE FUNCTION pg_temp.cnt(o text, t text DEFAULT NULL, reg text DEFAULT NULL) RETURNS bigint LANGUAGE sql AS $$
  SELECT COALESCE(sum(count),0)::bigint FROM public.reward_event_counters WHERE offer_id = o AND (t IS NULL OR event_type = t) AND (reg IS NULL OR region_coarse = reg) $$;
BEGIN;
DO $t$
DECLARE u uuid := '7a3a0001-0000-4000-8000-000000000001'; adm uuid := '7a3a0009-0000-4000-8000-000000000009'; r jsonb; n int; txt text; kk text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',false);
  INSERT INTO auth.users (id,email,phone,phone_confirmed_at,raw_user_meta_data,confirmed_at) VALUES (adm,'u7e009@test.dev','+84900031009',now(),'{"display_name":"u7e009"}',now()) ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles (id,display_name,handle,role,phone,phone_verified) VALUES (adm,'u7e009','u7e009','participant','+84900031009',true) ON CONFLICT (id) DO NOTHING;
  UPDATE profiles SET role='admin' WHERE id = adm;

  -- ===== O: old RPCs untouched
  FOR kk IN SELECT x.k FROM public._ev_snap x WHERE x.k LIKE 'def:%' LOOP
    PERFORM pg_temp.ok((SELECT s.v FROM public._ev_snap s WHERE s.k = kk) = to_jsonb((SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname = substr(kk,5))), 'O1 definition unchanged: '||substr(kk,5));
  END LOOP;
  PERFORM pg_temp.as_user(u);
  PERFORM pg_temp.ok((SELECT v FROM public._ev_snap WHERE k='res:redeem2') = public.redeem_reward('rwd-comet'), 'O2 redeem_reward answers exactly as before (already unlocked)');
  PERFORM pg_temp.ok((SELECT v FROM public._ev_snap WHERE k='res:rewards_after_redeem') = (public.get_my_rewards() - 'streak' - 'history'), 'O3 get_my_rewards result identical');
  PERFORM pg_temp.ok((SELECT v FROM public._ev_snap WHERE k='res:summary') ->> 'balance' = '100' AND (public.get_my_reward_summary()->>'balance')::int = 60, 'O4 summary balance reflects the one redeem exactly like before');

  -- ===== S: schema — nothing identifying can be stored
  PERFORM pg_temp.ok((SELECT string_agg(column_name||':'||data_type, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name='reward_event_counters')
                     = 'offer_id:text,event_date:date,region_coarse:text,event_type:text,count:bigint', 'S1 counters table has exactly offer_id, event_date, region_coarse, event_type, count');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('reward_event_counters','reward_event_config') AND (data_type IN ('uuid','inet','cidr','macaddr','jsonb','json','bytea') OR data_type LIKE 'timestamp%' OR data_type LIKE 'time%')), 'S2 no uuid/ip/json/bytea/timestamp column in the new tables');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('reward_event_counters','reward_event_config') AND column_name ~* '(user|uid|phone|email|device|ip|session|token|agent|created|updated|at$)'), 'S3 no identifying column NAME (user/phone/email/device/ip/session/token/agent/created_at/updated_at)');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid IN ('public.reward_event_counters'::regclass,'public.reward_event_config'::regclass) AND NOT t.tgisinternal), 'S4 no trigger (no audit/side effect) on the new tables');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.confrelid = 'public.reward_event_counters'::regclass), 'S5 nothing references the counters (no join path to people)');
  PERFORM pg_temp.ok((SELECT count(*) FROM pg_constraint WHERE conrelid='public.reward_event_counters'::regclass AND contype='f') = 1 AND
                     (SELECT confrelid::regclass::text FROM pg_constraint WHERE conrelid='public.reward_event_counters'::regclass AND contype='f') = 'reward_catalog', 'S6 the only FK is to reward_catalog (the offer), never to profiles/auth');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname IN ('record_reward_event','rewards_bump_event_counter','admin_reward_event_report') AND (p.prosrc ~* '(raise\s+(log|notice|warning|info)|v_uid|insert\s+into\s+public\.(?!reward_event_counters))' )),
                 'S7 no function logs, raises notices, keeps a user variable, or writes anywhere but the counters');
  PERFORM pg_temp.ok((SELECT length(prosrc) - length(replace(prosrc,'auth.uid()','')) FROM pg_proc WHERE proname='record_reward_event') = length('auth.uid()')
                     AND (SELECT prosrc FROM pg_proc WHERE proname='record_reward_event') ~ 'IF auth\.uid\(\) IS NULL THEN', 'S8 the caller is only checked (auth.uid() IS NULL), never stored or passed on');
  PERFORM pg_temp.ok((SELECT conname FROM pg_constraint WHERE conrelid='public.reward_event_counters'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%VN%') IS NOT NULL
                     AND (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.reward_event_counters'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%VN%') LIKE '%OTHER%UNKNOWN%', 'S9 region_coarse is restricted to VN/US/OTHER/UNKNOWN by CHECK');
  PERFORM pg_temp.ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.reward_event_counters'::regclass) AND NOT has_table_privilege('authenticated','public.reward_event_counters','SELECT') AND NOT has_table_privilege('authenticated','public.reward_event_counters','INSERT')
                     AND NOT has_table_privilege('authenticated','public.reward_event_counters','UPDATE') AND NOT has_table_privilege('anon','public.reward_event_counters','SELECT') AND NOT has_table_privilege('authenticated','public.reward_event_config','SELECT'), 'S10 RLS on, no client table privileges');

  -- fixtures: three partner offers (one inactive) + one keychain code
  INSERT INTO public.reward_catalog (code, kind, design_id, price, sort) VALUES ('ev-offer-a','partner_offer',NULL,1,60), ('ev-offer-b','partner_offer',NULL,1,61), ('ev-offer-off','partner_offer',NULL,1,62);
  UPDATE public.reward_catalog SET active = false WHERE code = 'ev-offer-off';

  -- ===== F: flag OFF by default writes nothing, neutral answer
  PERFORM pg_temp.ok((SELECT enabled FROM public.reward_feature_flags WHERE flag='reward_events') = false, 'F1 flag OFF by default');
  PERFORM pg_temp.as_user(u);
  r := public.record_reward_event('ev-offer-a'); 
  PERFORM pg_temp.ok((r->>'success')::boolean AND (r->>'recorded')::boolean = false, 'F2 flag off: success, recorded=false');
  PERFORM pg_temp.ok(public.record_reward_event('does-not-exist') = r AND public.record_reward_event('rwd-comet','offer_issued','XX') = r, 'F3 flag off: identical neutral answer for any offer/type (reveals nothing)');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.reward_event_counters) = 0, 'F4 flag off: no row written');
  PERFORM set_config('request.jwt.claim.sub','',false);
  PERFORM pg_temp.ok(public.record_reward_event('ev-offer-a')->>'error' = 'AUTH_REQUIRED', 'F5 no authenticated caller: AUTH_REQUIRED');
  SET LOCAL ROLE anon;
  BEGIN PERFORM public.record_reward_event('ev-offer-a'); RESET ROLE; RAISE EXCEPTION 'F6 anon executed'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  PERFORM pg_temp.ok(true, 'F6 anon cannot execute');

  -- ===== R: flag ON
  UPDATE public.reward_feature_flags SET enabled = true WHERE flag = 'reward_events';
  PERFORM pg_temp.as_user(u);
  PERFORM public.record_reward_event('ev-offer-a'); PERFORM public.record_reward_event('ev-offer-a','offer_viewed','VN'); PERFORM public.record_reward_event('ev-offer-a','offer_viewed','VN');
  PERFORM pg_temp.ok(pg_temp.cnt('ev-offer-a','offer_viewed','VN') = 2 AND pg_temp.cnt('ev-offer-a','offer_viewed','UNKNOWN') = 1, 'R1 each call adds exactly 1 to its own cell (VN=2, default region UNKNOWN=1)');
  PERFORM public.record_reward_event('ev-offer-a','offer_viewed','Hà Nội'); PERFORM public.record_reward_event('ev-offer-a','offer_viewed','10.0.0.1');
  PERFORM pg_temp.ok(pg_temp.cnt('ev-offer-a','offer_viewed','UNKNOWN') = 3 AND NOT EXISTS (SELECT 1 FROM public.reward_event_counters WHERE region_coarse NOT IN ('VN','US','OTHER','UNKNOWN')), 'R2 any value outside the allowed list (city, even an IP-looking string) is stored as UNKNOWN, never as given');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.reward_event_counters WHERE event_date = (now() AT TIME ZONE 'UTC')::date) = (SELECT count(*) FROM public.reward_event_counters), 'R3 only the UTC date is stored');
  PERFORM pg_temp.ok(public.record_reward_event('ev-offer-a','offer_issued','VN')->>'error' = 'INVALID_EVENT' AND public.record_reward_event('ev-offer-a','offer_redeemed')->>'error' = 'INVALID_EVENT' AND pg_temp.cnt('ev-offer-a','offer_issued') = 0, 'R4 a client cannot claim issued/redeemed');
  PERFORM pg_temp.ok((public.record_reward_event('nope')->>'recorded')::boolean = false AND (public.record_reward_event('rwd-comet')->>'recorded')::boolean = false AND (public.record_reward_event('ev-offer-off')->>'recorded')::boolean = false, 'R5 unknown offer, a keychain code and an inactive offer record nothing');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.reward_event_counters WHERE offer_id IN ('nope','rwd-comet','ev-offer-off')) = 0, 'R5b …and no row exists for them');
  PERFORM pg_temp.ok(public.rewards_bump_event_counter('ev-offer-a','offer_issued','US') AND public.rewards_bump_event_counter('ev-offer-a','offer_redeemed','US') AND pg_temp.cnt('ev-offer-a','offer_issued','US') = 1 AND pg_temp.cnt('ev-offer-a','offer_redeemed','US') = 1, 'R6 the server-side helper bumps issued/redeemed');
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM public.rewards_bump_event_counter('ev-offer-a','offer_issued','US'); RESET ROLE; RAISE EXCEPTION 'R7 helper callable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  PERFORM pg_temp.ok(true, 'R7 clients cannot call the helper directly');
  -- a second user adds to the SAME cell: nothing distinguishes the two
  PERFORM pg_temp.as_user(adm); PERFORM public.record_reward_event('ev-offer-a','offer_viewed','VN');
  PERFORM pg_temp.ok(pg_temp.cnt('ev-offer-a','offer_viewed','VN') = 3 AND (SELECT count(*) FROM public.reward_event_counters WHERE offer_id='ev-offer-a' AND event_type='offer_viewed' AND region_coarse='VN') = 1, 'R8 two different users land in one indistinguishable cell');

  -- ===== T: report with threshold
  PERFORM pg_temp.as_user(u);
  PERFORM pg_temp.ok(public.admin_reward_event_report()->>'error' = 'NOT_ADMIN', 'T1 a non-admin cannot read the report');
  PERFORM pg_temp.as_user(adm);
  PERFORM pg_temp.ok((public.admin_reward_event_report()->>'min_group_size')::int = 20, 'T2 default threshold is 20 (read from the config table)');
  DELETE FROM public.reward_event_counters;
  INSERT INTO public.reward_event_counters VALUES ('ev-offer-b', (now() AT TIME ZONE 'UTC')::date, 'VN', 'offer_viewed', 25), ('ev-offer-b', (now() AT TIME ZONE 'UTC')::date, 'US', 'offer_viewed', 19),
    ('ev-offer-b', (now() AT TIME ZONE 'UTC')::date - 1, 'VN', 'offer_viewed', 10), ('ev-offer-b', (now() AT TIME ZONE 'UTC')::date - 1, 'OTHER', 'offer_issued', 3);
  r := public.admin_reward_event_report(NULL, NULL, false);
  PERFORM pg_temp.ok(jsonb_array_length(r->'rows') = 1 AND r->'rows'->0->>'region' = 'VN' AND (r->'rows'->0->>'count')::int = 35, 'T3 summed over the window: VN views 25+10=35 shown');
  PERFORM pg_temp.ok((r->>'suppressed_cells')::int = 2, 'T4 the two small cells (US 19, OTHER issued 3) are hidden and only counted');
  txt := r::text;
  PERFORM pg_temp.ok(txt NOT LIKE '%"US"%' AND txt NOT LIKE '%"OTHER"%' AND txt !~ '\m19\M' AND txt !~ '"count": 3\M', 'T5 hidden cells appear nowhere in the answer (not their region, not their value)');
  r := public.admin_reward_event_report(NULL, NULL, true);
  PERFORM pg_temp.ok(jsonb_array_length(r->'rows') = 1 AND (r->'rows'->0->>'count')::int = 25 AND (r->>'suppressed_cells')::int = 3, 'T6 by day: only today''s VN=25 is large enough');
  r := public.admin_reward_event_report((now() AT TIME ZONE 'UTC')::date, (now() AT TIME ZONE 'UTC')::date, false);
  PERFORM pg_temp.ok(jsonb_array_length(r->'rows') = 1 AND (r->'rows'->0->>'count')::int = 25, 'T7 date range is honoured');
  BEGIN UPDATE public.reward_event_config SET min_group_size = 4; RAISE EXCEPTION 'T8 threshold below 5 accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
  UPDATE public.reward_event_config SET min_group_size = 5;
  PERFORM pg_temp.ok((public.admin_reward_event_report()->>'min_group_size')::int = 5 AND jsonb_array_length(public.admin_reward_event_report()->'rows') = 2 AND (public.admin_reward_event_report()->>'suppressed_cells')::int = 1,
                     'T8 the threshold lives in the config table (floor 5): lowering it to 5 reveals the 19 cell, still hides the 3');
  UPDATE public.reward_event_config SET min_group_size = 20;

  -- ===== X: cleanup of fixtures + flag off + rollback behaviour with data
  UPDATE public.reward_feature_flags SET enabled = false WHERE flag = 'reward_events';
  PERFORM pg_temp.ok((SELECT count(*) FROM public.reward_event_counters) > 0, 'X0 counters hold data (rollback must not delete it)');
  RAISE NOTICE 'EVENTS RESULT: ALL PASS';
END $t$;
ROLLBACK;
