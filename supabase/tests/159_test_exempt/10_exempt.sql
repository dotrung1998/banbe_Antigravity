-- Fixtures created AFTER migration 123, so none are grandfathered.
insert into auth.users(id,email) values
 ('a1000000-0000-0000-0000-000000000001','exempt@example.com'),
 ('a2000000-0000-0000-0000-000000000002','normal@example.com'),
 ('a3000000-0000-0000-0000-000000000003','verified@example.com');
update auth.users set phone='4915100000000', phone_confirmed_at=now() where id='a3000000-0000-0000-0000-000000000003';
insert into auth.sessions(id,user_id) values
 ('b1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001'),
 ('b1000000-0000-0000-0000-000000000011','a1000000-0000-0000-0000-000000000001'),
 ('b2000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000002'),
 ('b3000000-0000-0000-0000-000000000003','a3000000-0000-0000-0000-000000000003');
insert into auth.users(id,email) values ('a9000000-0000-0000-0000-000000000009','legacy@example.com');
insert into public.account_phone_grandfathered(user_id,cohort) values ('a9000000-0000-0000-0000-000000000009','migration_123');
\echo === grandfathered count before grant (must be unchanged afterwards)
select count(*) as grandfathered_before from public.account_phone_grandfathered;
-- Server-side grant (what the script does with the service role)
set role service_role;
insert into public.account_phone_test_exempt(user_id,reason) values ('a1000000-0000-0000-0000-000000000001','test_account');
reset role;
\set E '''a1000000-0000-0000-0000-000000000001'''
\set N '''a2000000-0000-0000-0000-000000000002'''
\set V '''a3000000-0000-0000-0000-000000000003'''
\set SE '''b1000000-0000-0000-0000-000000000001'''
\set SE2 '''b1000000-0000-0000-0000-000000000011'''
\set SN '''b2000000-0000-0000-0000-000000000002'''
\set SV '''b3000000-0000-0000-0000-000000000003'''

\echo === T1 exempt user: phone NOT required, phone NOT verified, test-exempt flag, DOB STILL required, not ready
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:E,'session_id',:SE)::text, false);
select public.account_gate_status();
select (s->>'phone_required')='false' as ok_phone_not_required, (s->>'phone_verified')='false' as ok_not_verified,
       (s->>'phone_test_exempt')='true' as ok_exempt_flag, (s->>'dob_enrollment_required')='true' as ok_dob_still_required,
       (s->>'ready')='false' as ok_not_ready
  from (select public.account_gate_status() s) q;

\echo === T2 exempt user can enroll DOB without a verified phone; then ready; phone still unverified
select public.set_date_of_birth(date '2000-05-05');
select (s->>'ready')='true' as ok_ready, (s->>'phone_verified')='false' as ok_still_unverified, (s->>'phone_test_exempt')='true' as ok_flag
  from (select public.account_gate_status() s) q;
select public.set_date_of_birth(date '1999-01-01') as second_set_refused;

\echo === T3 exempt user, NEW email-code session must still confirm DOB; password session does not
select set_config('request.jwt.claims', json_build_object('sub',:E,'session_id',:SE2,'amr',json_build_array(json_build_object('method','otp')))::text, false);
select (s->>'dob_confirmation_required')='true' as ok_confirm_still_required, (s->>'ready')='false' as ok_not_ready
  from (select public.account_gate_status() s) q;
select set_config('request.jwt.claims', json_build_object('sub',:E,'session_id',:SE2,'amr',json_build_array(json_build_object('method','password')))::text, false);
select (s->>'dob_confirmation_required')='false' as ok_password_exempt_unchanged from (select public.account_gate_status() s) q;
reset role;

\echo === T4 normal (non-exempt, non-grandfathered) user still blocked: phone required + DOB refused
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:N,'session_id',:SN)::text, false);
select (s->>'phone_required')='true' as ok_phone_required, (s->>'phone_test_exempt')='false' as ok_no_flag,
       (s->>'dob_enrollment_required')='true' as ok_dob_required, (s->>'ready')='false' as ok_not_ready
  from (select public.account_gate_status() s) q;
select (public.set_date_of_birth(date '2000-05-05')->>'error')='PHONE_NOT_VERIFIED' as ok_dob_refused_before_phone;

\echo === T5 really verified phone: verified true, exempt flag false
select set_config('request.jwt.claims', json_build_object('sub',:V,'session_id',:SV)::text, false);
select (s->>'phone_verified')='true' as ok_verified, (s->>'phone_test_exempt')='false' as ok_flag_off
  from (select public.account_gate_status() s) q;
reset role;

\echo === T6 no client can read/grant/alter/delete exemptions (authenticated + anon)
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:N,'session_id',:SN)::text, false);
do $$ begin perform 1 from public.account_phone_test_exempt; raise exception 'LEAK read'; exception when insufficient_privilege then raise notice 'ok: authenticated SELECT denied'; end $$;
do $$ begin insert into public.account_phone_test_exempt(user_id) values ('a2000000-0000-0000-0000-000000000002'); raise exception 'LEAK insert'; exception when insufficient_privilege then raise notice 'ok: authenticated INSERT denied (self-grant impossible)'; end $$;
do $$ begin update public.account_phone_test_exempt set reason='x'; raise exception 'LEAK update'; exception when insufficient_privilege then raise notice 'ok: authenticated UPDATE denied'; end $$;
do $$ begin delete from public.account_phone_test_exempt; raise exception 'LEAK delete'; exception when insufficient_privilege then raise notice 'ok: authenticated DELETE denied'; end $$;
reset role;
set role anon;
do $$ begin perform 1 from public.account_phone_test_exempt; raise exception 'LEAK read'; exception when insufficient_privilege then raise notice 'ok: anon SELECT denied'; end $$;
do $$ begin insert into public.account_phone_test_exempt(user_id) values ('a2000000-0000-0000-0000-000000000002'); raise exception 'LEAK insert'; exception when insufficient_privilege then raise notice 'ok: anon INSERT denied'; end $$;
reset role;
select count(*) = 1 as ok_only_server_row from public.account_phone_test_exempt;
select relrowsecurity as rls_on from pg_class where oid='public.account_phone_test_exempt'::regclass;
select count(*) as policies_on_table from pg_policies where tablename='account_phone_test_exempt';

\echo === T7 legacy grandfathered cohort untouched
select count(*) as grandfathered_after from public.account_phone_grandfathered;
select count(*) = 0 as ok_exempt_not_in_cohort from public.account_phone_grandfathered where user_id='a1000000-0000-0000-0000-000000000001';

\echo === T8 deleting the user cascades the exemption
insert into auth.users(id,email) values ('a4000000-0000-0000-0000-000000000004','tmp@example.com');
insert into public.account_phone_test_exempt(user_id) values ('a4000000-0000-0000-0000-000000000004');
delete from auth.users where id='a4000000-0000-0000-0000-000000000004';
select count(*) = 0 as ok_cascade from public.account_phone_test_exempt where user_id='a4000000-0000-0000-0000-000000000004';
