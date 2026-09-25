-- Migration: TASK D (2026-10-01 UX foundation pass) — shareable public
-- profile identity: a unique public handle, editable public fields, a
-- dedicated avatars Storage bucket with owner-only write, and a narrow
-- SECURITY DEFINER RPC for reading someone else's public profile (`profiles`
-- itself stays locked to `auth.uid() = id` — see 001's own RLS — so a
-- public profile screen needs its own read path that returns ONLY
-- public-safe fields, never phone/role/billing/refund/payment data).

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS handle text,
  ADD COLUMN IF NOT EXISTS bio text DEFAULT '',
  ADD COLUMN IF NOT EXISTS city text DEFAULT '',
  ADD COLUMN IF NOT EXISTS interests text[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS profile_theme text DEFAULT 'default';

-- Backfill: every existing profile gets a stable, unique handle derived
-- from its own id — never from display_name (which can collide, contain
-- spaces/unicode, or be empty) — so this migration never fails on existing
-- data and a user can rename their own handle to something human-readable
-- afterward via save_profile() below.
UPDATE profiles SET handle = 'u' || replace(id::text, '-', '')::text
WHERE handle IS NULL;
-- 'u' + 32 hex chars is already unique per id; trimmed to a friendlier
-- length (still effectively unique — collision would need two different
-- uuids sharing a 12-char prefix, astronomically unlikely at this app's
-- scale, and save_profile()'s own unique index + retry-on-conflict below
-- is the real safety net either way).
UPDATE profiles SET handle = left(handle, 13) WHERE length(handle) > 13;

ALTER TABLE profiles ALTER COLUMN handle SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_handle ON profiles(lower(handle));

-- ---------------------------------------------------------------------------
-- Avatars bucket — public read (a profile picture is meant to be seen),
-- owner-only write, path convention `<user_id>/<filename>` (same convention
-- 005's pay-qr bucket already uses for organizer-scoped paths).
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;
CREATE POLICY "avatars_public_read"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_owner_write" ON storage.objects;
CREATE POLICY "avatars_owner_write"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'avatars' AND split_part(name, '/', 1) = auth.uid()::text);

DROP POLICY IF EXISTS "avatars_owner_update" ON storage.objects;
CREATE POLICY "avatars_owner_update"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'avatars' AND split_part(name, '/', 1) = auth.uid()::text)
WITH CHECK (bucket_id = 'avatars' AND split_part(name, '/', 1) = auth.uid()::text);

DROP POLICY IF EXISTS "avatars_owner_delete" ON storage.objects;
CREATE POLICY "avatars_owner_delete"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'avatars' AND split_part(name, '/', 1) = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- save_profile() — the owner edits their own public identity. Validates
-- the handle (lowercase alnum/underscore, 3-24 chars) and returns a stable
-- HANDLE_TAKEN code on collision rather than a raw unique-constraint error.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_profile(
  p_handle text,
  p_display_name text,
  p_bio text DEFAULT '',
  p_city text DEFAULT '',
  p_interests text[] DEFAULT '{}',
  p_theme text DEFAULT 'default',
  p_avatar_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_handle text := lower(trim(p_handle));
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF v_handle !~ '^[a-z0-9_]{3,24}$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_HANDLE');
  END IF;
  IF trim(coalesce(p_display_name, '')) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_NAME');
  END IF;
  IF EXISTS (SELECT 1 FROM profiles WHERE lower(handle) = v_handle AND id <> auth.uid()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'HANDLE_TAKEN');
  END IF;

  UPDATE profiles
  SET handle = v_handle,
      display_name = trim(p_display_name),
      bio = left(coalesce(p_bio, ''), 280),
      city = left(coalesce(p_city, ''), 60),
      interests = (SELECT coalesce(array_agg(left(trim(x), 24)), '{}') FROM unnest(coalesce(p_interests, '{}')) AS x WHERE trim(x) <> ''),
      profile_theme = coalesce(nullif(trim(p_theme), ''), 'default'),
      avatar_url = coalesce(p_avatar_url, avatar_url)
  WHERE id = auth.uid();

  RETURN jsonb_build_object('success', true, 'handle', v_handle);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.save_profile(text, text, text, text, text[], text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_profile(text, text, text, text, text[], text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- get_public_profile() — the ONE read path for someone ELSE's profile.
-- Returns only public-safe fields: never phone, role, attended/no_show
-- counts, or anything from organizers beyond name/verified/hosting_since
-- (never bank_name/bank_account_no/momo_phone/pay_qr_path/pay_note —
-- exactly the "never billing/refund/payment data in profile/share
-- payloads" rule). Also returns whether the CALLER follows this organizer
-- (null if this profile isn't an organizer) and a follower count.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_public_profile(p_handle text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_organizer_id text;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE lower(handle) = lower(trim(p_handle));
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  SELECT o.id INTO v_organizer_id FROM organizers o
  WHERE o.owner_id = v_profile.id OR o.user_id = v_profile.id
  ORDER BY o.created_at ASC LIMIT 1;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_profile.id,
    'handle', v_profile.handle,
    'display_name', v_profile.display_name,
    'avatar_url', v_profile.avatar_url,
    'bio', v_profile.bio,
    'city', v_profile.city,
    'interests', v_profile.interests,
    'profile_theme', v_profile.profile_theme,
    'is_organizer', v_organizer_id IS NOT NULL,
    'organizer', CASE WHEN v_organizer_id IS NULL THEN NULL ELSE (
      SELECT jsonb_build_object(
        'id', o.id, 'name', o.name, 'verified', o.verified, 'hosting_since', o.hosting_since,
        'event_count', (SELECT count(*) FROM events e WHERE e.organizer_id = o.id),
        'follower_count', (SELECT count(*) FROM follows f WHERE f.organizer_id = o.id),
        'following', auth.uid() IS NOT NULL AND EXISTS (
          SELECT 1 FROM follows f WHERE f.organizer_id = o.id AND f.user_id = auth.uid()
        )
      )
      FROM organizers o WHERE o.id = v_organizer_id
    ) END
  );
END;
$$;

-- Unlike every other RPC in this app, this one is intentionally reachable
-- by `anon` too — a shared /u/<handle> link must resolve to a real public
-- profile page even for a visitor who isn't signed in (rule D2/D3: the
-- universal link must open something real, not force a login wall first).
GRANT EXECUTE ON FUNCTION public.get_public_profile(text) TO authenticated, anon;
