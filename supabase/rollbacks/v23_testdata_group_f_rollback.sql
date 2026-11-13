-- Rollback for supabase/drafts/v23-testdata/group-f-events.sql
-- Deletes the 12 new events and their photo rows ONLY if nothing hangs off them yet
-- (bookings, dispute threads, refund send requests, favorites, threads, check-ins). Otherwise it refuses,
-- and those events go through the admin removal flow (note 54). Restores the organizer name.
BEGIN;
DO $$ DECLARE v text; BEGIN
  SELECT string_agg(t || ':' || n, ', ') INTO v FROM (
    SELECT 'bookings' t, count(*) n FROM bookings WHERE event_id IN ('canhchua','bunchay','tranhtoi','dembass','saxsang','vaicu','aodaimoi','maydo','phimcu','gomxanh','giayin','chophien')
    UNION ALL SELECT 'dispute_threads', count(*) FROM dispute_threads WHERE event_id IN ('canhchua','bunchay','tranhtoi','dembass','saxsang','vaicu','aodaimoi','maydo','phimcu','gomxanh','giayin','chophien')
    UNION ALL SELECT 'refund_send_requests', count(*) FROM event_refund_send_requests WHERE event_id IN ('canhchua','bunchay','tranhtoi','dembass','saxsang','vaicu','aodaimoi','maydo','phimcu','gomxanh','giayin','chophien')
    UNION ALL SELECT 'favorites', count(*) FROM favorites WHERE event_id IN ('canhchua','bunchay','tranhtoi','dembass','saxsang','vaicu','aodaimoi','maydo','phimcu','gomxanh','giayin','chophien')
    UNION ALL SELECT 'threads', count(*) FROM threads WHERE event_id IN ('canhchua','bunchay','tranhtoi','dembass','saxsang','vaicu','aodaimoi','maydo','phimcu','gomxanh','giayin','chophien')
    UNION ALL SELECT 'check_ins', count(*) FROM check_ins WHERE event_id IN ('canhchua','bunchay','tranhtoi','dembass','saxsang','vaicu','aodaimoi','maydo','phimcu','gomxanh','giayin','chophien')
  ) x WHERE n > 0;
  IF v IS NOT NULL THEN RAISE EXCEPTION 'refusing, records hang off the new events: %', v; END IF;
END $$;
DELETE FROM event_photos WHERE event_id IN ('canhchua','bunchay','tranhtoi','dembass','saxsang','vaicu','aodaimoi','maydo','phimcu','gomxanh','giayin','chophien');
DELETE FROM events WHERE id IN ('canhchua','bunchay','tranhtoi','dembass','saxsang','vaicu','aodaimoi','maydo','phimcu','gomxanh','giayin','chophien');
UPDATE organizers SET name = $v23$Test$v23$ WHERE id = 'org_a96236c5' AND name = $v23$Nhà Chung$v23$;
COMMIT;
