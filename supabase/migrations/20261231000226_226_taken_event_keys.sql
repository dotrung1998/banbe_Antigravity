-- 226 — the set of production event keys, every status, so the demo catalogue can never stand in for a real event.
--
-- Audit 2026-11-19 row 7 (P1). Search builds its "a real event already owns this key" shadow set from the discovery
-- rows it filters to live+public+not-ended, so a cancelled (or removed) real event frees its key and the static demo
-- twin with the same key reappears — searchable, and opening it showed the demo copy instead of the real event.
-- Moving the set before the status filter covers live/cancelled/ended, but `removed` rows are not in the discovery
-- query at all (RLS only exposes live/ended/cancelled), so the client needs this one deliberately narrow list.
--
-- What it exposes: opaque ids, keys and slugs of events in a non-draft state. No name, price, host or any other
-- content — enough to suppress a twin, nothing to scrape. Callable by anon too, because a signed-out Search has the
-- same twin problem.
--
-- Rollback: supabase/rollbacks/20261231000226_226_revert_taken_event_keys.sql
-- Tests: supabase/tests/226_taken_event_keys/run.sh (throwaway stack only).

CREATE OR REPLACE FUNCTION public.get_taken_event_keys()
RETURNS TABLE (event_id text, event_key text, event_slug text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT e.id, e.key, e.slug
    FROM public.events e
   WHERE e.status IN ('live', 'ended', 'cancelled', 'removed')
$function$;

COMMENT ON FUNCTION public.get_taken_event_keys() IS
  'Audit 2026-11-19 row 7: ids/keys/slugs of real events in any non-draft state, so Search never shows a demo twin.';

REVOKE ALL ON FUNCTION public.get_taken_event_keys() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_taken_event_keys() TO anon, authenticated;
