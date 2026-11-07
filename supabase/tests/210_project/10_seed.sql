-- Seed for the migration 210 tests (throwaway stack only). Fixed ids so test_project.py can target exact rows.
-- Actors mirror tests/fixtures/project-permissions.json. Everyone is grandfathered, so account_gate_ok() is true.
BEGIN;
INSERT INTO auth.users (id, email) VALUES
  ('a0100000-0000-0000-0000-000000000001', 'pj.owner@example.com'),
  ('a0200000-0000-0000-0000-000000000002', 'pj.second@example.com'),
  ('a0300000-0000-0000-0000-000000000003', 'pj.mgr@example.com'),
  ('a0400000-0000-0000-0000-000000000004', 'pj.fin@example.com'),
  ('a0500000-0000-0000-0000-000000000005', 'pj.lead@example.com'),
  ('a0600000-0000-0000-0000-000000000006', 'pj.help@example.com'),
  ('a0700000-0000-0000-0000-000000000007', 'pj.hm@example.com'),
  ('a0800000-0000-0000-0000-000000000008', 'pj.hc@example.com'),
  ('a0900000-0000-0000-0000-000000000009', 'pj.rf@example.com'),
  ('a0a00000-0000-0000-0000-00000000000a', 'pj.out@example.com'),
  ('a0b00000-0000-0000-0000-00000000000b', 'pj.joiner@example.com');
UPDATE public.profiles SET display_name = 'PJ ' || right(id::text, 2) WHERE id IN (SELECT id FROM auth.users WHERE email LIKE 'pj.%@example.com');
INSERT INTO public.account_phone_grandfathered (user_id, cohort)
SELECT id, 'test_210' FROM auth.users WHERE email LIKE 'pj.%@example.com' ON CONFLICT DO NOTHING;

INSERT INTO public.organizers (id, name, owner_id, user_id)
VALUES ('org_pj', 'PJ Kitchen', 'a0100000-0000-0000-0000-000000000001', 'a0200000-0000-0000-0000-000000000002');

INSERT INTO public.events (id, organizer_id, name, status, event_date, event_time, tz, starts_at) VALUES
  ('pj_main', 'org_pj', 'PJ Main', 'live', current_date + 11, '19:00', 'Asia/Ho_Chi_Minh',
     ((current_date + 11) + time '19:00') AT TIME ZONE 'Asia/Ho_Chi_Minh'),
  ('pj_new', 'org_pj', 'PJ New', 'live', current_date + 20, '19:00', 'Asia/Ho_Chi_Minh',
     ((current_date + 20) + time '19:00') AT TIME ZONE 'Asia/Ho_Chi_Minh'),
  ('pj_past', 'org_pj', 'PJ Past', 'ended', current_date - 40, '19:00', 'Asia/Ho_Chi_Minh',
     ((current_date - 40) + time '19:00') AT TIME ZONE 'Asia/Ho_Chi_Minh'),
  ('pj_cancelled', 'org_pj', 'PJ Cancelled', 'cancelled', current_date + 5, '19:00', 'Asia/Ho_Chi_Minh',
     ((current_date + 5) + time '19:00') AT TIME ZONE 'Asia/Ho_Chi_Minh');

UPDATE public.app_feature_flags SET enabled = true WHERE key = 'event_project_hub';

INSERT INTO public.event_projects (event_id, started_by) VALUES
  ('pj_main', 'a0100000-0000-0000-0000-000000000001'), ('pj_past', 'a0100000-0000-0000-0000-000000000001');

INSERT INTO public.event_project_lanes (id, event_id, name, position) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'pj_main', 'Menu', 0),
  ('b0000000-0000-0000-0000-000000000002', 'pj_main', 'Venue', 1),
  ('b0000000-0000-0000-0000-000000000003', 'pj_past', 'Menu', 0);

INSERT INTO public.event_project_members (event_id, user_id, role, lane_id, cap_money, cap_checkin, status)
SELECT ev, u, role, CASE WHEN role = 'lane_lead' THEN (CASE ev WHEN 'pj_main' THEN 'b0000000-0000-0000-0000-000000000001'::uuid ELSE 'b0000000-0000-0000-0000-000000000003'::uuid END) END,
       cm, cc, st
FROM (VALUES ('pj_main'), ('pj_past')) e(ev),
     (VALUES ('a0300000-0000-0000-0000-000000000003'::uuid, 'manager', false, false, 'active'),
             ('a0400000-0000-0000-0000-000000000004'::uuid, 'finance', true, true, 'active'),
             ('a0500000-0000-0000-0000-000000000005'::uuid, 'lane_lead', false, false, 'active'),
             ('a0600000-0000-0000-0000-000000000006'::uuid, 'helper', false, false, 'active'),
             ('a0700000-0000-0000-0000-000000000007'::uuid, 'helper', true, false, 'active'),
             ('a0800000-0000-0000-0000-000000000008'::uuid, 'helper', false, true, 'active'),
             ('a0900000-0000-0000-0000-000000000009'::uuid, 'finance', true, true, 'removed')) m(u, role, cm, cc, st);

INSERT INTO public.event_project_tasks (id, event_id, lane_id, title, assignee_id, status) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'pj_main', 'b0000000-0000-0000-0000-000000000002', 'Check power and air', 'a0600000-0000-0000-0000-000000000006', 'todo'),
  ('c0000000-0000-0000-0000-000000000002', 'pj_main', 'b0000000-0000-0000-0000-000000000001', 'Confirm paid guests', 'a0400000-0000-0000-0000-000000000004', 'doing'),
  ('c0000000-0000-0000-0000-000000000004', 'pj_past', 'b0000000-0000-0000-0000-000000000003', 'Old task', 'a0600000-0000-0000-0000-000000000006', 'todo');
INSERT INTO public.event_project_tasks (id, event_id, lane_id, title, status, deleted_at, deleted_by, delete_reason) VALUES
  ('c0000000-0000-0000-0000-000000000003', 'pj_main', 'b0000000-0000-0000-0000-000000000001', 'Deleted task', 'todo', now(), 'a0100000-0000-0000-0000-000000000001', 'Written wrong');

INSERT INTO public.event_project_posts (id, event_id, lane_id, type, title, author_id, addressee_id, options, state) VALUES
  ('d0000000-0000-0000-0000-000000000001', 'pj_main', 'b0000000-0000-0000-0000-000000000002', 'question', 'Second socket in the garage?', 'a0600000-0000-0000-0000-000000000006', 'a0400000-0000-0000-0000-000000000004', NULL, 'open'),
  ('d0000000-0000-0000-0000-000000000002', 'pj_main', 'b0000000-0000-0000-0000-000000000002', 'question', 'Quiet question here', 'a0600000-0000-0000-0000-000000000006', 'a0100000-0000-0000-0000-000000000001', NULL, 'open'),
  ('d0000000-0000-0000-0000-000000000003', 'pj_main', 'b0000000-0000-0000-0000-000000000001', 'update', 'Deposit paid for tables', 'a0100000-0000-0000-0000-000000000001', NULL, NULL, 'open'),
  ('d0000000-0000-0000-0000-000000000004', 'pj_main', 'b0000000-0000-0000-0000-000000000001', 'proposal', 'Course 3: fish or mushroom?', 'a0500000-0000-0000-0000-000000000005', NULL, '["Fish", "Mushroom"]', 'open'),
  ('d0000000-0000-0000-0000-000000000005', 'pj_main', 'b0000000-0000-0000-0000-000000000001', 'proposal', 'Already settled proposal', 'a0500000-0000-0000-0000-000000000005', NULL, '["A", "B"]', 'resolved'),
  ('d0000000-0000-0000-0000-000000000006', 'pj_main', 'b0000000-0000-0000-0000-000000000001', 'decision', 'Max 14 guests', 'a0100000-0000-0000-0000-000000000001', NULL, NULL, 'locked');
INSERT INTO public.event_project_post_replies (post_id, author_id, body) VALUES
  ('d0000000-0000-0000-0000-000000000001', 'a0400000-0000-0000-0000-000000000004', 'Only one near the door.');
INSERT INTO public.event_project_post_seen (post_id, user_id) VALUES
  ('d0000000-0000-0000-0000-000000000003', 'a0100000-0000-0000-0000-000000000001'),
  ('d0000000-0000-0000-0000-000000000006', 'a0100000-0000-0000-0000-000000000001');

INSERT INTO public.event_project_invites (id, event_id, token, short_code, role, created_by, expires_at) VALUES
  ('e0000000-0000-0000-0000-000000000001', 'pj_main', 'MgrInviteToken00000000', 'BB-MGR2', 'helper', 'a0300000-0000-0000-0000-000000000003', now() + interval '48 hours'),
  ('e0000000-0000-0000-0000-000000000002', 'pj_main', 'OwnInviteToken00000000', 'BB-QWNX', 'helper', 'a0100000-0000-0000-0000-000000000001', now() + interval '48 hours');

INSERT INTO public.event_project_change_requests (id, event_id, kind, payload, why, proposed_by) VALUES
  ('f0000000-0000-0000-0000-000000000001', 'pj_main', 'lane_add', '{"name": "Marketing"}', 'Someone must handle photos', 'a0300000-0000-0000-0000-000000000003');

INSERT INTO public.event_project_ros_items (id, event_id, title, owner_id, starts_at, ends_at) VALUES
  ('90000000-0000-0000-0000-000000000001', 'pj_main', 'Set up kitchen', 'a0500000-0000-0000-0000-000000000005',
     ((current_date + 11) + time '16:00') AT TIME ZONE 'Asia/Ho_Chi_Minh', ((current_date + 11) + time '17:30') AT TIME ZONE 'Asia/Ho_Chi_Minh'),
  ('90000000-0000-0000-0000-000000000002', 'pj_past', 'Old set up', NULL,
     ((current_date - 40) + time '16:00') AT TIME ZONE 'Asia/Ho_Chi_Minh', ((current_date - 40) + time '17:30') AT TIME ZONE 'Asia/Ho_Chi_Minh');
COMMIT;
