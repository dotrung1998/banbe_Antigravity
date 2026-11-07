-- LOCAL TEST HARNESS ONLY. Runs INSIDE the transaction opened by 17_rewards_partner_draft_run.sh, after the DRAFT
-- (supabase/drafts/DRAFT_NOT_IN_CHAIN_*.sql) was applied to the throwaway container. The runner rolls everything back.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', u::text, true) $$;
CREATE FUNCTION pg_temp.mkuser(u uuid, handle text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id,email,phone,phone_confirmed_at,raw_user_meta_data,confirmed_at)
  VALUES (u,handle||'@test.dev','+84'||lpad((abs(hashtext(handle)) % 1000000000)::text,9,'0'),now(),jsonb_build_object('display_name',handle),now()) ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles (id,display_name,handle,role,phone,phone_verified) VALUES (u,handle,handle,'participant','+84'||lpad((abs(hashtext(handle)) % 1000000000)::text,9,'0'),true) ON CONFLICT (id) DO NOTHING;
END $$;
CREATE FUNCTION pg_temp.h(code text) RETURNS text LANGUAGE sql AS $$ SELECT encode(sha256(convert_to(upper(btrim(code)),'UTF8')),'hex') $$;

DO $t$
DECLARE
  staff uuid := '7a2a0001-0000-4000-8000-000000000001'; other_staff uuid := '7a2a0002-0000-4000-8000-000000000002';
  nobody uuid := '7a2a0003-0000-4000-8000-000000000003'; holder uuid := '7a2a0004-0000-4000-8000-000000000004';
  sp1 uuid := gen_random_uuid(); sp2 uuid := gen_random_uuid(); camp1 uuid := gen_random_uuid(); camp2 uuid := gen_random_uuid();
  off1 uuid := gen_random_uuid(); off2 uuid := gen_random_uuid(); r jsonb; n int; led int; t text; priv boolean;
BEGIN
  -- ===== S: structure + privileges
  FOREACH t IN ARRAY ARRAY['sponsors','sponsor_staff','sponsor_campaigns','reward_offers','reward_settlements','reward_redemptions'] LOOP
    PERFORM pg_temp.ok(to_regclass('public.'||t) IS NOT NULL AND (SELECT relrowsecurity FROM pg_class WHERE oid = ('public.'||t)::regclass), 'S1 '||t||' exists with RLS on');
    priv := has_table_privilege('anon','public.'||t,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated','public.'||t,'SELECT') OR has_table_privilege('authenticated','public.'||t,'INSERT')
         OR has_table_privilege('authenticated','public.'||t,'UPDATE') OR has_table_privilege('authenticated','public.'||t,'DELETE');
    PERFORM pg_temp.ok(NOT priv, 'S2 '||t||': no client table privileges');
  END LOOP;
  PERFORM pg_temp.ok(NOT has_function_privilege('anon','public.partner_confirm_redemption(text)','EXECUTE') AND has_function_privilege('authenticated','public.partner_confirm_redemption(text)','EXECUTE'), 'S3 stub executable by authenticated only');
  PERFORM pg_temp.ok((SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname ~ '(partner|sponsor|redemption|settlement)' AND p.prokind='f' AND p.proname NOT IN ('partner_confirm_redemption','reward_offers_require_partner_catalog')) = 0,
                 'S4 no other partner/sponsor function exists: no list/read endpoint for partners or about users');
  PERFORM pg_temp.ok((SELECT enabled FROM public.reward_feature_flags WHERE flag='partner_confirm') = false AND (SELECT enabled FROM public.reward_feature_flags WHERE flag='partner_offers') = false, 'S5 both flags OFF');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('sponsors','sponsor_staff','sponsor_campaigns','reward_offers','reward_settlements','reward_redemptions') AND column_name IN ('email','phone','device_id','ip_address','user_agent')), 'S6 no email/phone/device columns anywhere in the new tables');

  -- ===== C: compatibility with 179 (draft alters nothing existing)
  PERFORM pg_temp.ok(md5(pg_get_functiondef('public.get_my_rewards()'::regprocedure)) = current_setting('t.get_md5') AND md5(pg_get_functiondef('public.redeem_reward(text)'::regprocedure)) = current_setting('t.redeem_md5'),
                     'C1 get_my_rewards and redeem_reward are byte-identical before/after the draft');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.reward_catalog) = current_setting('t.catalog_n')::int, 'C2 reward_catalog untouched');

  -- ===== fixtures
  PERFORM pg_temp.mkuser(staff,'u7p001'); PERFORM pg_temp.mkuser(other_staff,'u7p002'); PERFORM pg_temp.mkuser(nobody,'u7p003'); PERFORM pg_temp.mkuser(holder,'u7p004');
  INSERT INTO public.sponsors (id, legal_name, country, kind, status) VALUES (sp1,'Cafe One','VN','venue','active'), (sp2,'Brand Two','US','brand','active');
  INSERT INTO public.sponsor_staff (sponsor_id, user_id) VALUES (sp1, staff), (sp2, other_staff);
  INSERT INTO public.sponsor_campaigns (id, sponsor_id, name, starts_at, ends_at, status) VALUES (camp1,sp1,'C1',now()-interval '1 day',now()+interval '30 days','running'), (camp2,sp2,'C2',now()-interval '1 day',now()+interval '30 days','running');
  INSERT INTO public.reward_catalog (code, kind, design_id, price, sort, title_vi, title_en) VALUES ('po-1','partner_offer',NULL,1,40,'Cà phê miễn phí','Free coffee'), ('po-2','partner_offer',NULL,1,41,'X','Y');
  INSERT INTO public.reward_offers (id, campaign_id, catalog_code, confirm_method, status) VALUES (off1,camp1,'po-1','partner_code','live'), (off2,camp2,'po-2','partner_code','live');
  BEGIN INSERT INTO public.reward_offers (campaign_id, catalog_code, confirm_method) VALUES (camp1,'rwd-comet','partner_code'); RAISE EXCEPTION 'K1 keychain accepted as an offer';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM pg_temp.ok(true, 'K1 an offer must reference a partner_offer catalog row (a keychain design is refused)');
  BEGIN INSERT INTO public.reward_offers (campaign_id, catalog_code, confirm_method) VALUES (camp1,'po-1','partner_code'); RAISE EXCEPTION 'K2 second offer for same listing';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN INSERT INTO public.sponsors (legal_name,country,kind) VALUES ('x','FR','brand'); RAISE EXCEPTION 'K3'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN INSERT INTO public.sponsor_campaigns (sponsor_id,name,starts_at,ends_at) VALUES (sp1,'bad',now(),now()-interval '1 day'); RAISE EXCEPTION 'K4'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN INSERT INTO public.reward_redemptions (user_id,offer_id,status,code_hash,expires_at) VALUES (holder,off1,'redeemed','zz',now()+interval '1 day'); RAISE EXCEPTION 'K5'; EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM pg_temp.ok(true, 'K2-K5 uniqueness, country, date-order and redeemed-needs-redeemed_at constraints hold');
  INSERT INTO public.reward_redemptions (user_id, offer_id, code_hash, expires_at) VALUES
    (holder, off1, pg_temp.h('ABC12345'), now()+interval '1 day'),
    (holder, off2, pg_temp.h('OTH12345'), now()+interval '1 day'), (holder, off1, pg_temp.h('PAU12345'), now()+interval '1 day');
  UPDATE public.reward_redemptions SET status='void' WHERE code_hash = pg_temp.h('PAU12345');
  INSERT INTO public.reward_redemptions (user_id, offer_id, code_hash, issued_at, expires_at) VALUES (holder, off1, pg_temp.h('OLD12345'), now()-interval '2 hours', now()-interval '1 hour');
  SELECT count(*) INTO led FROM public.reward_ledger;

  -- ===== R: the stub
  PERFORM pg_temp.as_user(staff);
  PERFORM pg_temp.ok(public.partner_confirm_redemption('ABC12345')->>'error' = 'NOT_AVAILABLE', 'R1 flag off: NOT_AVAILABLE (inert)');
  UPDATE public.reward_feature_flags SET enabled = true WHERE flag = 'partner_confirm';
  PERFORM pg_temp.as_user(nobody);
  PERFORM pg_temp.ok(public.partner_confirm_redemption('ABC12345')->>'error' = 'CODE_NOT_FOUND', 'R2 a non-staff user cannot confirm (and learns nothing)');
  PERFORM pg_temp.as_user(other_staff);
  PERFORM pg_temp.ok(public.partner_confirm_redemption('ABC12345')->>'error' = 'CODE_NOT_FOUND' AND public.partner_confirm_redemption('NOPE99999')->>'error' = 'CODE_NOT_FOUND', 'R3 another sponsor''s staff gets the same answer as an unknown code');
  PERFORM pg_temp.as_user(staff);
  PERFORM pg_temp.ok(public.partner_confirm_redemption('OTH12345')->>'error' = 'CODE_NOT_FOUND' AND public.partner_confirm_redemption('abc')->>'error' = 'CODE_NOT_FOUND' AND public.partner_confirm_redemption(NULL)->>'error' = 'CODE_NOT_FOUND', 'R4 other sponsor''s code / too-short / null code: CODE_NOT_FOUND');
  PERFORM pg_temp.ok(public.partner_confirm_redemption('PAU12345')->>'error' = 'CODE_NOT_FOUND', 'R5 a void code is not found');
  r := public.partner_confirm_redemption('  abc12345 ');
  PERFORM pg_temp.ok((r->>'success')::boolean AND r->'offer_title'->>'vi' = 'Cà phê miễn phí', 'R6 staff confirms a valid code (case/space-insensitive)');
  PERFORM pg_temp.ok(ARRAY(SELECT jsonb_object_keys(r) ORDER BY 1) = ARRAY['offer_title','redeemed_at','success'], 'R7 the answer has ONLY offer_title + redeemed_at');
  PERFORM pg_temp.ok(r::text NOT LIKE '%'||holder::text||'%' AND r::text NOT LIKE '%u7p004%', 'R8 nothing about the holder leaks into the answer');
  PERFORM pg_temp.ok(public.partner_confirm_redemption('ABC12345')->>'error' = 'ALREADY_REDEEMED', 'R9 a second confirmation is ALREADY_REDEEMED (idempotent, no double use)');
  PERFORM pg_temp.ok((SELECT redeemed_by FROM public.reward_redemptions WHERE code_hash = pg_temp.h('ABC12345')) = staff AND (SELECT status FROM public.reward_redemptions WHERE code_hash = pg_temp.h('ABC12345')) = 'redeemed', 'R10 the staff account is recorded, status redeemed');
  r := public.partner_confirm_redemption('OLD12345');
  PERFORM pg_temp.ok(r->>'error' = 'CODE_EXPIRED' AND (SELECT status FROM public.reward_redemptions WHERE code_hash = pg_temp.h('OLD12345')) = 'expired', 'R11 an expired code is refused and marked expired');
  UPDATE public.sponsor_campaigns SET status = 'paused' WHERE id = camp1; UPDATE public.reward_redemptions SET status='issued', redeemed_at=NULL, redeemed_by=NULL WHERE code_hash = pg_temp.h('ABC12345');
  PERFORM pg_temp.ok(public.partner_confirm_redemption('ABC12345')->>'error' = 'NOT_AVAILABLE', 'R12 a paused campaign cannot be confirmed against');
  UPDATE public.sponsor_campaigns SET status = 'running' WHERE id = camp1; UPDATE public.sponsors SET status = 'suspended' WHERE id = sp1;
  PERFORM pg_temp.ok(public.partner_confirm_redemption('ABC12345')->>'error' = 'CODE_NOT_FOUND', 'R13 a suspended sponsor''s staff lose access');
  UPDATE public.sponsors SET status = 'active' WHERE id = sp1; UPDATE public.sponsor_staff SET status = 'revoked' WHERE user_id = staff;
  PERFORM pg_temp.ok(public.partner_confirm_redemption('ABC12345')->>'error' = 'CODE_NOT_FOUND', 'R14 revoked staff lose access');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.reward_ledger) = led, 'R15 no coin moved at any point (no ledger row written)');
  SET LOCAL ROLE anon;
  BEGIN PERFORM public.partner_confirm_redemption('ABC12345'); RESET ROLE; RAISE EXCEPTION 'R16 anon call'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM count(*) FROM public.reward_redemptions; RESET ROLE; RAISE EXCEPTION 'R17 table readable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  PERFORM pg_temp.ok(true, 'R16-R17 anon cannot call; an authenticated client cannot read the tables');

  -- ===== B: rollback script refuses with data, works when empty
  UPDATE public.reward_feature_flags SET enabled = false WHERE flag = 'partner_confirm';
  BEGIN
    EXECUTE current_setting('t.rollback_sql');
    RAISE EXCEPTION 'B1 rollback ran despite data';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'refusing rollback:%' THEN RAISE; END IF;
  END;
  PERFORM pg_temp.ok(to_regclass('public.reward_redemptions') IS NOT NULL, 'B1 rollback refuses while a table has rows');
  DELETE FROM public.reward_redemptions; DELETE FROM public.reward_offers; DELETE FROM public.sponsor_campaigns; DELETE FROM public.sponsors;
  EXECUTE current_setting('t.rollback_sql');
  PERFORM pg_temp.ok(to_regclass('public.sponsors') IS NULL AND to_regclass('public.reward_redemptions') IS NULL AND to_regprocedure('public.partner_confirm_redemption(text)') IS NULL
                 AND NOT EXISTS (SELECT 1 FROM public.reward_feature_flags WHERE flag='partner_confirm'), 'B2 with empty tables the rollback removes everything it added');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.reward_catalog) = current_setting('t.catalog_n')::int + 2 AND to_regclass('public.reward_catalog') IS NOT NULL, 'B3 existing objects are untouched by the rollback (only test fixtures remain, rolled back by the runner)');
  RAISE NOTICE 'PARTNER DRAFT RESULT: ALL PASS';
END $t$;
