-- LOCAL TEST HARNESS ONLY. Runs on a database migrated to 178 (NOT 179). Builds legacy-shaped data and records what
-- the OLD functions return, so 16b_kinds_after.sql can prove 179 changes nothing for existing data.
\set ON_ERROR_STOP on
CREATE TABLE public._kind_snap (label text, k text, v jsonb);
CREATE FUNCTION public._kind_user(u uuid, handle text, coins int) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id,email,phone,phone_confirmed_at,raw_user_meta_data,confirmed_at)
  VALUES (u,handle||'@test.dev','+8490004'||substr(handle,2,4),now(),jsonb_build_object('display_name',handle),now()) ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles (id,display_name,handle,role,phone,phone_verified)
  VALUES (u,handle,handle,'participant','+8490004'||substr(handle,2,4),true) ON CONFLICT (id) DO NOTHING;
  INSERT INTO account_phone_grandfathered(user_id,cohort) VALUES (u,'t') ON CONFLICT DO NOTHING;
  IF coins > 0 THEN PERFORM public.rewards_add_entry(u,'award',coins,'seed:'||handle,NULL,'attendance','{}'); END IF;
END $$;
CREATE FUNCTION public._kind_as(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', u::text, false) $$;
-- the old client's view of get_my_rewards: only the keys a pre-179 client reads
CREATE FUNCTION public._kind_view(u uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  PERFORM public._kind_as(u); r := public.get_my_rewards();
  RETURN jsonb_build_object('balance', r->'balance',
    'catalog', (SELECT jsonb_agg(jsonb_build_object('code',x->'code','kind',x->'kind','design_id',x->'design_id','price',x->'price','unlocked',x->'unlocked') ORDER BY ordinality)
                  FROM jsonb_array_elements(r->'catalog') WITH ORDINALITY AS t(x, ordinality)),
    'history_types', (SELECT jsonb_agg(h->'type' ORDER BY ord) FROM jsonb_array_elements(r->'history') WITH ORDINALITY AS t(h, ord)),
    'streak', r->'streak'->'current', 'rules', r->'rules', 'paid', r->'attendance_paid_this_month',
    'unlocked', public.get_my_unlocked_cosmetics()->'design_ids', 'summary', public.get_my_reward_summary());
END $$;
-- an identical scripted history for one user; returns every client-visible result (ids stripped)
CREATE FUNCTION public._kind_script(u uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE o jsonb := '{}'; r jsonb;
BEGIN
  PERFORM public._kind_as(u);
  o := o || jsonb_build_object('redeem_comet', public.redeem_reward('rwd-comet'));
  o := o || jsonb_build_object('redeem_comet_again', public.redeem_reward('rwd-comet'));
  o := o || jsonb_build_object('redeem_lantern_poor', public.redeem_reward('rwd-lantern'));
  o := o || jsonb_build_object('redeem_unknown', public.redeem_reward('nope'));
  o := o || jsonb_build_object('save_locked', public.save_my_keychain('{"designId":"rwd-crown","enabled":true}'::jsonb)->'error');
  o := o || jsonb_build_object('save_unlocked', public.save_my_keychain('{"designId":"rwd-comet","enabled":true}'::jsonb)->'success');
  o := o || jsonb_build_object('save_free', public.save_my_keychain('{"designId":"sky-star"}'::jsonb)->'success');
  BEGIN UPDATE public.profile_keychains SET design_id = 'rwd-lantern' WHERE user_id = u; o := o || jsonb_build_object('direct_locked','ALLOWED');
  EXCEPTION WHEN check_violation THEN o := o || jsonb_build_object('direct_locked','DESIGN_LOCKED'); END;
  o := o || jsonb_build_object('view', public._kind_view(u));
  RETURN o;
END $$;

-- legacy population: a rich user who already owns one unlock + spent coins, a poor user, a zero user
SELECT public._kind_user('7a1a0001-0000-4000-8000-000000000001','u7k001',200);
SELECT public._kind_user('7a1a0002-0000-4000-8000-000000000002','u7k002',30);
SELECT public._kind_user('7a1a0003-0000-4000-8000-000000000003','u7k003',0);
SELECT public._kind_user('7a1a0004-0000-4000-8000-000000000004','u7k004',60);   -- scripted twin of ..0005
SELECT public._kind_user('7a1a0005-0000-4000-8000-000000000005','u7k005',60);
SELECT public._kind_as('7a1a0001-0000-4000-8000-000000000001');
SELECT public.redeem_reward('rwd-lantern');                                      -- a real pre-179 unlock
SELECT public._kind_as('7a1a0001-0000-4000-8000-000000000001');
SELECT public.save_my_keychain('{"designId":"rwd-lantern","enabled":true}'::jsonb);
INSERT INTO public._kind_snap SELECT 'before', 'view:'||id, public._kind_view(id) FROM profiles WHERE id IN
  ('7a1a0001-0000-4000-8000-000000000001','7a1a0002-0000-4000-8000-000000000002','7a1a0003-0000-4000-8000-000000000003');
INSERT INTO public._kind_snap VALUES ('before','script', public._kind_script('7a1a0004-0000-4000-8000-000000000004'));
INSERT INTO public._kind_snap SELECT 'before', 'catalog_rows', to_jsonb(array_agg(c ORDER BY c.code)) FROM public.reward_catalog c;
INSERT INTO public._kind_snap SELECT 'before', 'unlock_rows', to_jsonb(array_agg(u.user_id||':'||u.item_code ORDER BY u.user_id, u.item_code)) FROM public.reward_unlocks u;
INSERT INTO public._kind_snap SELECT 'before', 'balances', jsonb_object_agg(p.id::text, public.rewards_balance(p.id)) FROM profiles p WHERE p.id::text LIKE '7a1a%';
