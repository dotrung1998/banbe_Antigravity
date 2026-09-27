-- 102: Organizer Team pass (2026-09-27), Stage 3 — a separate long-form
-- "Giới thiệu" (distinct from, and never overwriting, the existing short
-- bio: profiles.bio stays 280 chars via save_profile; organizers.about/
-- bio stay whatever update_organizer_profile already enforces) plus
-- optional social links, for both personal and organizer profiles.
--
-- Social links are validated SERVER-SIDE (sanitize_social_links below),
-- not just hidden by the edit form's UI: only https://, a well-formed
-- host, at most 8 links, and — for a handful of named platforms — a
-- matching real host (an "instagram" link must actually point at
-- instagram.com). javascript:/data:/plain http:// and anything malformed
-- is rejected outright, never stored, never rendered.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS intro_long text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS social_links jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE organizers
  ADD COLUMN IF NOT EXISTS intro_long text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS social_links jsonb NOT NULL DEFAULT '[]'::jsonb;

CREATE OR REPLACE FUNCTION public.sanitize_social_links(p_links jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_result jsonb := '[]'::jsonb;
  v_item jsonb;
  v_platform text;
  v_url text;
  v_host text;
BEGIN
  IF p_links IS NULL THEN RETURN '[]'::jsonb; END IF;
  IF jsonb_typeof(p_links) <> 'array' THEN RETURN NULL; END IF;
  IF jsonb_array_length(p_links) > 8 THEN RETURN NULL; END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_links) LOOP
    IF jsonb_typeof(v_item) <> 'object' THEN RETURN NULL; END IF;
    v_platform := lower(trim(coalesce(v_item->>'platform', '')));
    v_url := trim(coalesce(v_item->>'url', ''));
    IF v_platform = '' OR v_url = '' THEN RETURN NULL; END IF;
    IF length(v_platform) > 20 OR length(v_url) > 300 THEN RETURN NULL; END IF;
    -- https:// only, a real host, optional path/query — rejects
    -- javascript:, data:, plain http://, and anything malformed.
    IF v_url !~* '^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}(/.*)?(\?.*)?$' THEN RETURN NULL; END IF;
    v_host := lower(substring(v_url from '^https://([^/]+)'));

    IF v_platform = 'instagram' AND v_host !~ 'instagram\.com$' THEN RETURN NULL; END IF;
    IF v_platform = 'facebook' AND v_host !~ 'facebook\.com$' THEN RETURN NULL; END IF;
    IF v_platform = 'tiktok' AND v_host !~ 'tiktok\.com$' THEN RETURN NULL; END IF;
    IF v_platform IN ('twitter', 'x') AND v_host !~ '(twitter\.com|x\.com)$' THEN RETURN NULL; END IF;
    IF v_platform = 'youtube' AND v_host !~ 'youtube\.com$' THEN RETURN NULL; END IF;

    v_result := v_result || jsonb_build_array(jsonb_build_object('platform', v_platform, 'url', v_url));
  END LOOP;
  RETURN v_result;
END;
$$;

-- ---------------------------------------------------------------------------
-- save_profile() — adds p_intro_long/p_social_links. Signature changes
-- (new params), so the OLD 7-arg overload is dropped explicitly rather
-- than left behind as a second, confusing overload.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.save_profile(text, text, text, text, text[], text, text);

CREATE OR REPLACE FUNCTION public.save_profile(
  p_handle text,
  p_display_name text,
  p_bio text DEFAULT '',
  p_city text DEFAULT '',
  p_interests text[] DEFAULT '{}',
  p_theme text DEFAULT 'default',
  p_avatar_url text DEFAULT NULL,
  p_intro_long text DEFAULT NULL,
  p_social_links jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_handle text := lower(trim(p_handle));
  v_links jsonb;
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
  IF length(coalesce(p_intro_long, '')) > 4000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INTRO_TOO_LONG');
  END IF;
  v_links := public.sanitize_social_links(p_social_links);
  IF v_links IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_LINKS');
  END IF;

  UPDATE profiles
  SET handle = v_handle,
      display_name = trim(p_display_name),
      bio = left(coalesce(p_bio, ''), 280),
      city = left(coalesce(p_city, ''), 60),
      interests = (SELECT coalesce(array_agg(left(trim(x), 24)), '{}') FROM unnest(coalesce(p_interests, '{}')) AS x WHERE trim(x) <> ''),
      profile_theme = coalesce(nullif(trim(p_theme), ''), 'default'),
      avatar_url = coalesce(p_avatar_url, avatar_url),
      intro_long = CASE WHEN p_intro_long IS NULL THEN intro_long ELSE left(p_intro_long, 4000) END,
      social_links = CASE WHEN p_social_links IS NULL THEN social_links ELSE v_links END
  WHERE id = auth.uid();

  RETURN jsonb_build_object('success', true, 'handle', v_handle);
END;
$$;

REVOKE ALL ON FUNCTION public.save_profile(text, text, text, text, text[], text, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_profile(text, text, text, text, text[], text, text, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_profile(text, text, text, text, text[], text, text, text, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- update_organizer_profile() — same addition. Old 4-arg overload dropped.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.update_organizer_profile(text, text, text, text);

CREATE OR REPLACE FUNCTION public.update_organizer_profile(
  p_organizer_id text,
  p_name text,
  p_intro text DEFAULT NULL,
  p_avatar_path text DEFAULT NULL,
  p_intro_long text DEFAULT NULL,
  p_social_links jsonb DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_org organizers%ROWTYPE;
  v_clean_name text := trim(COALESCE(p_name, ''));
  v_clean_intro text := trim(COALESCE(p_intro, ''));
  v_links jsonb;
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
  IF length(coalesce(p_intro_long, '')) > 4000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INTRO_TOO_LONG');
  END IF;
  v_links := public.sanitize_social_links(p_social_links);
  IF v_links IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_LINKS');
  END IF;

  SELECT * INTO v_org FROM organizers
    WHERE id = p_organizer_id AND (owner_id = auth.uid() OR user_id = auth.uid() OR public.is_platform_admin())
    FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ORGANIZER_NOT_FOUND');
  END IF;

  v_name_changed := v_org.name IS DISTINCT FROM v_clean_name AND v_org.name IS NOT NULL AND v_org.name <> '';

  -- Genuine no-op — no write, no notification, matching "never on a
  -- no-op save." Long intro/social links are deliberately NOT part of
  -- this no-op check (bio/avatar-only edits already don't notify below;
  -- this just controls whether the row is written at all).
  IF v_org.name = v_clean_name AND COALESCE(v_org.about, '') = v_clean_intro
     AND (p_avatar_path IS NULL OR p_avatar_path = v_org.avatar_path)
     AND (p_intro_long IS NULL OR p_intro_long = v_org.intro_long)
     AND (p_social_links IS NULL OR v_links = v_org.social_links) THEN
    RETURN jsonb_build_object('success', true, 'notified', 0);
  END IF;

  UPDATE organizers SET
    name = v_clean_name,
    about = v_clean_intro,
    bio = v_clean_intro,
    avatar_path = COALESCE(p_avatar_path, avatar_path),
    intro_long = CASE WHEN p_intro_long IS NULL THEN intro_long ELSE left(p_intro_long, 4000) END,
    social_links = CASE WHEN p_social_links IS NULL THEN social_links ELSE v_links END
  WHERE id = p_organizer_id;

  -- Unchanged: only a real NAME change notifies followers — bio/avatar/
  -- intro/link-only edits never do (this ticket's own "don't notify
  -- followers for bio/avatar-only edits" rule, now explicitly extended
  -- to intro_long/social_links too).
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

REVOKE ALL ON FUNCTION public.update_organizer_profile(text, text, text, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_organizer_profile(text, text, text, text, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_organizer_profile(text, text, text, text, text, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- get_public_profile() / get_organizer_profile() — expose the new fields
-- read-only. Everything else about each function (100/095) unchanged.
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
    'intro_long', v_profile.intro_long,
    'social_links', v_profile.social_links,
    'city', v_profile.city,
    'interests', v_profile.interests,
    'profile_theme', v_profile.profile_theme,
    'is_organizer', v_organizer_id IS NOT NULL,
    'organizer_mode', v_profile.role IN ('organizer', 'admin'),
    'organizer', CASE WHEN v_organizer_id IS NULL THEN NULL ELSE (
      SELECT jsonb_build_object(
        'id', o.id, 'name', o.name, 'verified', o.verified,
        'event_count', (
          SELECT count(*) FROM events e
          WHERE e.organizer_id = o.id AND e.status IN ('live', 'ended')
        ),
        'hosting_since_year', (
          SELECT EXTRACT(YEAR FROM min(e.starts_at))::int FROM events e
          WHERE e.organizer_id = o.id AND e.status IN ('live', 'ended') AND e.starts_at IS NOT NULL
        ),
        'follower_count', (SELECT count(*) FROM follows f WHERE f.organizer_id = o.id),
        'following', auth.uid() IS NOT NULL AND EXISTS (
          SELECT 1 FROM follows f WHERE f.organizer_id = o.id AND f.user_id = auth.uid()
        )
      )
      FROM organizers o WHERE o.id = v_organizer_id
    ) END,
    'team_badges', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'organizer_id', om.organizer_id, 'organizer_name', o.name, 'public_role', om.public_role
      )), '[]'::jsonb)
      FROM organizer_members om JOIN organizers o ON o.id = om.organizer_id
      WHERE om.user_id = v_profile.id AND om.status = 'accepted' AND om.public_visible = true
    ),
    'credited_events', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'event_id', e.id, 'event_name', e.name, 'organizer_id', ec.organizer_id, 'organizer_name', o.name
      ) ORDER BY e.starts_at DESC NULLS LAST), '[]'::jsonb)
      FROM event_credits ec
      JOIN events e ON e.id = ec.event_id
      JOIN organizers o ON o.id = ec.organizer_id
      JOIN organizer_members om ON om.organizer_id = ec.organizer_id AND om.user_id = ec.user_id
      WHERE ec.user_id = v_profile.id AND ec.status = 'accepted'
        AND om.status = 'accepted' AND om.public_visible = true
        AND e.status IN ('live', 'ended')
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_organizer_profile(p_organizer_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_org organizers%ROWTYPE;
BEGIN
  SELECT * INTO v_org FROM organizers WHERE id = p_organizer_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND'); END IF;
  RETURN jsonb_build_object(
    'success', true, 'id', v_org.id, 'name', v_org.name, 'about', v_org.about,
    'intro_long', v_org.intro_long, 'social_links', v_org.social_links,
    'avatar_path', v_org.avatar_path, 'verified', v_org.verified,
    'event_count', (SELECT count(*) FROM events e WHERE e.organizer_id = v_org.id AND e.status IN ('live','ended')),
    'hosting_since_year', (SELECT EXTRACT(YEAR FROM min(e.starts_at))::int FROM events e WHERE e.organizer_id = v_org.id AND e.status IN ('live','ended') AND e.starts_at IS NOT NULL),
    'follower_count', (SELECT count(*) FROM follows f WHERE f.organizer_id = v_org.id),
    'following', auth.uid() IS NOT NULL AND EXISTS (SELECT 1 FROM follows f WHERE f.organizer_id = v_org.id AND f.user_id = auth.uid())
  );
END; $$;
