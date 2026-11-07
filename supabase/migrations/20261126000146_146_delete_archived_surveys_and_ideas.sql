-- Migration: permanently delete ARCHIVED surveys and USED (archived) ideas.
--
-- delete_survey() (116) is deliberately draft-only. Archived is the
-- host's "I'm done with this" bucket, so it gets its own delete, still
-- restricted to status = 'archived' (an active/closed survey can never be
-- deleted this way) and to the survey's own host. Deleting a survey
-- cascades to its responses, suggested/used ideas and any survey-share
-- stories (all ON DELETE CASCADE). Irreversible — the clients confirm.

CREATE OR REPLACE FUNCTION public.delete_archived_surveys(p_survey_ids uuid[])
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  DELETE FROM surveys s
  WHERE s.id = ANY (p_survey_ids) AND s.status = 'archived' AND EXISTS (
    SELECT 1 FROM organizers o WHERE o.id = s.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.delete_archived_surveys(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_archived_surveys(uuid[]) TO authenticated;

-- Only ideas already moved to Archived ('used') can be deleted here; a
-- still-suggested/dismissed idea is managed with Dismiss/Restore instead.
CREATE OR REPLACE FUNCTION public.delete_survey_candidates(p_candidate_ids uuid[])
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  DELETE FROM survey_event_candidates c
  WHERE c.id = ANY (p_candidate_ids) AND c.status = 'used' AND EXISTS (
    SELECT 1 FROM surveys s JOIN organizers o ON o.id = s.organizer_id
    WHERE s.id = c.survey_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.delete_survey_candidates(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_survey_candidates(uuid[]) TO authenticated;
