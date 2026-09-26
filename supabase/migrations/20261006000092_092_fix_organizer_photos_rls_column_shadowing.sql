-- 092: root-cause fix for "Không thể lưu. Vui lòng thử lại." on every
-- organizer avatar upload — reproduced directly (upload call, not just
-- code review): Supabase Storage's own upload returned a genuine
-- StorageApiError, "new row violates row-level security policy" (403).
--
-- Migration 090's organizer_photos_owner_write/update/delete policies
-- wrote `split_part(name, '/', 1)` inside a correlated subquery
-- `EXISTS (SELECT 1 FROM organizers o WHERE o.id = split_part(name, '/', 1)
-- AND ...)`. `organizers` ITSELF has a column called `name` — Postgres
-- resolves a bare, unqualified `name` inside that subquery's own scope to
-- the CLOSEST candidate, `organizers.name` (confirmed via `pg_policies`:
-- the stored `qual`/`with_check` literally read
-- `o.id = split_part(o.name, '/', 1)`), never the outer `storage.objects
-- .name` (the actual uploaded path) the policy meant to test. An
-- organizer's own display name never looks like `"<its own id>/..."`, so
-- the EXISTS clause was unconditionally false and every upload/update/
-- delete was denied regardless of who owned what.
--
-- Fixed by qualifying the outer table explicitly (`storage.objects.name`)
-- so the correlated subquery can no longer shadow it with `organizers`'
-- own `name` column.

DROP POLICY IF EXISTS "organizer_photos_owner_write" ON storage.objects;
CREATE POLICY "organizer_photos_owner_write"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'organizer-photos' AND
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = split_part(storage.objects.name, '/', 1) AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);

DROP POLICY IF EXISTS "organizer_photos_owner_update" ON storage.objects;
CREATE POLICY "organizer_photos_owner_update"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'organizer-photos' AND
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = split_part(storage.objects.name, '/', 1) AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);

DROP POLICY IF EXISTS "organizer_photos_owner_delete" ON storage.objects;
CREATE POLICY "organizer_photos_owner_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'organizer-photos' AND
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = split_part(storage.objects.name, '/', 1) AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);
