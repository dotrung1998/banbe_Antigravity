-- 211 — Event Project Hub jobs (note 76, phase 7): the 18:00 digest and the daily clean-up.
--
--   send_project_digests(p_now)  hourly. At 18:00 on each person's own clock (user_local_zone, like the weekly digest),
--                                one bundled notification per person per local day: my open tasks due by tomorrow (in
--                                each EVENT's zone), posts waiting on me, and (for a Host) blocked tasks. Silent when
--                                there is nothing; muted per kind ('project_digest'); only while event_project_hub is on.
--                                Topics never notify per post: this is the only routine project notification
--                                (blocked tasks alert at once from 210's project_set_task_status).
--   purge_project_data(p_now)    daily. Trash older than 7 days (tasks, posts, run-of-show items, archived lanes; a
--                                lane takes its remaining done tasks and posts with it, exactly like the Host's own
--                                purge in 210), invites expired or revoked for more than a day, invite attempts older
--                                than a day, digest log rows older than 14 days, and whole projects 90 days after the
--                                event ends (project_event_end + purgeDays). Bookings, payments and refunds are not in
--                                these tables and are never touched; the money audit table (212) is not tied to a
--                                project row and follows the booking.
--   Read-only (30 days after the event) needs no job: project_guard() (210) compares now() with project_read_only_at()
--   on every write.
--
-- Notification text is Vietnamese like every server-written notification; 142's localize_notification_text decides
-- what other locales see (no English pattern is added here, so English readers get the Vietnamese text until 142 learns
-- it; same as the weekly digest).
--
-- LOCAL HARNESS ONLY until the owner says otherwise. Rollback: supabase/rollbacks/20261231000211_211_revert_event_project_jobs.sql.

-- ================================================================== limits: + digestHour (= src/data/projectLimits.json)
CREATE OR REPLACE FUNCTION public.project_limits()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'lanesMax', 10, 'laneNameMax', 24, 'changeWhyMax', 140, 'reasonMin', 3, 'reasonMax', 140,
    'taskTitleMin', 3, 'taskTitleMax', 60, 'postTitleMin', 3, 'postTitleMax', 80, 'postBodyMax', 280,
    'replyMax', 140, 'repliesMax', 10, 'proposalOptionsMin', 2, 'proposalOptionsMax', 4, 'proposalOptionMax', 40,
    'rosTitleMin', 2, 'rosTitleMax', 40, 'rosMinMinutes', 10, 'rosWindowBeforeStartHours', 12, 'rosWindowAfterStartHours', 24,
    'trashMax', 30, 'trashDays', 7, 'channelsMax', 5, 'channelLabelMax', 30, 'channelUrlMax', 300,
    'inviteHours', 48, 'inviteMaxUses', 20, 'grantDays', 7, 'readOnlyDays', 30, 'purgeDays', 90, 'digestHour', 18);
$$;

-- ================================================================== notification kinds (service, never promotional)
INSERT INTO public.notification_kind_policy (kind, promotional, note) VALUES
  ('project_digest', false, 'Event Project Hub: 18:00 digest of my tasks and waiting posts (note 76)'),
  ('project_blocked', false, 'Event Project Hub: a task was marked blocked (note 76)'),
  ('project_joined', false, 'Event Project Hub: someone joined with my invite (note 76)')
ON CONFLICT (kind) DO NOTHING;

-- ================================================================== digest
CREATE TABLE IF NOT EXISTS public.event_project_digest_log (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  local_day date NOT NULL,
  items int NOT NULL,
  event_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, local_day)
);
ALTER TABLE public.event_project_digest_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.event_project_digest_log FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.event_project_digest_log TO service_role;

-- What waits on one person in each open project: tasks (mine, open, due by tomorrow in the event's zone; late ones
-- included), posts (a question to me, a proposal I haven't voted on, an update or decision I haven't seen; never my
-- own) and, for a Host, blocked tasks. Projects that are read-only, or whose event is cancelled/removed, are skipped.
CREATE OR REPLACE FUNCTION public.project_digest_items(p_user uuid, p_now timestamptz)
RETURNS TABLE (event_id text, event_name text, tasks int, posts int, blocked int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH mine AS (
    SELECT p.event_id, e.name, e.tz, (p_user = ANY (public.project_host_ids(p.event_id))) AS host
      FROM event_projects p JOIN events e ON e.id = p.event_id
     WHERE e.status::text NOT IN ('cancelled', 'removed')
       AND p_now < public.project_read_only_at(p.event_id)
       AND (p_user = ANY (public.project_host_ids(p.event_id))
            OR EXISTS (SELECT 1 FROM event_project_members m WHERE m.event_id = p.event_id AND m.user_id = p_user AND m.status = 'active'))
  )
  SELECT m.event_id, m.name,
    (SELECT count(*) FROM event_project_tasks t
      WHERE t.event_id = m.event_id AND t.deleted_at IS NULL AND t.status <> 'done' AND t.assignee_id = p_user
        AND t.due_date IS NOT NULL AND t.due_date <= ((p_now AT TIME ZONE coalesce(m.tz, 'Asia/Ho_Chi_Minh'))::date + 1))::int,
    (SELECT count(*) FROM event_project_posts po
      WHERE po.event_id = m.event_id AND po.deleted_at IS NULL AND po.author_id IS DISTINCT FROM p_user AND (
            (po.type = 'question' AND po.state = 'open' AND po.addressee_id = p_user)
         OR (po.type = 'proposal' AND po.state = 'open'
             AND NOT EXISTS (SELECT 1 FROM event_project_post_votes v WHERE v.post_id = po.id AND v.user_id = p_user))
         OR (po.type IN ('update', 'decision')
             AND NOT EXISTS (SELECT 1 FROM event_project_post_seen s WHERE s.post_id = po.id AND s.user_id = p_user))))::int,
    CASE WHEN m.host THEN (SELECT count(*) FROM event_project_tasks t
      WHERE t.event_id = m.event_id AND t.deleted_at IS NULL AND t.status = 'blocked')::int ELSE 0 END
  FROM mine m
$$;

CREATE OR REPLACE FUNCTION public.send_project_digests(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  u record;
  v_local timestamp;
  v_tasks int; v_posts int; v_blocked int;
  v_event text; v_name text; v_projects int;
  v_parts text[];
  v_sent int := 0;
BEGIN
  IF NOT public.app_flag('event_project_hub', false) THEN RETURN 0; END IF;
  FOR u IN
    SELECT DISTINCT x.user_id FROM (
      SELECT m.user_id FROM event_project_members m WHERE m.status = 'active'
      UNION SELECT unnest(public.project_host_ids(p.event_id)) FROM event_projects p) x
    WHERE x.user_id IS NOT NULL
  LOOP
    CONTINUE WHEN public.kind_muted(u.user_id, 'project_digest');
    v_local := p_now AT TIME ZONE public.user_local_zone(u.user_id);
    CONTINUE WHEN extract(hour FROM v_local) <> public.project_limit('digestHour');
    CONTINUE WHEN EXISTS (SELECT 1 FROM event_project_digest_log l WHERE l.user_id = u.user_id AND l.local_day = v_local::date);
    SELECT coalesce(sum(d.tasks), 0), coalesce(sum(d.posts), 0), coalesce(sum(d.blocked), 0),
           count(*) FILTER (WHERE d.tasks + d.posts + d.blocked > 0)
      INTO v_tasks, v_posts, v_blocked, v_projects
      FROM public.project_digest_items(u.user_id, p_now) d;
    CONTINUE WHEN v_tasks + v_posts + v_blocked = 0;   -- nothing real to say: say nothing
    -- The project with the most waiting is where the notification opens.
    SELECT d.event_id, d.event_name INTO v_event, v_name
      FROM public.project_digest_items(u.user_id, p_now) d
     ORDER BY d.blocked + d.tasks + d.posts DESC, d.event_id LIMIT 1;
    v_parts := ARRAY[]::text[];
    IF v_tasks > 0 THEN v_parts := v_parts || (v_tasks || ' việc sắp đến hạn'); END IF;
    IF v_posts > 0 THEN v_parts := v_parts || (v_posts || ' bài đang chờ bạn'); END IF;
    IF v_blocked > 0 THEN v_parts := v_parts || (v_blocked || ' việc bị chặn'); END IF;
    INSERT INTO event_project_digest_log (user_id, local_day, items, event_id)
    VALUES (u.user_id, v_local::date, v_tasks + v_posts + v_blocked, v_event);
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (u.user_id, 'project_digest', 'Dự án hôm nay',
            'Bạn có ' || array_to_string(v_parts, ', ') ||
              CASE WHEN v_projects > 1 THEN ' trong ' || v_projects || ' dự án.' ELSE ' ở ' || v_name || '.' END,
            jsonb_build_object('screen', 'event_project', 'event_id', v_event,
                               'tasks', v_tasks, 'posts', v_posts, 'blocked', v_blocked));
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END;
$$;

-- ================================================================== clean-up
CREATE OR REPLACE FUNCTION public.purge_project_data(p_now timestamptz DEFAULT now())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_cut timestamptz := p_now - make_interval(days => public.project_limit('trashDays'));
  v_tasks int; v_posts int; v_ros int; v_lanes int; v_invites int; v_attempts int; v_digest int; v_projects int;
BEGIN
  -- Whole projects first (everything below cascades with them).
  DELETE FROM event_projects p
   WHERE public.project_event_end(p.event_id) + make_interval(days => public.project_limit('purgeDays')) <= p_now;
  GET DIAGNOSTICS v_projects = ROW_COUNT;

  DELETE FROM event_project_tasks WHERE deleted_at IS NOT NULL AND deleted_at <= v_cut;
  GET DIAGNOSTICS v_tasks = ROW_COUNT;
  DELETE FROM event_project_posts WHERE deleted_at IS NOT NULL AND deleted_at <= v_cut;
  GET DIAGNOSTICS v_posts = ROW_COUNT;
  DELETE FROM event_project_ros_items WHERE deleted_at IS NOT NULL AND deleted_at <= v_cut;
  GET DIAGNOSTICS v_ros = ROW_COUNT;
  DELETE FROM event_project_lanes WHERE archived_at IS NOT NULL AND archived_at <= v_cut;
  GET DIAGNOSTICS v_lanes = ROW_COUNT;

  DELETE FROM event_project_invites
   WHERE expires_at <= p_now - interval '1 day' OR (revoked_at IS NOT NULL AND revoked_at <= p_now - interval '1 day');
  GET DIAGNOSTICS v_invites = ROW_COUNT;
  DELETE FROM event_project_invite_attempts WHERE at <= p_now - interval '1 day';
  GET DIAGNOSTICS v_attempts = ROW_COUNT;
  DELETE FROM event_project_digest_log WHERE local_day <= (p_now - interval '14 days')::date;
  GET DIAGNOSTICS v_digest = ROW_COUNT;

  RETURN jsonb_build_object('projects', v_projects, 'tasks', v_tasks, 'posts', v_posts, 'ros', v_ros, 'lanes', v_lanes,
                            'invites', v_invites, 'attempts', v_attempts, 'digest_log', v_digest);
END;
$$;

-- ================================================================== who may call what
-- Jobs and their helper are server-only (Supabase grants new functions to anon/authenticated by default).
REVOKE ALL ON FUNCTION public.project_digest_items(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.send_project_digests(timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.purge_project_data(timestamptz) FROM PUBLIC, anon, authenticated;
-- project_limits() was granted to nobody in 210 either (it is used inside definer functions only).
REVOKE ALL ON FUNCTION public.project_limits() FROM PUBLIC, anon, authenticated;

-- ================================================================== schedules (UTC)
SELECT cron.schedule('bb_project_digest', '7 * * * *', $cmd$ SELECT public.send_project_digests(); $cmd$);
SELECT cron.schedule('bb_project_purge', '17 20 * * *', $cmd$ SELECT public.purge_project_data(); $cmd$);
