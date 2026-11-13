-- Rollback for supabase/drafts/v23-testdata/group-c-revive-clone.sql
-- bandai: exact old values (backup ~/banbe-backups/2026-11-13-pre-v23-testdata/events.json).
-- aeie-2 / sonmai-2: rows created by group C. They are deleted ONLY if nothing hangs off them yet
-- (bookings, dispute threads, refund send requests, favorites, threads). Otherwise this refuses and
-- they should go through the admin removal flow (note 54) instead.
-- Run: supabase db query --linked -f <this file>
BEGIN;

DO $$
DECLARE v text;
BEGIN
  SELECT string_agg(t || ':' || n, ', ') INTO v FROM (
    SELECT 'bookings' t, count(*) n FROM bookings WHERE event_id IN ('aeie-2', 'sonmai-2')
    UNION ALL SELECT 'dispute_threads', count(*) FROM dispute_threads WHERE event_id IN ('aeie-2', 'sonmai-2')
    UNION ALL SELECT 'refund_send_requests', count(*) FROM event_refund_send_requests WHERE event_id IN ('aeie-2', 'sonmai-2')
    UNION ALL SELECT 'favorites', count(*) FROM favorites WHERE event_id IN ('aeie-2', 'sonmai-2')
    UNION ALL SELECT 'threads', count(*) FROM threads WHERE event_id IN ('aeie-2', 'sonmai-2')
  ) x WHERE n > 0;
  IF v IS NOT NULL THEN RAISE EXCEPTION 'refusing, records hang off the clones: %', v; END IF;
END $$;

UPDATE events SET status = 'cancelled'::event_status, event_date = '2026-11-14',
       starts_at = '2026-11-14T19:00:00+00:00'::timestamptz
 WHERE id = 'bandai' AND key = 'bandai';

DELETE FROM event_photos WHERE event_id IN ('aeie-2', 'sonmai-2');
DELETE FROM events WHERE id IN ('aeie-2', 'sonmai-2');

COMMIT;
