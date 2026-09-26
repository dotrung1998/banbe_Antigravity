-- 090: Stage D of the post-e661cfb "REAL event creation/discovery"
-- follow-up — the host tab's own rounded profile card (organizer avatar,
-- name, introduction — stored on `organizers`, never `profiles.display_
-- name`) and a real "notify followers once when the organizer's name
-- genuinely changes" path.
--
-- 1. organizers.avatar_path — a real photo field distinct from any goer
--    profile field.
-- 2. A dedicated, publicly-readable `organizer-photos` bucket, write
--    scoped to that organizer's own owner/user (never any other host's).
-- 3. update_organizer_profile RPC: owner/admin only, validates length,
--    is a genuine no-op on an unchanged name/intro/avatar (no wasted
--    write, no notification), and notifies followers exactly once per
--    REAL name change — never on an avatar/bio-only edit or a no-op
--    save. Dedup-on-retry falls out of the same "did the name actually
--    change from what's stored" check: calling this twice with the same
--    new name only notifies on the first call, since by the second call
--    the stored name already matches.

ALTER TABLE organizers ADD COLUMN IF NOT EXISTS avatar_path text NOT NULL DEFAULT '';

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('organizer-photos', 'organizer-photos', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "organizer_photos_public_read" ON storage.objects;
CREATE POLICY "organizer_photos_public_read"
ON storage.objects FOR SELECT
USING (bucket_id = 'organizer-photos');

-- Path convention: <organizer_id>/<filename> — write/update/delete is
-- scoped to THIS organizer's own owner/user, never any other host's
-- (unlike 087's event_photos_host_update/delete, which check only "owns
-- SOME organizer," not this specific one — a pre-existing gap, out of
-- scope for this migration, left as-is rather than silently widened
-- further here).
DROP POLICY IF EXISTS "organizer_photos_owner_write" ON storage.objects;
CREATE POLICY "organizer_photos_owner_write"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'organizer-photos' AND
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = split_part(name, '/', 1) AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);

DROP POLICY IF EXISTS "organizer_photos_owner_update" ON storage.objects;
CREATE POLICY "organizer_photos_owner_update"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'organizer-photos' AND
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = split_part(name, '/', 1) AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);

DROP POLICY IF EXISTS "organizer_photos_owner_delete" ON storage.objects;
CREATE POLICY "organizer_photos_owner_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'organizer-photos' AND
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = split_part(name, '/', 1) AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);

CREATE OR REPLACE FUNCTION public.update_organizer_profile(
  p_organizer_id text,
  p_name text,
  p_intro text DEFAULT NULL,
  p_avatar_path text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_org organizers%ROWTYPE;
  v_clean_name text := trim(COALESCE(p_name, ''));
  v_clean_intro text := trim(COALESCE(p_intro, ''));
  v_name_changed boolean;
  v_notified int := 0;
  r record;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF v_clean_name = '' OR length(v_clean_name) > 80 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_NAME');
  END IF;
  IF length(v_clean_intro) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_INTRO');
  END IF;

  SELECT * INTO v_org FROM organizers
    WHERE id = p_organizer_id AND (owner_id = auth.uid() OR user_id = auth.uid() OR public.is_platform_admin())
    FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ORGANIZER_NOT_FOUND');
  END IF;

  v_name_changed := v_org.name IS DISTINCT FROM v_clean_name AND v_org.name IS NOT NULL AND v_org.name <> '';

  -- Genuine no-op (same name, same intro, no new avatar) — no write, no
  -- notification, matching "never on a no-op save."
  IF v_org.name = v_clean_name AND COALESCE(v_org.about, '') = v_clean_intro
     AND (p_avatar_path IS NULL OR p_avatar_path = v_org.avatar_path) THEN
    RETURN jsonb_build_object('success', true, 'notified', 0);
  END IF;

  UPDATE organizers SET
    name = v_clean_name,
    about = v_clean_intro,
    bio = v_clean_intro,
    avatar_path = COALESCE(p_avatar_path, avatar_path)
  WHERE id = p_organizer_id;

  IF v_name_changed THEN
    FOR r IN SELECT user_id AS recipient_id FROM follows WHERE organizer_id = p_organizer_id
    LOOP
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (
        r.recipient_id,
        'organizer_renamed',
        'Một người tổ chức bạn theo dõi đã đổi tên',
        v_org.name || ' đã đổi tên thành ' || v_clean_name || '.',
        jsonb_build_object('organizer_id', p_organizer_id, 'old_name', v_org.name, 'new_name', v_clean_name)
      );
      v_notified := v_notified + 1;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('success', true, 'notified', v_notified);
END;
$$;

REVOKE ALL ON FUNCTION public.update_organizer_profile(text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_organizer_profile(text, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_organizer_profile(text, text, text, text) TO authenticated;
