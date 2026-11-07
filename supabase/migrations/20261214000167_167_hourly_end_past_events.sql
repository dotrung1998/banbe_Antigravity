-- Events have no end time. The old job (008) ran once a day at 00:05 UTC, so an event could sit at
-- status='live' for up to ~36h after it was over (still reservable, still tagged "Going").
-- Run it hourly and catch up immediately.
UPDATE events
   SET status = 'ended'
 WHERE status = 'live'
   AND starts_at IS NOT NULL
   AND starts_at < now() - interval '12 hours';

SELECT cron.unschedule('goc_mark_past_events');
SELECT cron.schedule(
  job_name  => 'goc_mark_past_events',
  schedule  => '5 * * * *',
  command   => $cmd$
    UPDATE events
       SET status = 'ended'
     WHERE status = 'live'
       AND starts_at IS NOT NULL
       AND starts_at < now() - interval '12 hours';
  $cmd$
);
