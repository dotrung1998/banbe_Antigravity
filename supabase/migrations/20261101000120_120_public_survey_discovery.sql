-- Home survey-discovery pass — PUBLISHING an eligible public survey makes it
-- discoverable on Home; "Share To Story" becomes an optional, SEPARATE
-- publishing action again (it still creates a `stories` row for the story
-- viewer/ring, untouched by this migration). Before this, Home's own
-- discovery feed was built entirely by scanning `stories` for
-- `kind = 'survey_share'` rows (loadHomeStories(), both platforms) — a
-- real, confirmed bug: a published survey with no Share-To-Story action
-- (or an EXPIRED story — `stories.expires_at`, migration 066, prunes rows
-- after 24h) silently disappeared from discovery even while still fully
-- active and answerable via its direct link. This function reads `surveys`
-- directly instead, with the exact SAME "effective status" rule
-- `get_survey_public()` (migration 114) already uses, so "active" means the
-- same thing everywhere in this codebase.
--
-- Authenticated-only (Home's own survey-discovery section is never shown
-- signed out), SECURITY DEFINER (same reasoning as `get_survey_card`: an
-- ordinary signed-in, non-owner/non-follower viewer has no direct SELECT on
-- `surveys` at all per `surveys_select_host`, by design — this function is
-- the one allowlisted, read-only door into "what's publicly discoverable
-- right now"), returns ONLY the fields a discovery card needs — no
-- `config`/respondent data, no raw table exposed.
--
-- Keyset pagination (created_at, id) DESC, both passed as the next page's
-- cursor — stable and deterministic even when two surveys share the exact
-- same `created_at` (the `id` tie-breaker), unlike a plain OFFSET/prefix
-- LIMIT which can skip or duplicate rows across pages if new surveys are
-- published between calls. Fetches `p_limit + 1` to compute `has_more`
-- without a second COUNT query.
CREATE OR REPLACE FUNCTION public.get_public_survey_discovery(
  p_cursor_created_at timestamptz DEFAULT NULL,
  p_cursor_id uuid DEFAULT NULL,
  p_limit int DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit int := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_rows jsonb;
  v_has_more boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  WITH eligible AS (
    SELECT s.id, s.public_id, s.title, s.organizer_id, s.closes_at, s.created_at,
           o.name AS host_name, o.avatar_path AS host_avatar_path
    FROM surveys s
    JOIN organizers o ON o.id = s.organizer_id
    WHERE s.status NOT IN ('draft', 'closed', 'archived')
      AND (s.opens_at IS NULL OR s.opens_at <= now())
      AND (s.closes_at IS NULL OR s.closes_at > now())
      AND (
        p_cursor_created_at IS NULL
        OR s.created_at < p_cursor_created_at
        OR (s.created_at = p_cursor_created_at AND s.id < p_cursor_id)
      )
    ORDER BY s.created_at DESC, s.id DESC
    LIMIT v_limit + 1
  ),
  page AS (
    SELECT * FROM eligible ORDER BY created_at DESC, id DESC LIMIT v_limit
  )
  SELECT
    jsonb_agg(jsonb_build_object(
      'survey_id', p.id,
      'public_id', p.public_id,
      'title', p.title,
      'organizer_id', p.organizer_id,
      'host_name', COALESCE(p.host_name, ''),
      'host_avatar_path', p.host_avatar_path,
      'closes_at', p.closes_at,
      'created_at', p.created_at
    ) ORDER BY p.created_at DESC, p.id DESC),
    (SELECT count(*) > v_limit FROM eligible)
  INTO v_rows, v_has_more
  FROM page p;

  RETURN jsonb_build_object(
    'success', true,
    'surveys', COALESCE(v_rows, '[]'::jsonb),
    'has_more', COALESCE(v_has_more, false)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_survey_discovery(timestamptz, uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_survey_discovery(timestamptz, uuid, int) TO authenticated;
