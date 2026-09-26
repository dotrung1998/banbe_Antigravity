-- 091: iPhone fix pass follow-up to migration 090's organizer profile
-- work — get_public_profile()'s own `event_count` counted EVERY row for
-- that organizer regardless of status (draft/review/cancelled included),
-- and had no honest "hosting since" at all (`organizers.hosting_since` is
-- a free-text column nothing ever actually sets — always blank). Both
-- fixed here: `event_count` now only counts events this organizer has
-- actually PUBLISHED (status IN ('live','ended') — excludes draft/review/
-- cancelled, consistent with "published" everywhere else in this schema),
-- and `hosting_since_year` is derived from the earliest such event's
-- starts_at, NULL (never a fabricated year) when there isn't one yet.

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
