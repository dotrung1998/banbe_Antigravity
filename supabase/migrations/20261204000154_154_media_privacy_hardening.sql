-- 154: media privacy hardening found by the R2 audit (.claude/notes/28-r2-hybrid-media.md).
-- Tightening only: no data is moved or deleted by this migration, no policy is loosened.

-- 1. cleanup_expired_stories() was executable by EVERY signed-in user. It hard-deletes
--    every organizer's expired story rows (not just the caller's) and returns their
--    storage paths, and nothing in the app ever calls it, so expired story files were
--    never removed from Storage. Lock it to the service role; the media-sweep job now
--    removes expired stories itself (rows AFTER their objects).
REVOKE ALL ON FUNCTION public.cleanup_expired_stories() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_stories() TO service_role;

-- 2. 'event-photos' is a PUBLIC bucket: anyone who knows an object URL can fetch it
--    regardless of RLS (that cannot be changed without moving the object). But the
--    SELECT policy was `TO public USING (bucket_id='event-photos')`, so ANYONE could also
--    LIST the bucket and enumerate every draft / review / withdrawn event's photo path.
--    Listing is now limited to photos of publicly visible events, plus the host and
--    platform admins. Display via public URLs is unaffected (no app code lists this bucket).
--    NOTE: `(objects).name` is deliberate — inside the EXISTS subquery a bare `name` resolves to events.name.
DROP POLICY IF EXISTS "event_photos_public_read" ON storage.objects;
CREATE POLICY "event_photos_public_read"
ON storage.objects FOR SELECT TO public
USING (
  bucket_id = 'event-photos'
  AND (
    EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = split_part((objects).name, '/', 1)
        AND e.status IN ('live', 'ended', 'cancelled')
        AND e.visibility = 'public'
    )
    OR (auth.uid() IS NOT NULL AND (public.is_event_host(split_part((objects).name, '/', 1)) OR public.is_platform_admin()))
  )
);
