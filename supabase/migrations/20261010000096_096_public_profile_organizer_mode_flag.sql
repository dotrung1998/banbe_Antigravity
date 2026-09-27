-- 096: Account extension (2026-09-27, Stage 1) — "organizer mode OFF means
-- host UI is OFF" includes the personal public profile's own "Founder tổ
-- chức: <name>" line, for ANY visitor, not just the owner viewing their
-- own page — get_public_profile() had no way to express that at all.
-- There is no separate `organizer_mode` boolean column (migration 016's
-- own comment: "organizer mode is a self-service toggle," implemented as
-- `profiles.role` itself, not a second flag) — set_organizer_mode() writes
-- role='organizer'/'participant' directly, so `role = 'organizer'` (or the
-- 'admin' role, which the client's own organizerMode derivation already
-- treats as "on") IS the real organizer_mode value. Everything else about
-- get_public_profile() (091's published-event-only stats) is untouched.

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
    ) END
  );
END;
$$;
