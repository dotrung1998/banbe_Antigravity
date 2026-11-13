-- Note 82 · end times for every production event (36 rows: 26 with an end time, three of them after midnight, and
-- 10 open-ended). Needs migration 220. Touches only events.end_time / end_open; the only triggers on a plain events
-- UPDATE guard r2 refs and removal columns, so no notification, reward or follow alert fires.
-- apply.sql ends in COMMIT, dry-run.sql in ROLLBACK; otherwise identical.
BEGIN;
UPDATE public.events e SET end_time = v.t, end_open = v.o
FROM (VALUES
  ('vaicu', '18:00'::time, false),
  ('maydo', '18:00'::time, false),
  ('aeie-2', NULL, true),
  ('aeie', NULL, true),
  ('compound', '22:00'::time, false),
  ('aodaimoi', '21:30'::time, false),
  ('fanci', NULL, true),
  ('motlop', '22:30'::time, false),
  ('orbit', NULL, true),
  ('phong302', '19:00'::time, false),
  ('giayin', '20:00'::time, false),
  ('khongnguoi', NULL, true),
  ('phimcu', '21:00'::time, false),
  ('vungtrang', NULL, true),
  ('gomxanh', '21:00'::time, false),
  ('sonmai', '21:30'::time, false),
  ('sonmai-2', '21:30'::time, false),
  ('noigiay', '21:00'::time, false),
  ('saxsang', '12:00'::time, false),
  ('chieucham', '18:00'::time, false),
  ('bangcoi', '23:00'::time, false),
  ('tranhtoi', '22:30'::time, false),
  ('jazzgac', '00:00'::time, false),
  ('modular', NULL, true),
  ('pianomuon', '01:00'::time, false),
  ('dembass', NULL, true),
  ('chophien', NULL, true),
  ('vuonsau', '21:30'::time, false),
  ('bunchay', '21:00'::time, false),
  ('test-s-ki-n-8444c8', '22:00'::time, false),
  ('canhchua', '21:30'::time, false),
  ('bepnho', '22:30'::time, false),
  ('bandai', NULL, true),
  ('banrieng', '22:30'::time, false),
  ('comnha', '22:00'::time, false),
  ('phokhuya', '02:00'::time, false)
) AS v(id, t, o)
WHERE e.id = v.id;
SELECT count(*) FILTER (WHERE end_time IS NOT NULL) AS with_end_time,
       count(*) FILTER (WHERE end_open) AS open_ended,
       count(*) FILTER (WHERE end_time IS NULL AND NOT end_open) AS not_stated,
       count(*) FILTER (WHERE end_time IS NOT NULL AND end_time <= event_time) AS next_day
FROM public.events;
ROLLBACK;
