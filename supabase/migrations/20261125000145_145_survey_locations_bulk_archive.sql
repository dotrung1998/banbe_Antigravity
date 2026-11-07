-- Migration: structured survey locations, bulk dismiss/archive, un-archive.
--
-- * Survey location options can now be real addresses picked with the same
--   search Create Event uses ({id, label, address_line, district, city,
--   postal_code, country_code, state_province, neighborhood, lat, lng}).
--   Candidates snapshot that structure in location_data so "Use This Idea"
--   can fill Create Event's confirmed address directly. Free-text location
--   options still work (location_data is just '{}').
-- * set_survey_candidates_status: dismiss / restore / archive many drafts
--   in one call (dismiss selected, dismiss all).
-- * archive_surveys: move many CLOSED surveys to Archived in one call;
--   unarchive_survey moves one back to Closed, so archiving is never a
--   one-way door.

ALTER TABLE survey_event_candidates
  ADD COLUMN IF NOT EXISTS location_data jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION public._generate_survey_candidates(p_survey_id uuid)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_survey surveys%ROWTYPE;
  v_total int;
  v_inserted int;
BEGIN
  SELECT * INTO v_survey FROM surveys WHERE id = p_survey_id;
  IF NOT FOUND THEN RETURN 0; END IF;
  SELECT count(*) INTO v_total FROM survey_responses WHERE survey_id = p_survey_id;

  DELETE FROM survey_event_candidates WHERE survey_id = p_survey_id AND status = 'suggested';
  IF v_total = 0 THEN RETURN 0; END IF;

  WITH
  dates AS (
    SELECT d.value->>'id' AS id, COALESCE(d.value->>'label', '') AS label, d.ord,
           COALESCE(d.value->>'date', '') AS dv, COALESCE(d.value->>'time', '') AS tv
    FROM jsonb_array_elements(COALESCE(v_survey.config->'date_options', '[]'::jsonb)) WITH ORDINALITY AS d(value, ord)
    UNION ALL SELECT '', '', 0, '', ''
    WHERE jsonb_array_length(COALESCE(v_survey.config->'date_options', '[]'::jsonb)) = 0
  ),
  locs AS (
    SELECT l.value->>'id' AS id, COALESCE(l.value->>'label', '') AS label, l.ord, l.value AS lv
    FROM jsonb_array_elements(COALESCE(v_survey.config->'location_options', '[]'::jsonb)) WITH ORDINALITY AS l(value, ord)
    UNION ALL SELECT '', '', 0, '{}'::jsonb
    WHERE jsonb_array_length(COALESCE(v_survey.config->'location_options', '[]'::jsonb)) = 0
  ),
  pairs AS (
    SELECT d.id AS d_id, d.label AS d_label, d.ord AS d_ord, d.dv AS d_dv, d.tv AS d_tv, l.id AS l_id, l.label AS l_label, l.ord AS l_ord, l.lv AS l_lv
    FROM dates d CROSS JOIN locs l
  ),
  support AS (
    SELECT p.d_id, p.l_id, r.id AS response_id, r.group_size, r.budget_option, r.activities,
           r.contact_consent, COALESCE(r.interest_level, 3) AS interest
    FROM pairs p
    JOIN survey_responses r ON r.survey_id = p_survey_id
      AND (p.d_id = '' OR p.d_id = ANY (r.date_options))
      AND (p.l_id = '' OR p.l_id = ANY (r.location_options))
  ),
  agg AS (
    SELECT s.d_id, s.l_id,
           count(*)::int AS supporters,
           count(*) FILTER (WHERE s.contact_consent)::int AS consent,
           (count(*) * 10 + sum(s.interest))::numeric AS score,
           (percentile_disc(0.5) WITHIN GROUP (ORDER BY s.group_size))::int AS median_size
    FROM support s GROUP BY s.d_id, s.l_id
  ),
  budget_pick AS (
    SELECT DISTINCT ON (s.d_id, s.l_id) s.d_id, s.l_id, s.budget_option AS bid
    FROM support s
    LEFT JOIN LATERAL (
      SELECT b.ord FROM jsonb_array_elements(COALESCE(v_survey.config->'budget_options', '[]'::jsonb)) WITH ORDINALITY AS b(value, ord)
      WHERE b.value->>'id' = s.budget_option LIMIT 1
    ) bo ON true
    WHERE s.budget_option IS NOT NULL
    GROUP BY s.d_id, s.l_id, s.budget_option, bo.ord
    ORDER BY s.d_id, s.l_id, count(*) DESC, bo.ord NULLS LAST
  ),
  act_counts AS (
    SELECT s.d_id, s.l_id, a.aid, count(*) AS n
    FROM support s CROSS JOIN LATERAL unnest(s.activities) AS a(aid)
    GROUP BY s.d_id, s.l_id, a.aid
  ),
  act_pick AS (
    SELECT ranked.d_id, ranked.l_id, array_agg(ranked.label ORDER BY ranked.n DESC, ranked.ord) AS labels
    FROM (
      SELECT c.d_id, c.l_id, c.n, COALESCE(o.value->>'label', c.aid) AS label, COALESCE(o.ord, 9999) AS ord,
             row_number() OVER (PARTITION BY c.d_id, c.l_id ORDER BY c.n DESC, COALESCE(o.ord, 9999)) AS rn
      FROM act_counts c
      LEFT JOIN LATERAL (
        SELECT x.value, x.ord FROM jsonb_array_elements(COALESCE(v_survey.config->'activity_options', '[]'::jsonb)) WITH ORDINALITY AS x(value, ord)
        WHERE x.value->>'id' = c.aid LIMIT 1
      ) o ON true
    ) ranked
    WHERE ranked.rn <= 3
    GROUP BY ranked.d_id, ranked.l_id
  ),
  top AS (
    SELECT p.*, a.supporters, a.consent, a.score, a.median_size,
           row_number() OVER (ORDER BY a.score DESC, a.supporters DESC, p.d_ord, p.l_ord) AS rnk
    FROM pairs p JOIN agg a ON a.d_id = p.d_id AND a.l_id = p.l_id
    WHERE NOT EXISTS (
      SELECT 1 FROM survey_event_candidates e
      WHERE e.survey_id = p_survey_id AND e.date_option_id = p.d_id AND e.location_option_id = p.l_id
    )
  )
  INSERT INTO survey_event_candidates (
    survey_id, rank, date_option_id, date_label, location_option_id, location_label,
    budget_label, activity_labels, date_value, time_value, location_data, supporter_count, response_total, consent_count,
    suggested_group_size, score
  )
  SELECT p_survey_id, t.rnk::int, t.d_id, t.d_label, t.l_id, t.l_label,
         COALESCE((SELECT b.value->>'label'
                   FROM jsonb_array_elements(COALESCE(v_survey.config->'budget_options', '[]'::jsonb)) AS b(value)
                   WHERE b.value->>'id' = bp.bid LIMIT 1), ''),
         COALESCE(ap.labels, '{}'), t.d_dv, t.d_tv, t.l_lv - 'id' - 'label', t.supporters, v_total, t.consent,
         COALESCE(t.median_size, t.supporters), t.score
  FROM top t
  LEFT JOIN budget_pick bp ON bp.d_id = t.d_id AND bp.l_id = t.l_id
  LEFT JOIN act_pick ap ON ap.d_id = t.d_id AND ap.l_id = t.l_id
  WHERE t.rnk <= 5;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted;
END;
$$;
REVOKE EXECUTE ON FUNCTION public._generate_survey_candidates(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.set_survey_candidates_status(p_candidate_ids uuid[], p_status text)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_status NOT IN ('suggested', 'dismissed', 'used') THEN RAISE EXCEPTION 'INVALID_STATUS'; END IF;
  UPDATE survey_event_candidates c SET status = p_status
  WHERE c.id = ANY (p_candidate_ids) AND EXISTS (
    SELECT 1 FROM surveys s JOIN organizers o ON o.id = s.organizer_id
    WHERE s.id = c.survey_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_survey_candidates_status(uuid[], text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_survey_candidates_status(uuid[], text) TO authenticated;

CREATE OR REPLACE FUNCTION public.archive_surveys(p_survey_ids uuid[])
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  UPDATE surveys s SET status = 'archived'
  WHERE s.id = ANY (p_survey_ids) AND s.status = 'closed' AND EXISTS (
    SELECT 1 FROM organizers o WHERE o.id = s.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.archive_surveys(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.archive_surveys(uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.unarchive_survey(p_survey_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  UPDATE surveys s SET status = 'closed'
  WHERE s.id = p_survey_id AND s.status = 'archived' AND EXISTS (
    SELECT 1 FROM organizers o WHERE o.id = s.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  );
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.unarchive_survey(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.unarchive_survey(uuid) TO authenticated;
