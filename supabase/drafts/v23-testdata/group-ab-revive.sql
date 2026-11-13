-- v2.3 test data, groups A + B: move test events 0–3 weeks ahead and set them live again.
-- NOT a migration (not in the chain). Run with: supabase db query --linked -f <this file>
-- The file ends in ROLLBACK (dry run). The apply copy swaps the last line for COMMIT.
-- Only the event row changes: event_date, starts_at, status. event_time is kept as it is.
-- starts_at follows migration 195's rule: (event_date + event_time) AT TIME ZONE tz.
-- (The seeded rows had starts_at = the wall-clock time stored as UTC, 7 h late. This fixes that too.)
-- Bookings, refunds, disputes, chats, attendees: not touched. No DELETE.
-- Rollback: supabase/rollbacks/v23_testdata_group_ab_rollback.sql (exact old values).

BEGIN;

-- 'd' n = n days after today (venue date). 'sat' n = n days after the coming Saturday
-- (today if today is Saturday). Times stay each event's own event_time.
CREATE TEMP TABLE v23_plan (key text PRIMARY KEY, grp text, slot text, n int) ON COMMIT DROP;
INSERT INTO v23_plan VALUES
  -- group A: no money records
  ('phokhuya',   'A', 'd',   0),  -- tonight 23:00
  ('modular',    'A', 'd',   0),  -- tonight 21:30
  ('bangcoi',    'A', 'd',   1),
  ('orbit',      'A', 'sat', 0),
  ('compound',   'A', 'sat', 0),
  ('jazzgac',    'A', 'sat', 1),
  ('chieucham',  'A', 'sat', 1),
  ('khongnguoi', 'A', 'sat', 1),
  ('fanci',      'A', 'd',   3),
  ('motlop',     'A', 'd',   4),
  ('banrieng',   'A', 'sat', 7),
  ('phong302',   'A', 'sat', 8),
  ('comnha',     'A', 'd',  10),
  -- group B: old bookings stay attached (expired, or confirmed test tickets)
  ('vuonsau',    'B', 'sat', 0),
  ('vungtrang',  'B', 'sat', 0),
  ('pianomuon',  'B', 'd',   5),
  ('noigiay',    'B', 'd',   6),
  ('bepnho',     'B', 'sat', 7);

CREATE TEMP TABLE v23_before ON COMMIT DROP AS
SELECT e.id, e.key, e.status, e.event_date, e.event_time, e.starts_at, e.tz
  FROM events e JOIN v23_plan p ON p.key = e.key;

CREATE TEMP TABLE v23_badges_before ON COMMIT DROP AS
SELECT count(*) AS n FROM reward_user_badges;

DO $$
DECLARE v_bad text;
BEGIN
  IF (SELECT count(*) FROM v23_before) <> (SELECT count(*) FROM v23_plan) THEN
    RAISE EXCEPTION 'plan/key mismatch: % planned, % found', (SELECT count(*) FROM v23_plan), (SELECT count(*) FROM v23_before);
  END IF;
  SELECT string_agg(key || '=' || status, ', ') INTO v_bad FROM v23_before WHERE status NOT IN ('ended', 'live');
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'refusing: not ended/live: %', v_bad; END IF;
END $$;

WITH d AS (
  SELECT p.key,
         (now() AT TIME ZONE b.tz)::date AS today
    FROM v23_plan p JOIN v23_before b USING (key)
), t AS (
  SELECT d.key,
         CASE p.slot
           WHEN 'd' THEN d.today + p.n
           ELSE d.today + ((6 - extract(isodow FROM d.today)::int + 7) % 7) + p.n
         END AS new_date
    FROM d JOIN v23_plan p USING (key)
)
UPDATE events e
   SET event_date = t.new_date,
       starts_at  = (t.new_date + e.event_time) AT TIME ZONE e.tz,
       status     = 'live'
  FROM t
 WHERE e.key = t.key;

-- Diff, venue time. Nothing must end again within the hour: 167 ends live events 12 h after start.
SELECT p.grp, b.key,
       b.status || ' → ' || e.status AS status,
       to_char(b.starts_at AT TIME ZONE b.tz, 'Dy DD Mon HH24:MI') || ' → ' ||
       to_char(e.starts_at AT TIME ZONE e.tz, 'Dy DD Mon HH24:MI') AS venue_time,
       (e.starts_at < now() - interval '12 hours') AS would_end_now,
       (SELECT n FROM v23_badges_before) AS badges_before,
       (SELECT count(*) FROM reward_user_badges) AS badges_after
  FROM v23_before b JOIN events e ON e.id = b.id JOIN v23_plan p ON p.key = b.key
 ORDER BY e.starts_at;

ROLLBACK;
