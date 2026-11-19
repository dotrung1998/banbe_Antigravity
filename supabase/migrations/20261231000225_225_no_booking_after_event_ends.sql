-- 225 — no booking can be created for an event that is already over.
--
-- Audit 2026-11-19 row 6 (P1), server half. `hold_seats` (219:50) checks only `status = 'live'`, and the ended sweep
-- (migration 167) flips that status hourly, so between an event's real end and the next sweep a live row stayed
-- bookable — the client showed "Hôm nay" and an active Reserve for a 19:00–21:00 event at 21:44. The client now has
-- one rule (`isEventOver` in src/lib/eventEnd.js); this is the same rule in SQL, applied where every booking is
-- created, without rewriting hold_seats / hold_seats_with_attendees / claim_seats:
--   * a host-set end time (events.end_time, wall clock in the event's own zone; at or before the start means the next
--     venue day), or
--   * the note 38 fallback, 12 h after the start, when the end is open-ended or not stated.
-- The guard is a BEFORE INSERT trigger on bookings, so it also covers any future insert path. It only rejects rows for
-- an event still marked 'live' that is past its end: an explicitly 'ended'/'cancelled' event is already refused by
-- hold_seats' own status check, and seed/test fixtures that book historical events (usually marked 'ended') keep
-- working.
--
-- Rollback: supabase/rollbacks/20261231000225_225_revert_no_booking_after_event_ends.sql
-- Tests: supabase/tests/225_event_ended_hold/run.sh (throwaway stack only).

-- The instant an event is over, exactly as the client computes it.
CREATE OR REPLACE FUNCTION public.event_ends_at(
  p_starts_at timestamptz,
  p_end_time time,
  p_end_open boolean,
  p_tz text
) RETURNS timestamptz
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  WITH z AS (
    SELECT coalesce(nullif(p_tz, ''), 'Asia/Ho_Chi_Minh') AS tz
  ), d AS (
    SELECT z.tz, (p_starts_at AT TIME ZONE z.tz)::date AS day FROM z
  )
  SELECT CASE
    WHEN p_starts_at IS NULL THEN NULL
    WHEN p_end_time IS NULL THEN p_starts_at + interval '12 hours'
    WHEN ((d.day + p_end_time) AT TIME ZONE d.tz) <= p_starts_at
      THEN ((d.day + 1) + p_end_time) AT TIME ZONE d.tz
    ELSE (d.day + p_end_time) AT TIME ZONE d.tz
  END
  FROM d
$function$;

COMMENT ON FUNCTION public.event_ends_at(timestamptz, time, boolean, text) IS
  'Audit 2026-11-19 row 6: when an event is over — end_time on the venue clock, or start + 12h when open-ended/not stated.';

CREATE OR REPLACE FUNCTION public.bookings_guard_event_over()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.event_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1
      FROM public.events e
     WHERE e.id = NEW.event_id
       AND e.status = 'live'
       AND public.event_ends_at(e.starts_at, e.end_time, e.end_open, e.tz) <= now()
  ) THEN
    RAISE EXCEPTION 'EVENT_ENDED';
  END IF;
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.bookings_guard_event_over() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS bookings_guard_event_over ON public.bookings;
CREATE TRIGGER bookings_guard_event_over
  BEFORE INSERT ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.bookings_guard_event_over();
