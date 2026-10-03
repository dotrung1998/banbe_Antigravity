\echo === 11. (migration 125) check-in guest info: host only, ticket only, audited
reset role;
insert into public.profiles(id, display_name) values ('11111111-1111-1111-1111-111111111111','Host A') on conflict do nothing;
insert into public.events(id, organizer_id, name) values ('ev2','org1','Door test') on conflict do nothing;
insert into public.bookings(id,event_id,user_id,status) values
 ('b0000000-0000-0000-0000-000000000001','ev2','11111111-1111-1111-1111-111111111111','confirmed'),
 ('b0000000-0000-0000-0000-000000000002','ev2','44444444-4444-4444-4444-444444444444','pending'),
 ('b0000000-0000-0000-0000-000000000003','ev2','44444444-4444-4444-4444-444444444444','confirmed');
insert into public.profiles(id, display_name) values ('44444444-4444-4444-4444-444444444444','Legacy Goer') on conflict do nothing;
set role authenticated;
-- host A (owner of org1), session confirmed earlier in this script
select set_config('request.jwt.claims', json_build_object('sub','11111111-1111-1111-1111-111111111111','session_id','a0000000-0000-0000-0000-000000000002')::text, false);
select public.get_checkin_guest_info('b0000000-0000-0000-0000-000000000001') as own_ticket_name_and_dob;
select public.get_checkin_guest_info('b0000000-0000-0000-0000-000000000003') as legacy_goer_dob_null;
select public.get_checkin_guest_info('b0000000-0000-0000-0000-000000000002') as pending_not_eligible;
select public.get_checkin_guest_info('b0000000-0000-0000-0000-0000000000ff') as unknown_booking;
-- a non-host sees the same answer as unknown
select set_config('request.jwt.claims', json_build_object('sub','66666666-6666-6666-6666-666666666666','session_id','a0000000-0000-0000-0000-000000000006')::text, false);
select public.get_checkin_guest_info('b0000000-0000-0000-0000-000000000001') as non_host_denied;
do $$ begin perform 1 from public.checkin_dob_views; raise exception 'LEAK'; exception when insufficient_privilege then raise notice 'ok: audit table denied'; end $$;
reset role;
select count(*) as audit_rows from public.checkin_dob_views;
