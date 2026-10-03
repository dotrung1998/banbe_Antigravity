\set E '''55555555-5555-5555-5555-555555555555'''
\set SE '''a0000000-0000-0000-0000-000000000005'''
\echo === 8. E: DOB before phone verified is refused; after phone: future refused, valid stored once
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:E,'session_id',:SE)::text, false);
select public.set_date_of_birth(date '1999-03-01') as before_phone;
reset role;
update auth.users set phone='+14155550100', phone_confirmed_at=now() where id=:E::uuid;
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:E,'session_id',:SE)::text, false);
select public.set_date_of_birth(current_date + 1) as future_dob;
select public.set_date_of_birth(date '1899-12-31') as too_old;
select public.set_date_of_birth(date '2000-02-29') as leap_day_ok;
select public.set_date_of_birth(date '1990-01-01') as second_attempt_cannot_overwrite;
select (public.account_gate_status()->>'ready') as e_ready_after_enrollment;
select count(*) as e_notifications_visible from public.notifications;
reset role;
select date_of_birth as stored_not_overwritten from public.user_private_dob where user_id=:E::uuid;
\echo === 9. promo: default off; consent; one recipient at a time; no phone leak
insert into public.organizers(id, owner_id, name) values ('org1','11111111-1111-1111-1111-111111111111','Org One');
insert into public.events(id, organizer_id, name) values ('ev1','org1','Rooftop Groove');
insert into auth.users(id,email,phone,phone_confirmed_at) values
 ('66666666-6666-6666-6666-666666666666','guest1@example.com','+84901234567',now()),
 ('77777777-7777-7777-7777-777777777777','guest2@example.com','+84907654321',now()),
 ('88888888-8888-8888-8888-888888888888','stranger@example.com','+84900000000',now());
insert into public.profiles(id, display_name, locale) values
 ('66666666-6666-6666-6666-666666666666','Guest One','vi'),('77777777-7777-7777-7777-777777777777','Guest Two','en'),('88888888-8888-8888-8888-888888888888','Stranger','en');
insert into public.bookings(event_id,user_id,status) values ('ev1','66666666-6666-6666-6666-666666666666','confirmed');
insert into public.follows(user_id,organizer_id) values ('77777777-7777-7777-7777-777777777777','org1');
-- grandfather the guests so the gate passes for them
insert into public.account_phone_grandfathered(user_id,cohort) values
 ('66666666-6666-6666-6666-666666666666','t'),('77777777-7777-7777-7777-777777777777','t'),('88888888-8888-8888-8888-888888888888','t');
insert into auth.sessions(id,user_id) values
 ('a0000000-0000-0000-0000-000000000006','66666666-6666-6666-6666-666666666666'),
 ('a0000000-0000-0000-0000-000000000007','77777777-7777-7777-7777-777777777777'),
 ('a0000000-0000-0000-0000-000000000008','88888888-8888-8888-8888-888888888888');
-- host A (owner) must pass the DOB gate this session
insert into public.dob_session_confirmations(session_id,user_id) values ('a0000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111');
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub','11111111-1111-1111-1111-111111111111','session_id','a0000000-0000-0000-0000-000000000002')::text, false);
select public.next_promo_recipient('ev1') as none_consented_yet;
select set_config('request.jwt.claims', json_build_object('sub','66666666-6666-6666-6666-666666666666','session_id','a0000000-0000-0000-0000-000000000006')::text, false);
select public.get_host_promo_consent() as g1_default;
select public.set_host_promo_consent(true) as g1_opt_in;
select set_config('request.jwt.claims', json_build_object('sub','77777777-7777-7777-7777-777777777777','session_id','a0000000-0000-0000-0000-000000000007')::text, false);
select public.set_host_promo_consent(true) as g2_opt_in;
select set_config('request.jwt.claims', json_build_object('sub','88888888-8888-8888-8888-888888888888','session_id','a0000000-0000-0000-0000-000000000008')::text, false);
select public.set_host_promo_consent(true) as stranger_opt_in_but_no_relationship;
\echo --- host
select set_config('request.jwt.claims', json_build_object('sub','11111111-1111-1111-1111-111111111111','session_id','a0000000-0000-0000-0000-000000000002')::text, false);
select public.next_promo_recipient('ev1') as first_recipient_no_phone;
select public.begin_promo_compose('ev1','88888888-8888-8888-8888-888888888888') as stranger_refused;
select public.begin_promo_compose('ev1','66666666-6666-6666-6666-666666666666') as begin_guest1;
select public.begin_promo_compose('ev1','66666666-6666-6666-6666-666666666666') as repeat_refused;
select public.next_promo_recipient('ev1') as second_recipient;
\echo --- guest2 withdraws consent after being listed
select set_config('request.jwt.claims', json_build_object('sub','77777777-7777-7777-7777-777777777777','session_id','a0000000-0000-0000-0000-000000000007')::text, false);
select public.set_host_promo_consent(false) as g2_withdraw;
select set_config('request.jwt.claims', json_build_object('sub','11111111-1111-1111-1111-111111111111','session_id','a0000000-0000-0000-0000-000000000002')::text, false);
select public.begin_promo_compose('ev1','77777777-7777-7777-7777-777777777777') as begin_after_withdrawal_refused;
select public.next_promo_recipient('ev1') as no_one_left;
\echo --- a non-host cannot compose; clients cannot read consent/log tables
select set_config('request.jwt.claims', json_build_object('sub','66666666-6666-6666-6666-666666666666','session_id','a0000000-0000-0000-0000-000000000006')::text, false);
select public.next_promo_recipient('ev1') as nonhost_denied;
do $$ begin perform 1 from public.host_promo_consent; raise exception 'LEAK'; exception when insufficient_privilege then raise notice 'ok: consent table denied'; end $$;
do $$ begin perform 1 from public.host_promo_compose_log; raise exception 'LEAK'; exception when insufficient_privilege then raise notice 'ok: log table denied'; end $$;
