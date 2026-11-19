BEGIN;

-- Back to 005's policy (any organizer owner may upload anywhere in event-photos).
DROP POLICY IF EXISTS "event_photos_host_insert" ON storage.objects;
CREATE POLICY "event_photos_host_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'event-photos' AND
  EXISTS (
    SELECT 1 FROM public.organizers o
    WHERE o.owner_id = auth.uid() OR o.user_id = auth.uid()
  )
);

COMMIT;
