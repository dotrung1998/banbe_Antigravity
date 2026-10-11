-- LOCAL TEST HARNESS ONLY. DB migrated to 179 (NOT 180): snapshot the old RPCs' definitions and results.
\set ON_ERROR_STOP on
CREATE TABLE public._ev_snap (k text PRIMARY KEY, v jsonb);
INSERT INTO auth.users (id,email,phone,phone_confirmed_at,raw_user_meta_data,confirmed_at)
VALUES ('7a3a0001-0000-4000-8000-000000000001','u7e001@test.dev','+84900031001',now(),'{"display_name":"u7e001"}',now()) ON CONFLICT (id) DO NOTHING;
INSERT INTO profiles (id,display_name,handle,role,phone,phone_verified) VALUES ('7a3a0001-0000-4000-8000-000000000001','u7e001','u7e001','participant','+84900031001',true) ON CONFLICT (id) DO NOTHING;
INSERT INTO account_phone_grandfathered(user_id,cohort) VALUES ('7a3a0001-0000-4000-8000-000000000001','t') ON CONFLICT DO NOTHING;
SELECT public.rewards_add_entry('7a3a0001-0000-4000-8000-000000000001','award',100,'seed:e1',NULL,'attendance','{}');
SELECT set_config('request.jwt.claim.sub','7a3a0001-0000-4000-8000-000000000001',false);
INSERT INTO public._ev_snap SELECT 'def:'||p.proname, to_jsonb(md5(pg_get_functiondef(p.oid)))
  FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname IN ('get_my_rewards','redeem_reward','get_my_reward_summary','record_active_day','save_my_keychain','get_my_unlocked_cosmetics','profile_keychains_require_unlock','rewards_streak_of');
INSERT INTO public._ev_snap VALUES ('res:rewards', (public.get_my_rewards() - 'streak'));  -- streak has no volatile bits, but keep it simple
INSERT INTO public._ev_snap VALUES ('res:summary', public.get_my_reward_summary());
INSERT INTO public._ev_snap VALUES ('res:redeem', public.redeem_reward('rwd-comet'));
INSERT INTO public._ev_snap VALUES ('res:redeem2', public.redeem_reward('rwd-comet'));
INSERT INTO public._ev_snap VALUES ('res:rewards_after_redeem', (public.get_my_rewards() - 'streak' - 'history'));
