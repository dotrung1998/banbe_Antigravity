\set A '''11111111-1111-1111-1111-111111111111'''
\set D '''44444444-4444-4444-4444-444444444444'''
\set S1 '''a0000000-0000-0000-0000-000000000001'''
\set S2 '''a0000000-0000-0000-0000-000000000002'''
\set SD '''a0000000-0000-0000-0000-000000000004'''
\echo === 1. client roles cannot read DOB / attempts / cohort tables
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:A,'session_id',:S1)::text, false);
do $$ begin perform 1 from public.user_private_dob; raise exception 'LEAK'; exception when insufficient_privilege then raise notice 'ok: user_private_dob denied'; end $$;
do $$ begin perform 1 from public.dob_attempts; raise exception 'LEAK'; exception when insufficient_privilege then raise notice 'ok: dob_attempts denied'; end $$;
\echo === 2. seeded user A, session1: needs confirmation; private table gated
select public.account_gate_status();
select count(*) as notifications_visible_before_confirm from public.notifications;
\echo === 3. wrong x5 -> lock; correct while locked still LOCKED
select public.confirm_date_of_birth(date '2000-01-01');
select public.confirm_date_of_birth(date '1998-06-14');
select public.confirm_date_of_birth(date '1998-06-16');
select public.confirm_date_of_birth(date '1997-06-15');
select public.confirm_date_of_birth(date '2001-06-15');
select public.confirm_date_of_birth(date '1998-06-15') as correct_while_locked;
reset role;
\echo === 4. lock expiry (simulated) then correct DOB unlocks session1 only
update public.dob_attempts set locked_until = now() - interval '1 minute';
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:A,'session_id',:S1)::text, false);
select public.confirm_date_of_birth(date '1998-06-15') as correct_after_lock;
select (public.account_gate_status()->>'ready') as s1_ready;
select count(*) as notifications_visible_after_confirm from public.notifications;
select set_config('request.jwt.claims', json_build_object('sub',:A,'session_id',:S2)::text, false);
select (public.account_gate_status()->>'ready') as s2_ready_new_login_must_confirm, public.account_gate_status()->>'dob_confirmation_required' as s2_needs_confirm;
select set_config('request.jwt.claims', json_build_object('sub',:A)::text, false);
select (public.account_gate_status()->>'ready') as no_session_claim_ready;
reset role;
\echo === 5. deleting the session removes its confirmation
delete from auth.sessions where id = :S1::uuid;
select count(*) as s1_confirmations_left from public.dob_session_confirmations where session_id = :S1::uuid;
\echo === 6. legacy user D (grandfathered, no DOB): keeps access, no DOB/phone demanded
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:D,'session_id',:SD)::text, false);
select public.account_gate_status();
select count(*) as d_notifications from public.notifications;
select public.confirm_date_of_birth(date '1990-01-01') as confirm_when_no_dob;
reset role;
\echo === 7. NEW user E (post-migration): blocked until phone verified then DOB
insert into auth.users(id,email) values ('55555555-5555-5555-5555-555555555555','new@example.com');
insert into auth.sessions(id,user_id) values ('a0000000-0000-0000-0000-000000000005','55555555-5555-5555-5555-555555555555');
insert into public.notifications(user_id, body) values ('55555555-5555-5555-5555-555555555555','secret');
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub','55555555-5555-5555-5555-555555555555','session_id','a0000000-0000-0000-0000-000000000005')::text, false);
select public.account_gate_status();
select count(*) as e_notifications_blocked from public.notifications;
do $$ begin perform public.set_date_of_birth('1999-02-29'::date); raise exception 'ACCEPTED'; exception when datetime_field_overflow then raise notice 'ok: impossible calendar date rejected'; end $$;
