-- Stubs for what production already has (026 is_platform_admin, 001 profile columns).
alter table public.profiles add column if not exists phone text default '', add column if not exists phone_verified boolean not null default false;
create or replace function public.is_platform_admin() returns boolean language sql security definer stable set search_path=public as $$ select exists (select 1 from profiles where id = auth.uid() and role='admin') $$;
grant execute on function public.is_platform_admin() to authenticated;
-- admin (grandfathered legacy-style, so the gate lets them through), a normal member, targets
insert into auth.users(id,email) values
 ('c1000000-0000-0000-0000-000000000001','admin@example.com'),
 ('c2000000-0000-0000-0000-000000000002','member@example.com'),
 ('c3000000-0000-0000-0000-000000000003','target@example.com'),
 ('c4000000-0000-0000-0000-000000000004','other@example.com');
insert into auth.sessions(id,user_id) values
 ('d1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001'),
 ('d2000000-0000-0000-0000-000000000002','c2000000-0000-0000-0000-000000000002');
insert into public.profiles(id,display_name,role,phone) values
 ('c1000000-0000-0000-0000-000000000001','Admin','admin',''),
 ('c2000000-0000-0000-0000-000000000002','Member','participant',''),
 ('c3000000-0000-0000-0000-000000000003','Target','participant',''),
 ('c4000000-0000-0000-0000-000000000004','Other','participant','+4915111111111')
 on conflict (id) do update set role=excluded.role, phone=excluded.phone;
insert into public.account_phone_grandfathered(user_id,cohort) values ('c1000000-0000-0000-0000-000000000001','legacy'),('c2000000-0000-0000-0000-000000000002','legacy');
\set AD '''c1000000-0000-0000-0000-000000000001'''
\set ME '''c2000000-0000-0000-0000-000000000002'''
\set TG '''c3000000-0000-0000-0000-000000000003'''
\set OT '''c4000000-0000-0000-0000-000000000004'''

\echo === A1 normal member cannot look up or grant
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:ME,'session_id','d2000000-0000-0000-0000-000000000002')::text, false);
select (public.admin_phone_exempt_lookup('target@example.com')->>'error')='NOT_AUTHORIZED' as ok_lookup_denied;
select (public.admin_set_phone_exemption(:TG::uuid, '+16467212169', date '1999-08-11', true)->>'error')='NOT_AUTHORIZED' as ok_grant_denied;
select (public.admin_set_phone_exemption(:ME::uuid, '+16467212169', null, true)->>'error')='NOT_AUTHORIZED' as ok_self_grant_denied;
reset role;
select count(*)=0 as ok_nothing_written from public.account_phone_test_exempt where user_id in (:TG::uuid,:ME::uuid);

\echo === A2 admin: lookup, validate, grant
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:AD,'session_id','d1000000-0000-0000-0000-000000000001')::text, false);
select public.admin_phone_exempt_lookup('TARGET@example.com');
select (public.admin_phone_exempt_lookup('nobody@example.com')->>'error')='USER_NOT_FOUND' as ok_not_found;
select (public.admin_set_phone_exemption(:AD::uuid, null, null, true)->>'error')='INVALID_TARGET' as ok_self_refused;
select (public.admin_set_phone_exemption(:TG::uuid, '12345', null, true)->>'error')='INVALID_PHONE' as ok_bad_phone;
select (public.admin_set_phone_exemption(:TG::uuid, '+10123456789', null, true)->>'error')='INVALID_PHONE' as ok_bad_nanp;
select (public.admin_set_phone_exemption(:TG::uuid, '+4915111111111', null, true)->>'error')='PHONE_IN_USE' as ok_collision;
select (public.admin_set_phone_exemption(:TG::uuid, '+4917656035288', date '2999-01-01', true)->>'error')='INVALID_DOB' as ok_future_dob;
reset role;
select count(*)=0 as ok_failed_calls_wrote_nothing from public.account_phone_test_exempt where user_id=:TG::uuid;
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:AD,'session_id','d1000000-0000-0000-0000-000000000001')::text, false);
select public.admin_set_phone_exemption(:TG::uuid, '+4917656035288', date '1999-08-11', true);
reset role;
select p.phone='+4917656035288' as ok_phone_stored, p.phone_verified=false as ok_unverified,
       exists(select 1 from public.account_phone_test_exempt where user_id=:TG::uuid and granted_by=:AD::uuid) as ok_exempt_by_admin,
       exists(select 1 from public.user_private_dob where user_id=:TG::uuid and source='admin_test_seed') as ok_dob_seeded,
       (select phone_confirmed_at is null and coalesce(phone,'')='' from auth.users where id=:TG::uuid) as ok_auth_phone_untouched
  from public.profiles p where p.id=:TG::uuid;
select count(*)=1 as ok_audit_row, bool_and(dob_seeded) as ok_audit_dob_flag from public.phone_test_exempt_audit where target_user_id=:TG::uuid;

\echo === A3 existing DOB is never changed; same value is idempotent; revoke works
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:AD,'session_id','d1000000-0000-0000-0000-000000000001')::text, false);
select (public.admin_set_phone_exemption(:TG::uuid, null, date '2000-01-01', true)->>'error')='DOB_ALREADY_SET' as ok_dob_not_overwritten;
select (public.admin_set_phone_exemption(:TG::uuid, null, date '1999-08-11', true)->>'success')='true' as ok_same_dob_idempotent;
select (public.admin_set_phone_exemption(:ME::uuid, null, null, true)->>'grandfathered')='true' as ok_grandfathered_noop_flag;
reset role;
select count(*)=0 as ok_no_exempt_row_for_grandfathered from public.account_phone_test_exempt where user_id=:ME::uuid;
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:AD,'session_id','d1000000-0000-0000-0000-000000000001')::text, false);
select (public.admin_set_phone_exemption(:TG::uuid, null, null, false)->>'test_exempt')='false' as ok_revoked;
reset role;

\echo === A4 audit table unreadable by clients; exempt user (target) gate now matches
set role authenticated;
do $$ begin perform 1 from public.phone_test_exempt_audit; raise exception 'LEAK'; exception when insufficient_privilege then raise notice 'ok: audit denied to clients'; end $$;
reset role;

\echo === A5 search by display name (migration 161): admin only, no private fields
\i /tmp/161.sql
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub',:ME,'session_id','d2000000-0000-0000-0000-000000000002')::text, false);
select (public.admin_phone_exempt_search('tar')->>'error')='NOT_AUTHORIZED' as ok_member_denied;
select set_config('request.jwt.claims', json_build_object('sub',:AD,'session_id','d1000000-0000-0000-0000-000000000001')::text, false);
select jsonb_array_length(public.admin_phone_exempt_search('TARG')->'results')=1 as ok_one_match,
       (public.admin_phone_exempt_search('TARG')->'results'->0->>'email')='target@example.com' as ok_email,
       not (public.admin_phone_exempt_search('TARG')->'results'->0 ? 'profile_phone') as ok_no_private_fields;
select jsonb_array_length(public.admin_phone_exempt_search('t')->'results')=0 as ok_too_short_empty;
select jsonb_array_length(public.admin_phone_exempt_search('%')->'results')=0 as ok_wildcard_escaped;
reset role;
