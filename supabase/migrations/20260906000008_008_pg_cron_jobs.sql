-- Migration: pg_cron state cleanup jobs

CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
  job_name  => 'goc_expire_lapsed_pendings',
  schedule  => '* * * * *',
  command   => $cmd$
    UPDATE bookings
    SET status = 'expired'
    WHERE status = 'pending'
      AND expires_at IS NOT NULL
      AND expires_at < now();
  $cmd$
);

CREATE OR REPLACE FUNCTION goc_flag_overdue_refunds()
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  v_count int := 0;
  v_row record;
BEGIN
  FOR v_row IN
    SELECT rc.id, e.organizer_id
    FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    WHERE rc.status = 'owed'
      AND rc.last_flagged_at IS NULL
      AND rc.created_at < now() - interval '72 hours'
      AND e.organizer_id IS NOT NULL
  LOOP
    UPDATE organizers
       SET disputes_open = COALESCE(disputes_open, 0) + 1
     WHERE id = v_row.organizer_id;

    UPDATE refund_claims
       SET last_flagged_at = now()
     WHERE id = v_row.id;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION goc_flag_overdue_refunds() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION goc_flag_overdue_refunds() FROM anon;
GRANT EXECUTE ON FUNCTION goc_flag_overdue_refunds() TO authenticated;

SELECT cron.schedule(
  job_name  => 'goc_flag_overdue_refunds',
  schedule  => '0 * * * *',
  command   => $cmd$ SELECT goc_flag_overdue_refunds(); $cmd$
);

SELECT cron.schedule(
  job_name  => 'goc_mark_past_events',
  schedule  => '5 0 * * *',
  command   => $cmd$
    UPDATE events
       SET status = 'ended'
     WHERE status = 'live'
       AND starts_at IS NOT NULL
       AND starts_at < now() - interval '12 hours';
  $cmd$
);
