-- LOCAL TEST HARNESS ONLY. Runs on the same database AFTER migration 179 is applied.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
DO $t$
DECLARE
  rich uuid := '7a1a0001-0000-4000-8000-000000000001'; poor uuid := '7a1a0002-0000-4000-8000-000000000002'; zero uuid := '7a1a0003-0000-4000-8000-000000000003';
  twin_b uuid := '7a1a0004-0000-4000-8000-000000000004'; twin_a uuid := '7a1a0005-0000-4000-8000-000000000005';
  r jsonb; n int; led int; bal int; v_ledger_before int; kk text;
BEGIN
  -- ===== O: old data, old calls, identical results
  PERFORM pg_temp.ok((SELECT v FROM public._kind_snap WHERE label='before' AND k='view:'||rich) = public._kind_view(rich), 'O1 rich user (pre-179 unlock): balance, catalog, unlocks, summary identical');
  PERFORM pg_temp.ok((SELECT v FROM public._kind_snap WHERE label='before' AND k='view:'||poor) = public._kind_view(poor) AND
                     (SELECT v FROM public._kind_snap WHERE label='before' AND k='view:'||zero) = public._kind_view(zero), 'O2 poor and zero users identical');
  PERFORM pg_temp.ok((public._kind_view(rich)->'unlocked') = '["rwd-lantern"]'::jsonb AND (public._kind_view(rich)->>'balance')::int = 120, 'O3 the existing unlock still shows and the balance did not change (200 - 80)');
  PERFORM public._kind_as(rich);
  PERFORM pg_temp.ok((SELECT (x->>'unlocked')::boolean FROM jsonb_array_elements(public.get_my_rewards()->'catalog') x WHERE x->>'code'='rwd-lantern'), 'O5 unlocked item reads unlocked=true');
  PERFORM pg_temp.ok((SELECT v FROM public._kind_snap WHERE label='before' AND k='unlock_rows')
                     = (SELECT to_jsonb(array_agg(u.user_id||':'||u.item_code ORDER BY u.user_id, u.item_code)) FROM public.reward_unlocks u WHERE u.user_id <> twin_a), 'O6 reward_unlocks rows untouched by 179 (the twin is excluded: it is scripted after)');
  PERFORM pg_temp.ok((SELECT v - twin_a::text FROM public._kind_snap WHERE label='before' AND k='balances')
                     = (SELECT jsonb_object_agg(p.id::text, public.rewards_balance(p.id)) - twin_a::text FROM profiles p WHERE p.id::text LIKE '7a1a%'), 'O7 every pre-existing balance is identical');
  -- the scripted history on a twin account must give exactly what the twin got before 179
  INSERT INTO public._kind_snap VALUES ('after','script', public._kind_script(twin_a));
  PERFORM pg_temp.ok((SELECT v FROM public._kind_snap WHERE label='before' AND k='script') = (SELECT v FROM public._kind_snap WHERE label='after' AND k='script'),
                     'O8 redeem/again/poor/unknown + locked/unlocked/free keychain saves + direct locked write: byte-identical to pre-179');
  PERFORM pg_temp.ok((SELECT v FROM public._kind_snap WHERE label='before' AND k='catalog_rows')
                     = (SELECT jsonb_agg(to_jsonb(c) - 'title_vi' - 'title_en' - 'desc_vi' - 'desc_en' ORDER BY c.code) FROM public.reward_catalog c), 'O9 catalog rows unchanged (only new nullable columns added)');

  -- ===== K: the new kind
  INSERT INTO public.reward_catalog (code, kind, design_id, price, sort, title_vi, title_en, desc_vi, desc_en)
  VALUES ('offer-x', 'partner_offer', NULL, 50, 40, 'Ưu đãi X', 'Offer X', 'mô tả', 'description');
  PERFORM pg_temp.ok(true, 'K1 a partner_offer row without design_id is accepted');
  BEGIN INSERT INTO public.reward_catalog (code, kind, design_id, price) VALUES ('bad-k', 'keychain_design', NULL, 10); RAISE EXCEPTION 'K2 design-less keychain accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN INSERT INTO public.reward_catalog (code, kind, design_id, price) VALUES ('bad-kind', 'voucher', NULL, 10); RAISE EXCEPTION 'K2b unknown kind accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM pg_temp.ok(true, 'K2 a keychain_design still requires a design_id, and unknown kinds are refused');
  PERFORM public._kind_as(rich);
  v_ledger_before := (SELECT count(*) FROM public.reward_ledger); bal := public.rewards_balance(rich);
  r := public.redeem_reward('offer-x');
  PERFORM pg_temp.ok(r->>'error' = 'NOT_AVAILABLE' AND (r->>'success')::boolean = false, 'K3 redeeming a partner_offer returns NOT_AVAILABLE');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.reward_ledger) = v_ledger_before AND public.rewards_balance(rich) = bal AND NOT EXISTS (SELECT 1 FROM public.reward_unlocks WHERE item_code='offer-x'), 'K4 …and charged nothing, unlocked nothing');
  PERFORM public._kind_as(zero);
  PERFORM pg_temp.ok(public.redeem_reward('offer-x')->>'error' = 'NOT_AVAILABLE', 'K5 same answer for a user who could not afford it (no balance leak)');
  r := public.get_my_rewards();
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'catalog') x WHERE x->>'kind' <> 'keychain_design') AND jsonb_array_length(r->'catalog') = 3, 'K6 catalog (what old clients read) still lists ONLY the 3 keychain designs');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'catalog') x WHERE jsonb_typeof(x->'design_id') <> 'string'), 'K7 every catalog row still has a string design_id (old iOS decoder requirement)');
  PERFORM pg_temp.ok(r->'offers' = '[]'::jsonb, 'K8 offers is [] while the partner_offers flag is off');
  FOREACH kk IN ARRAY ARRAY['success','balance','rules','streak','badges','history','catalog','attendance_paid_this_month','timezone_settings'] LOOP
    PERFORM pg_temp.ok(r ? kk, 'K9 get_my_rewards still has '||kk);
  END LOOP;
  PERFORM pg_temp.ok((SELECT (x ? 'code' AND x ? 'kind' AND x ? 'design_id' AND x ? 'price' AND x ? 'unlocked' AND x ? 'status') FROM jsonb_array_elements(r->'catalog') x LIMIT 1), 'K10 catalog items keep code/kind/design_id/price/unlocked and gain status');
  UPDATE public.reward_feature_flags SET enabled = true WHERE flag = 'partner_offers';
  r := public.get_my_rewards();
  PERFORM pg_temp.ok(jsonb_array_length(r->'offers') = 1 AND r->'offers'->0->>'code' = 'offer-x' AND r->'offers'->0->>'status' = 'unavailable' AND r->'offers'->0->>'title_en' = 'Offer X', 'K11 flag on: the offer appears in `offers` (display only, status unavailable)');
  PERFORM pg_temp.ok(jsonb_array_length(r->'catalog') = 3, 'K12 …and still not in `catalog`');
  PERFORM pg_temp.ok(public.redeem_reward('offer-x')->>'error' = 'NOT_AVAILABLE', 'K13 flag on does not open a redemption path in 179');
  UPDATE public.reward_catalog SET active = false WHERE code = 'offer-x';
  PERFORM pg_temp.ok(jsonb_array_length(public.get_my_rewards()->'offers') = 0, 'K14 an inactive offer is hidden');
  UPDATE public.reward_feature_flags SET enabled = false WHERE flag = 'partner_offers';

  -- ===== L: keychain locking only looks at keychain_design rows
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.reward_catalog WHERE code='offer-x' AND design_id IS NOT NULL), 'L0 offer has no design');
  PERFORM public._kind_as(zero);
  PERFORM pg_temp.ok((public.save_my_keychain('{"designId":"sky-moon"}'::jsonb)->>'success')::boolean, 'L1 a free design is unaffected by a partner row');
  -- a partner_offer must never "lock" a design: give it a design id of a built-in charm via superuser and check it stays free
  INSERT INTO public.reward_catalog (code, kind, design_id, price, sort, active) VALUES ('offer-y','partner_offer','sky-cloud',10,50,false);
  PERFORM pg_temp.ok((public.save_my_keychain('{"designId":"sky-cloud"}'::jsonb)->>'success')::boolean, 'L2 a partner_offer sharing a design id does not lock that free charm');
  PERFORM pg_temp.ok(public.save_my_keychain('{"designId":"rwd-crown"}'::jsonb)->>'error' = 'DESIGN_LOCKED', 'L3 a real reward design is still locked until redeemed');
  PERFORM pg_temp.ok(NOT ('sky-cloud' = ANY (ARRAY(SELECT jsonb_array_elements_text(public.get_my_unlocked_cosmetics()->'design_ids')))), 'L4 get_my_unlocked_cosmetics ignores non-keychain rows');

  -- ===== P: privileges unchanged / new table closed
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM count(*) FROM public.reward_feature_flags; RESET ROLE; RAISE EXCEPTION 'P1 flags readable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM count(*) FROM public.reward_catalog; RESET ROLE; RAISE EXCEPTION 'P2 catalog readable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE anon;
  BEGIN PERFORM public.redeem_reward('rwd-comet'); RESET ROLE; RAISE EXCEPTION 'P3 anon redeem'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  PERFORM pg_temp.ok((SELECT enabled FROM public.reward_feature_flags WHERE flag='partner_offers') = false, 'P4 partner_offers flag is OFF');
  RAISE NOTICE 'KINDS RESULT: ALL PASS';
END $t$;
