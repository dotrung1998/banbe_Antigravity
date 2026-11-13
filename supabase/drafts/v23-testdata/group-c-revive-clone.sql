-- v2.3 test data, group C (owner choices 2026-11-13):
--   test-s-ki-n-8444c8: (b) leave as it is (refunds + closed disputes). Not touched here.
--   bandai: (a) revive the event row only (cancelled, no bookings, cancelled_at was never set).
--   aeie:   (c) clone into a fresh live event 'aeie-2' (the original keeps its refund claim and stays ended).
--   sonmai: (c) clone into a fresh live event 'sonmai-2' (the original keeps its cancelled bookings and stays cancelled).
-- Clones copy every column of the source row plus its event_photos rows (same storage paths, no file copies).
-- NOT a migration. Run with: supabase db query --linked -f <this file>
-- Ends in ROLLBACK (dry run). The apply copy swaps the last line for COMMIT.
-- Rollback: supabase/rollbacks/v23_testdata_group_c_rollback.sql
-- starts_at follows migration 195: (event_date + event_time) AT TIME ZONE tz. No DELETE.

BEGIN;

CREATE TEMP TABLE v23_c (src text, new_key text, n int) ON COMMIT DROP;
INSERT INTO v23_c VALUES
  ('bandai', 'bandai',   5),   -- today + 5, same row
  ('aeie',   'aeie-2',   7),   -- today + 7, new row
  ('sonmai', 'sonmai-2', 11);  -- today + 11, new row

DO $$
BEGIN
  IF (SELECT status FROM events WHERE key = 'bandai') <> 'cancelled' THEN RAISE EXCEPTION 'bandai is not cancelled'; END IF;
  IF EXISTS (SELECT 1 FROM bookings WHERE event_id = 'bandai') THEN RAISE EXCEPTION 'bandai has bookings'; END IF;
  IF EXISTS (SELECT 1 FROM events WHERE id IN ('aeie-2', 'sonmai-2') OR slug IN ('aeie-2', 'sonmai-2')) THEN
    RAISE EXCEPTION 'clone ids already exist';
  END IF;
END $$;

-- (a) bandai: the row only
UPDATE events e
   SET status     = 'live',
       event_date = (now() AT TIME ZONE e.tz)::date + 5,
       starts_at  = (((now() AT TIME ZONE e.tz)::date + 5) + e.event_time) AT TIME ZONE e.tz
 WHERE e.key = 'bandai';

-- (c) clones
INSERT INTO events
SELECT (jsonb_populate_record(NULL::events,
          to_jsonb(e) || jsonb_build_object(
            'id', c.new_key, 'key', c.new_key, 'slug', c.new_key,
            'status', 'live',
            'event_date', ((now() AT TIME ZONE e.tz)::date + c.n),
            'starts_at', ((((now() AT TIME ZONE e.tz)::date + c.n) + e.event_time) AT TIME ZONE e.tz),
            'created_at', now(), 'submitted_at', now(), 'reviewed_at', now(),
            'cancelled_at', NULL, 'cancel_reason', '',
            'removed_at', NULL, 'removed_by', NULL, 'removed_from_status', NULL,
            'withdrawn_at', NULL,
            'resubmission_count', 0, 'resubmission_window_start', NULL,
            'admin_remind_count', 0, 'last_admin_reminded_at', NULL,
            'seats_remaining', e.capacity
          ))).*
  FROM events e JOIN v23_c c ON c.src = e.key AND c.new_key <> c.src;

INSERT INTO event_photos (event_id, storage_path, sort_order, r2_ref)
SELECT c.new_key, p.storage_path, p.sort_order, p.r2_ref
  FROM event_photos p JOIN v23_c c ON c.src = p.event_id AND c.new_key <> c.src;

-- Diff
SELECT c.src, c.new_key,
       s.status::text AS source_status_after,
       n.status::text AS target_status,
       to_char(n.starts_at AT TIME ZONE n.tz, 'Dy DD Mon HH24:MI') AS target_venue_time,
       n.organizer_id = s.organizer_id AS same_host,
       (SELECT count(*) FROM event_photos WHERE event_id = n.id) AS photos,
       n.details = s.details AS same_details,
       (SELECT count(*) FROM bookings WHERE event_id = n.id) AS target_bookings
  FROM v23_c c JOIN events s ON s.key = c.src JOIN events n ON n.key = c.new_key
 ORDER BY n.starts_at;

ROLLBACK;
