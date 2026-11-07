-- Migration: make the 20260910000020 seed's demo events track real time
-- instead of a single frozen week (2026-07-08 .. 2026-07-15).
--
-- Confirmed problem (see .claude/notes/07-notifications.md): that seed only
-- ever wrote `event_date`/`event_time`, never `starts_at` — and `starts_at`
-- is this schema's real anchor column (020600920000057's own comment: "the
-- primary anchor (timestamptz); event_date+event_time is the fallback for a
-- row where starts_at was never set"). `goc_mark_past_events`
-- (008_pg_cron_jobs.sql) only ever looks at `starts_at`, so these rows were
-- never swept to 'ended' no matter how far in the past their date drifted —
-- two compounding problems (frozen date, status never following it) from
-- one root cause.
--
-- This is a one-time, idempotent-safe data fix (not a repeatable seed): it
-- reassigns each of the 21 demo events from that migration a fresh
-- `starts_at`/`event_date` spread randomly across genuinely-past,
-- happening-very-soon, and further-out-future — a realistic live-marketplace
-- mix instead of one static week — and brings `status` in line with the new
-- date (past -> 'ended', current/future -> 'live'). `cancelled`/`draft`
-- events are left alone, per their own intentional status.
--
-- Safe to re-run: re-randomizes the same 21 rows every time it's applied,
-- which is fine (there's nothing downstream keyed to a specific prior
-- random date), and only ever touches rows by their known fixed ids.

DO $$
DECLARE
  v_ids text[] := ARRAY[
    'bepnho', 'comnha', 'bandai', 'phokhuya', 'vuonsau', 'orbit', 'aeie',
    'fanci', 'compound', 'motlop', 'vungtrang', 'sonmai', 'khongnguoi',
    'noigiay', 'phong302', 'chieucham', 'jazzgac', 'bangcoi', 'modular',
    'pianomuon', 'banrieng'
  ];
  v_id text;
  v_bucket float8;
  v_offset_days int;
  v_new_starts_at timestamptz;
BEGIN
  FOREACH v_id IN ARRAY v_ids LOOP
    -- 35% clearly-past (1-45 days ago), 30% very soon/this week (0-6 days
    -- out), 35% further out (1-9 weeks out) — a realistic marketplace mix,
    -- not one static bucket.
    v_bucket := random();
    IF v_bucket < 0.35 THEN
      v_offset_days := -(1 + floor(random() * 45)::int);
    ELSIF v_bucket < 0.65 THEN
      v_offset_days := floor(random() * 7)::int;
    ELSE
      v_offset_days := 7 + floor(random() * 60)::int;
    END IF;

    SELECT (current_date + v_offset_days) + COALESCE(e.event_time, '19:00'::time)
      INTO v_new_starts_at
    FROM public.events e WHERE e.id = v_id;

    IF v_new_starts_at IS NULL THEN
      CONTINUE; -- event id not present (e.g. seed migration never ran here)
    END IF;

    UPDATE public.events e
       SET starts_at = v_new_starts_at,
           event_date = (current_date + v_offset_days),
           status = CASE
             WHEN e.status IN ('cancelled', 'draft') THEN e.status
             WHEN v_new_starts_at < now() THEN 'ended'::event_status
             ELSE 'live'::event_status
           END
     WHERE e.id = v_id;
  END LOOP;
END $$;
