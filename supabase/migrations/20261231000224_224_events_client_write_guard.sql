-- 224 — a host's direct `events` write cannot skip review or move the terms of a booked event.
--
-- Audit 2026-11-19 row 3 (P1). `events_insert_own` / `events_update_own` (001:127-137) check only that the caller owns
-- the organizer, so a host could INSERT or UPDATE `events` straight through PostgREST: flip status to 'live' (or
-- 'ended'/'cancelled') bypassing the admin review queue (085), or change price_vnd / capacity / currency / visibility
-- after guests had booked (capacity below seats sold, price moved under a hold). 189 guards the removal fields only.
--
-- The app does write `events` directly, for legitimate fields (chat_greeting, end_time, end_open, cover), so a plain
-- REVOKE is not the fix. This trigger separates the two paths the database already knows apart:
--   * a direct client write runs as the `authenticated` / `anon` role;
--   * every sanctioned status or terms change runs inside a SECURITY DEFINER RPC (create_event_draft,
--     resubmit_event_for_review, admin_review_event, cancel_event, admin_remove_events, …) where `current_user` is the
--     function owner, and service-role work (api/*, cron) runs as service_role.
-- Only the direct path is constrained:
--   INSERT  — status must be draft/review (never live/ended/cancelled/removed).
--   UPDATE  — status may not change at all; price_vnd / capacity / currency / visibility may not change once the event
--             has a seat-holding booking (confirmed/attended, or a pending hold that has not lapsed).
-- Platform admins are exempt, as they are in the RPCs.
--
-- Rollback: supabase/rollbacks/20261231000224_224_revert_events_client_write_guard.sql
-- Tests: supabase/tests/224_events_client_write_guard/run.sh (throwaway stack only).

-- SECURITY INVOKER on purpose: `current_user` must be the role that issued the write. A SECURITY DEFINER trigger
-- would report its own owner and the guard would never fire.
CREATE OR REPLACE FUNCTION public.events_guard_client_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  -- Trusted paths: SECURITY DEFINER RPCs (their owner is current_user), service_role (api/cron), migrations/seed.
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  IF coalesce(public.is_platform_admin(), false) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status NOT IN ('draft', 'review') THEN
      RAISE EXCEPTION 'EVENT_STATUS_REVIEW_REQUIRED';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'EVENT_STATUS_GUARDED';
  END IF;

  IF (NEW.price_vnd IS DISTINCT FROM OLD.price_vnd
      OR NEW.capacity IS DISTINCT FROM OLD.capacity
      OR NEW.currency IS DISTINCT FROM OLD.currency
      OR NEW.visibility IS DISTINCT FROM OLD.visibility)
     AND EXISTS (
       SELECT 1 FROM public.bookings b
        WHERE b.event_id = OLD.id
          AND (b.status IN ('confirmed', 'attended')
               OR (b.status = 'pending' AND coalesce(b.hold_expires_at, b.expires_at) > now()))
     )
  THEN
    RAISE EXCEPTION 'EVENT_TERMS_LOCKED_AFTER_BOOKING';
  END IF;

  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.events_guard_client_write() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS events_guard_client_write ON public.events;
CREATE TRIGGER events_guard_client_write
  BEFORE INSERT OR UPDATE ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION public.events_guard_client_write();

COMMENT ON FUNCTION public.events_guard_client_write() IS
  'Audit 2026-11-19 row 3: direct client events writes may not change status, nor price/capacity/currency/visibility once booked.';
