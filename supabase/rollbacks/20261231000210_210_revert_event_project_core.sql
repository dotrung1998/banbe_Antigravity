-- Revert 210: drop the Event Project Hub core (note 76). Deletes every project, task, topic, run-of-show item, invite
-- and log row. Nothing outside these tables changes (events, bookings, payments and refunds are untouched).
-- Notifications of kinds project_joined / project_blocked are left as they are (they are ordinary inbox rows).
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND (p.proname LIKE 'project\_%' OR p.proname IN (
       'get_event_project', 'get_event_project_posts', 'get_event_project_post', 'get_event_project_trash', 'get_event_project_ros',
       'get_my_event_projects', 'start_event_project', 'peek_project_invite', 'is_event_project_member', 'sanitize_project_channels'))
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %s CASCADE', r.sig);
  END LOOP;
END $$;

DROP TABLE IF EXISTS public.event_project_log, public.event_project_ros_items, public.event_project_post_seen,
  public.event_project_post_replies, public.event_project_post_votes, public.event_project_posts, public.event_project_tasks,
  public.event_project_change_requests, public.event_project_invite_attempts, public.event_project_invites,
  public.event_project_members, public.event_project_lanes, public.event_projects CASCADE;

DELETE FROM public.app_feature_flags WHERE key IN ('event_project_hub', 'project_qr_invite', 'project_delegate_checkin',
  'project_delegate_payments', 'project_delegate_refunds');
DELETE FROM public.app_feature_flag_defs WHERE key IN ('event_project_hub', 'project_qr_invite', 'project_delegate_checkin',
  'project_delegate_payments', 'project_delegate_refunds');
