-- 104: iPhone fix pass (2026-09-27), Issue 2 — CONFIRMED root cause of "iOS
-- avatar change fails for the personal profile (and any Team-member's own
-- personal profile — same code path)": migration 079's avatars_owner_write/
-- update/delete policies compare `split_part(name, '/', 1) = auth.uid()::text`
-- as plain TEXT. Postgres's `uuid::text` cast always produces the canonical
-- LOWERCASE form; the iOS client (AppState+Profile.swift's uploadAvatar())
-- builds its own upload path from Swift's `UUID.uuidString`, which is
-- ALWAYS UPPERCASE — a real, deterministic case mismatch, not a guess:
-- confirmed by reading both sides (this policy's own text and Swift's own
-- `UUID.uuidString` documentation), and consistent with "Remove still
-- works" (removeAvatar() never uploads — it's a bare save_profile() RPC
-- call with an empty avatar_url override, so it never touches this
-- policy at all) while picking a NEW image (upload first) fails every
-- time. Web's own uploadAvatar() (GocContext.jsx) builds its path from
-- `supabase.auth`'s own session user id, which is already lowercase —
-- exactly why this was never seen on web.
--
-- Fixed by lower-casing the path segment before comparing, which makes the
-- policy correct for ANY future client regardless of how it happens to
-- format a UUID, not just a targeted iOS-only patch.

DROP POLICY IF EXISTS "avatars_owner_write" ON storage.objects;
CREATE POLICY "avatars_owner_write"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'avatars' AND lower(split_part(name, '/', 1)) = auth.uid()::text);

DROP POLICY IF EXISTS "avatars_owner_update" ON storage.objects;
CREATE POLICY "avatars_owner_update"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'avatars' AND lower(split_part(name, '/', 1)) = auth.uid()::text)
WITH CHECK (bucket_id = 'avatars' AND lower(split_part(name, '/', 1)) = auth.uid()::text);

DROP POLICY IF EXISTS "avatars_owner_delete" ON storage.objects;
CREATE POLICY "avatars_owner_delete"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'avatars' AND lower(split_part(name, '/', 1)) = auth.uid()::text);

-- organizer-photos' own policies (migration 090/092) key off
-- `organizers.id` (a plain `text` primary key, never built from a Swift/JS
-- UUID type on either client) via an EXISTS join, and `owner_id`/`user_id`
-- are compared as genuine `uuid` type values (Postgres uuid equality is
-- value-based, not textual, so case can't affect it there) — traced
-- separately, per this ticket's own "do not assume one RLS fix covers both
-- buckets" instruction, and NOT reproducing this same bug. Left untouched.
