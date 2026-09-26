-- Migration 093: Restrict event_photos_host_update/delete to the actual
-- owner of the photo's event.
--
-- 087 introduced these two storage.objects policies so a host could clean
-- up orphaned uploads, but the USING clause only checked "is this account
-- ANY organizer's owner" — never that the photo's event belongs to that
-- organizer. Any authenticated host could therefore update or delete any
-- OTHER host's event photos. event_photos_host_insert (005) has the same
-- shape but is left alone here: inserts are only ever pointed at an event
-- the uploader is actively editing, and the event_photos ROW insert is
-- already owner-checked by event_photos_insert_own (001); this migration
-- closes the update/delete gap specifically, matching the ticket's scope.
--
-- Path convention (GocContext.jsx uploadEventPhoto / AppState+Data.swift):
-- objects.name = "<event_id>/<timestamp>.<ext>", so split_part(name,'/',1)
-- is the event id. No is_admin()/admin-override helper exists elsewhere in
-- storage policies (organizer_photos, pay_qr) so none is added here either.

DROP POLICY IF EXISTS "event_photos_host_update" ON storage.objects;
CREATE POLICY "event_photos_host_update"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'event-photos' AND
  EXISTS (
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = split_part(storage.objects.name, '/', 1)
    AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);

DROP POLICY IF EXISTS "event_photos_host_delete" ON storage.objects;
CREATE POLICY "event_photos_host_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'event-photos' AND
  EXISTS (
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = split_part(storage.objects.name, '/', 1)
    AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);
