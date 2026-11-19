-- 229 — an event photo may only be uploaded into an event the uploader hosts.
--
-- Audit 2026-11-19 row 32 (P3). 005's `event_photos_host_insert` only asked "is this account ANY organizer's owner" and
-- 093 deliberately left it alone, so any signed-in host could write objects into any event's folder. The row in
-- `event_photos` is owner-checked (001), so this was orphan-blob damage rather than a takeover — still unbounded
-- public storage written by someone else's account.
--
-- Fix: the same rule 093 gave UPDATE/DELETE — the first path segment is the event id (path convention
-- `<event_id>/<timestamp>.<ext>`, uploadEventPhoto / AppState+Data.swift) and the caller must own that event's
-- organizer.
--
-- Rollback: supabase/rollbacks/20261231000229_229_revert_event_photos_insert_scope.sql
-- Tests: supabase/tests/229_photo_insert/run.sh (throwaway stack only).

DROP POLICY IF EXISTS "event_photos_host_insert" ON storage.objects;
CREATE POLICY "event_photos_host_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'event-photos' AND
  EXISTS (
    SELECT 1 FROM public.events e
    JOIN public.organizers o ON o.id = e.organizer_id
    WHERE e.id = split_part(storage.objects.name, '/', 1)
      AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);
