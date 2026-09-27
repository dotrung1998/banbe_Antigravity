-- 095 — a NEW, organizer-id-keyed public profile RPC, separate from
-- get_public_profile's handle-keyed personal(+merged-organizer) page.
--
-- Nav/discovery pass (2026-09-27, personal-vs-organizer hierarchy) — a
-- shareable organizer link (web: /org/<organizer_id>, iOS universal link
-- .../org/<organizer_id>) must resolve to a real, standalone organizer
-- page WITHOUT requiring the owner's personal handle at all (today's
-- get_public_profile can only be reached that way) and without exposing
-- any of the owner's personal profile fields (handle, bio, interests,
-- theme) on what's supposed to be a purely organizational page.
--
-- Field-for-field mirrors get_public_profile's own organizer sub-object
-- (migration 091) so the two can never numerically disagree — same
-- published-events-only rule (`status IN ('live','ended')`), same
-- hosting_since_year derivation (earliest real published event's
-- starts_at, never the free-text organizers.hosting_since column, which
-- nothing ever actually sets).
CREATE OR REPLACE FUNCTION public.get_organizer_profile(p_organizer_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org organizers%ROWTYPE;
BEGIN
  SELECT * INTO v_org FROM organizers WHERE id = p_organizer_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_org.id,
    'name', v_org.name,
    'about', v_org.about,
    'avatar_path', v_org.avatar_path,
    'verified', v_org.verified,
    'event_count', (
      SELECT count(*) FROM events e
      WHERE e.organizer_id = v_org.id AND e.status IN ('live', 'ended')
    ),
    'hosting_since_year', (
      SELECT EXTRACT(YEAR FROM min(e.starts_at))::int FROM events e
      WHERE e.organizer_id = v_org.id AND e.status IN ('live', 'ended') AND e.starts_at IS NOT NULL
    ),
    -- `follows` is locked to `auth.uid() = user_id` (migration 003) — the
    -- real reason this RPC needs SECURITY DEFINER at all (organizers and
    -- published events are already publicly readable directly).
    'follower_count', (SELECT count(*) FROM follows f WHERE f.organizer_id = v_org.id),
    'following', auth.uid() IS NOT NULL AND EXISTS (
      SELECT 1 FROM follows f WHERE f.organizer_id = v_org.id AND f.user_id = auth.uid()
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_organizer_profile(text) FROM PUBLIC;
-- Intentionally reachable by `anon` too, same as get_public_profile — a
-- shared /org/<id> link must resolve to a real page for a signed-out
-- visitor, not force a login wall first.
GRANT EXECUTE ON FUNCTION public.get_organizer_profile(text) TO authenticated, anon;
