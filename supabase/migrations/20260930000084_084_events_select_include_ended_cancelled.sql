-- Migration: fix the REAL root cause of "wrong month for an ended event"
-- (Modular/Compound and any other non-live event) — confirmed by direct
-- query, not guessed: `events_select_public` (migration 001) only ever
-- allowed `status = 'live'` through to anon/authenticated, for anyone who
-- isn't the owning organizer. The instant `goc_mark_past_events` (or an
-- organizer cancelling) flips a row to 'ended'/'cancelled', RLS silently
-- drops it from every ordinary SELECT — indistinguishable, from the
-- client's own perspective, from "this row doesn't exist". Confirmed live:
--   anon SELECT ... WHERE id = 'aeie'     (status='live')      -> 1 row
--   anon SELECT ... WHERE id = 'modular'  (status='ended')     -> 0 rows
--   anon SELECT ... WHERE id = 'compound' (status='ended')     -> 0 rows
--   anon SELECT ... WHERE id = 'bandai'   (status='cancelled') -> 0 rows
-- This is why `liveEventOverrides()`/`applyingLiveStatus()` (the shared
-- merge every screen now goes through, per the last two fix passes) never
-- had a live row to read for these — not a duplicate catalog id, not a
-- missing DB row (every one of these already exists with the correct real
-- date; see the same query above). It also means every OTHER feature that
-- depends on reading a non-owner's ended/cancelled event (the "48h after
-- ended" strip, a cancelled-event banner on Event Detail, etc.) has been
-- silently degraded to the same "looks like it doesn't exist" failure
-- mode for anyone but the organizer, the whole time this app has had
-- ended/cancelled events at all.
--
-- Fix: extend the same policy to also allow `ended`/`cancelled` — an
-- event that has already happened or been called off is not sensitive
-- information (its own live/public visibility already made it public
-- knowledge); only `draft`/`review` (an organizer's own not-yet-published
-- event) stay owner-only, unchanged from before.
DROP POLICY IF EXISTS "events_select_public" ON events;
CREATE POLICY "events_select_public" ON events FOR SELECT TO anon, authenticated USING (
  status IN ('live', 'ended', 'cancelled')
  OR EXISTS (SELECT 1 FROM organizers o WHERE o.id = events.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);
