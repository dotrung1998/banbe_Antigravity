-- Migration: two real bugs found testing on a physical iPhone.
--
-- 1. get_survey_public() unconditionally returned NOT_FOUND for a draft,
--    with no exception for the survey's own host — so the host's own
--    "Preview" button (both web and iOS call this same RPC) showed
--    "this survey couldn't be found" for every draft, the exact reported
--    symptom. Fixed: the host (or admin) may now preview their own draft;
--    a stranger still gets the identical NOT_FOUND a draft is supposed to
--    give. Effective status for a host-previewed draft is reported as
--    'draft' (not 'active'/'closed'/'not_open_yet', none of which are
--    true yet) so the UI can show an honest "not published" state rather
--    than a fabricated one.
-- 2. No way to delete a draft survey that was created by mistake or never
--    published — create_survey has no undo. Added delete_survey(),
--    intentionally restricted to status = 'draft' only: a published
--    survey (active/closed/archived) may already have real respondent
--    answers, and this pass's whole privacy model is "never silently
--    destroy a respondent's data" — archive_survey() is the correct
--    action once a survey has ever been live, not delete.

CREATE OR REPLACE FUNCTION public.get_survey_public(p_public_id text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_survey surveys%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_effective_status text;
  v_is_host boolean;
BEGIN
  SELECT * INTO v_survey FROM surveys WHERE public_id = p_public_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  v_is_host := auth.uid() IS NOT NULL AND (
    EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_survey.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
    OR public.is_platform_admin()
  );

  -- A draft is host-only; a stranger gets the same NOT_FOUND a truly-
  -- missing link would (nothing dishonest about that — a draft link was
  -- never meant to be reachable by anyone else yet). The host/admin CAN
  -- see their own draft, so "Preview" works before publishing.
  IF v_survey.status = 'draft' AND NOT v_is_host THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  v_effective_status := CASE
    WHEN v_survey.status = 'draft' THEN 'draft'
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
    'timezone', v_survey.timezone,
    'opens_at', v_survey.opens_at,
    'closes_at', v_survey.closes_at,
    'status', v_effective_status,
    'config', v_survey.config,
    'config_version', v_survey.config_version
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_survey_public(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_survey_public(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_survey(p_survey_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_survey surveys%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_survey FROM surveys WHERE id = p_survey_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SURVEY_NOT_FOUND'; END IF;
  IF NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_survey.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_survey.status != 'draft' THEN RAISE EXCEPTION 'ONLY_DRAFT_CAN_BE_DELETED'; END IF;

  DELETE FROM surveys WHERE id = p_survey_id;
  RETURN true;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.delete_survey(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_survey(uuid) TO authenticated;
