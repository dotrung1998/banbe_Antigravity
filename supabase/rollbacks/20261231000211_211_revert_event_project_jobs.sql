-- Revert 211: stop the Event Project Hub jobs (note 76). Unschedules both cron jobs, drops the digest and clean-up
-- functions and the digest log, removes the three notification kinds, and puts project_limits() back exactly as 210
-- defined it (without digestHour). Project data is untouched. Notifications already sent stay in people's inboxes.
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname IN ('bb_project_digest', 'bb_project_purge');

DROP FUNCTION IF EXISTS public.send_project_digests(timestamptz);
DROP FUNCTION IF EXISTS public.purge_project_data(timestamptz);
DROP FUNCTION IF EXISTS public.project_digest_items(uuid, timestamptz);
DROP TABLE IF EXISTS public.event_project_digest_log;

DELETE FROM public.notification_kind_policy WHERE kind IN ('project_digest', 'project_blocked', 'project_joined');

CREATE OR REPLACE FUNCTION public.project_limits()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'lanesMax', 10, 'laneNameMax', 24, 'changeWhyMax', 140, 'reasonMin', 3, 'reasonMax', 140,
    'taskTitleMin', 3, 'taskTitleMax', 60, 'postTitleMin', 3, 'postTitleMax', 80, 'postBodyMax', 280,
    'replyMax', 140, 'repliesMax', 10, 'proposalOptionsMin', 2, 'proposalOptionsMax', 4, 'proposalOptionMax', 40,
    'rosTitleMin', 2, 'rosTitleMax', 40, 'rosMinMinutes', 10, 'rosWindowBeforeStartHours', 12, 'rosWindowAfterStartHours', 24,
    'trashMax', 30, 'trashDays', 7, 'channelsMax', 5, 'channelLabelMax', 30, 'channelUrlMax', 300,
    'inviteHours', 48, 'inviteMaxUses', 20, 'grantDays', 7, 'readOnlyDays', 30, 'purgeDays', 90);
$$;
