-- Migration: "Share survey to Story" + public (non-follower) discovery of
-- published survey stories (Slice D of .claude/notes/21-invite-only-events-
-- and-surveys.md — "not started" before this pass).
--
-- Same smallest-compatible-extension approach migration 068 already used for
-- event_share: a new `kind = 'survey_share'` + a nullable `survey_id` on the
-- existing `stories` table, not a parallel table. An event_share story is
-- visible to the SAME audience as every other story (author/co-owned
-- organizer/follower, migration 066's `stories_select_active_permitted`) —
-- a survey_share story is deliberately NOT: the whole point of this ticket
-- is that a published survey must be discoverable by non-followers too, so
-- it needs its OWN, additive RLS policy rather than loosening the existing
-- one (which must keep gating ordinary photo/video stories to followers,
-- unchanged, per the ticket's own "keep Following stories unchanged" rule).

ALTER TABLE stories ADD COLUMN IF NOT EXISTS survey_id uuid REFERENCES surveys(id) ON DELETE CASCADE;
DO $$ BEGIN
  ALTER TABLE stories DROP CONSTRAINT IF EXISTS stories_kind_check;
  ALTER TABLE stories ADD CONSTRAINT stories_kind_check CHECK (kind IN ('media', 'event_share', 'survey_share'));
END $$;

-- Additive SELECT policy: a survey_share story is visible to ANY
-- authenticated user as long as the survey it points at was ever actually
-- published (status <> 'draft' — mirrors get_survey_public's own "a draft
-- is host-only" rule, so a draft can never leak via a story even if one
-- somehow got created for it). Deliberately NOT restricted to 'active' only
-- — a survey can close while its story still has real hours left on its own
-- 24h lifetime ("preserve normal story lifetime separately from survey
-- lifetime"), and the card itself shows the TRUE current status (via
-- get_survey_card below, read live, never trusted from this row) rather
-- than disappearing or silently staying respondable. Deleting the survey
-- removes the story outright (ON DELETE CASCADE above) — no stale-but-still
-- -joinable row can ever exist.
DROP POLICY IF EXISTS "stories_select_survey_share_public" ON stories;
CREATE POLICY "stories_select_survey_share_public" ON stories FOR SELECT TO authenticated USING (
  kind = 'survey_share'
  AND EXISTS (SELECT 1 FROM surveys sv WHERE sv.id = stories.survey_id AND sv.status <> 'draft')
);

-- Ownership + "must actually be published" enforced server-side, same
-- pattern as create_event_share_story (068) — a client-passed survey_id is
-- never trusted on its own, and a draft can never be shared as a story
-- (task 4's own "require explicit Publish" + "validate owner permission and
-- public survey audience at publication" rules).
CREATE OR REPLACE FUNCTION create_survey_share_story(p_survey_id uuid)
RETURNS stories
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_survey surveys%ROWTYPE;
  v_uid uuid := auth.uid();
  v_story stories;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_SIGNED_IN';
  END IF;

  SELECT * INTO v_survey FROM surveys WHERE id = p_survey_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SURVEY_NOT_FOUND';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM organizers o WHERE o.id = v_survey.organizer_id AND (o.owner_id = v_uid OR o.user_id = v_uid)
  ) THEN
    RAISE EXCEPTION 'NOT_ORGANIZER_OWNER';
  END IF;

  IF v_survey.status <> 'active' THEN
    RAISE EXCEPTION 'SURVEY_NOT_ACTIVE';
  END IF;

  INSERT INTO stories (organizer_id, author_id, media_path, media_type, kind, survey_id)
  VALUES (v_survey.organizer_id, v_uid, '', 'application/x-banbe-survey-share', 'survey_share', p_survey_id)
  RETURNING * INTO v_story;

  RETURN v_story;
END;
$$;
REVOKE ALL ON FUNCTION create_survey_share_story(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_survey_share_story(uuid) TO authenticated;

-- A survey-story card needs the same safe, allowlisted fields
-- get_survey_public() already returns (title/host_name/closes_at/status/
-- public_id — enough to render the card and route "Answer Survey" into the
-- existing SurveyPublic flow via its public_id) but keyed by the story's
-- own `survey_id`, not a public_id a story row doesn't store. Deliberately
-- a SEPARATE function from get_survey_public rather than widening that
-- one's signature — this one is authenticated-only (the story viewer
-- already requires sign-in; it is never reachable signed-out the way the
-- browser route is) and intentionally does NOT special-case a draft for
-- its own host (get_survey_public's preview behavior, migration 116) —
-- a draft survey can never have a story row at all (enforced above), so
-- that branch does not apply here.
CREATE OR REPLACE FUNCTION get_survey_card(p_survey_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_survey surveys%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_effective_status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_survey FROM surveys WHERE id = p_survey_id;
  IF NOT FOUND OR v_survey.status = 'draft' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  v_effective_status := CASE
    WHEN v_survey.status IN ('closed', 'archived') THEN 'closed'
    WHEN v_survey.closes_at IS NOT NULL AND v_survey.closes_at <= now() THEN 'closed'
    WHEN v_survey.opens_at IS NOT NULL AND v_survey.opens_at > now() THEN 'not_open_yet'
    ELSE 'active'
  END;

  SELECT * INTO v_org FROM organizers WHERE id = v_survey.organizer_id;

  RETURN jsonb_build_object(
    'success', true,
    'survey_id', v_survey.id,
    'public_id', v_survey.public_id,
    'title', v_survey.title,
    'description', v_survey.description,
    'host_name', COALESCE(v_org.name, ''),
    'closes_at', v_survey.closes_at,
    'status', v_effective_status
  );
END;
$$;
REVOKE ALL ON FUNCTION get_survey_card(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_survey_card(uuid) TO authenticated;
