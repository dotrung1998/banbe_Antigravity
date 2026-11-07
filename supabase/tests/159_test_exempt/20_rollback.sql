\echo === R1 after rollback 160: exempt user is gated by phone again; DOB + other logic intact
insert into auth.users(id,email) values ('a5000000-0000-0000-0000-000000000005','exempt2@example.com');
insert into auth.sessions(id,user_id) values ('b5000000-0000-0000-0000-000000000005','a5000000-0000-0000-0000-000000000005');
select to_regclass('public.account_phone_test_exempt') is null as ok_table_dropped;
select position('test_exempt' in pg_get_functiondef('public.account_gate_status()'::regprocedure)) = 0 as ok_gate_clean,
       position('test_exempt' in pg_get_functiondef('public.set_date_of_birth(date)'::regprocedure)) = 0 as ok_dob_fn_clean,
       position('''password'', ''oauth''' in pg_get_functiondef('public.account_gate_status()'::regprocedure)) > 0 as ok_124_amr_logic_kept;
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub','a1000000-0000-0000-0000-000000000001','session_id','b1000000-0000-0000-0000-000000000001')::text, false);
select (s->>'phone_required')='true' as ok_phone_required_again, not (s ? 'phone_test_exempt') as ok_no_flag_key
  from (select public.account_gate_status() s) q;
reset role;
select count(*) as grandfathered_after_rollback from public.account_phone_grandfathered;
select to_regprocedure('public.admin_set_phone_exemption(uuid,text,date,boolean)') is null and to_regprocedure('public.admin_phone_exempt_lookup(text)') is null and to_regclass('public.phone_test_exempt_audit') is null as ok_admin_objects_dropped;
