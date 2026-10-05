-- Migration: Survey -> suggested event candidates (Slice C).
--
-- Until now "Suggested Event Drafts" was a hardcoded empty state: nothing
-- ever turned closed-survey responses into candidates. This migration adds
-- a deterministic (no ML, no randomness) scorer and snapshots the result
-- into survey_event_candidates the moment a survey closes — via the
-- host's close_survey(), the pg_cron close_expired_surveys() worker, or
-- the host's own "Refresh suggestions" button — and backfills every
-- survey that is ALREADY closed/archived (e.g. a survey closed before this
-- migration existed).
--
-- Scoring: every (date option x location option) pair is a candidate
-- ("" when the survey has no options of that kind). Supporters = distinct
-- respondents who picked BOTH that date and that location. score =
-- supporters * 10 + sum(coalesce(interest_level, 3)). Budget = the most
-- common budget among supporters; activities = top 3 among supporters;
-- suggested group size = median of supporters' own group sizes (falls back
-- to the supporter count). Top 5 pairs with >= 1 supporter are kept.
-- Ties break on option order in the survey's own config, never random.

CREATE TABLE IF NOT EXISTS survey_event_candidates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id uuid NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
  rank int NOT NULL,
  date_option_id text NOT NULL DEFAULT '',
  date_label text NOT NULL DEFAULT '',
  location_option_id text NOT NULL DEFAULT '',
  location_label text NOT NULL DEFAULT '',
  budget_label text NOT NULL DEFAULT '',
  activity_labels text[] NOT NULL DEFAULT '{}',
  supporter_count int NOT NULL DEFAULT 0,
  response_total int NOT NULL DEFAULT 0,
  consent_count int NOT NULL DEFAULT 0,
  suggested_group_size int,
  score numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'suggested' CHECK (status IN ('suggested', 'dismissed', 'used')),
  generated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (survey_id, date_option_id, location_option_id)
);

CREATE INDEX IF NOT EXISTS idx_survey_event_candidates_survey ON survey_event_candidates(survey_id);

ALTER TABLE survey_event_candidates ENABLE ROW LEVEL SECURITY;

-- Host/admin read only; the only write paths are the RPCs below.
CREATE POLICY "survey_event_candidates_select" ON survey_event_candidates FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM surveys s JOIN organizers o ON o.id = s.organizer_id
    WHERE s.id = survey_event_candidates.survey_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
  OR public.is_platform_admin()
);

-- Internal generator: no auth check (callers are the host RPCs and the
-- cron worker, which already authorised/own the survey). Idempotent —
-- replaces still-'suggested' rows, leaves 'dismissed'/'used' rows alone and
-- never re-suggests a pair the host already dismissed or used.
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
    SELECT d.value->>'id' AS id, COALESCE(d.value->>'label', '') AS label, d.ord
    FROM jsonb_array_elements(COALESCE(v_survey.config->'date_options', '[]'::jsonb)) WITH ORDINALITY AS d(value, ord)
    UNION ALL SELECT '', '', 0
    WHERE jsonb_array_length(COALESCE(v_survey.config->'date_options', '[]'::jsonb)) = 0
  ),
  locs AS (
    SELECT l.value->>'id' AS id, COALESCE(l.value->>'label', '') AS label, l.ord
    FROM jsonb_array_elements(COALESCE(v_survey.config->'location_options', '[]'::jsonb)) WITH ORDINALITY AS l(value, ord)
    UNION ALL SELECT '', '', 0
    WHERE jsonb_array_length(COALESCE(v_survey.config->'location_options', '[]'::jsonb)) = 0
  ),
  pairs AS (
    SELECT d.id AS d_id, d.label AS d_label, d.ord AS d_ord, l.id AS l_id, l.label AS l_label, l.ord AS l_ord
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
    budget_label, activity_labels, supporter_count, response_total, consent_count,
    suggested_group_size, score
  )
  SELECT p_survey_id, t.rnk::int, t.d_id, t.d_label, t.l_id, t.l_label,
         COALESCE((SELECT b.value->>'label'
                   FROM jsonb_array_elements(COALESCE(v_survey.config->'budget_options', '[]'::jsonb)) AS b(value)
                   WHERE b.value->>'id' = bp.bid LIMIT 1), ''),
         COALESCE(ap.labels, '{}'), t.supporters, v_total, t.consent,
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

-- Host-callable refresh (also used by the client right after a close, and
-- as the fallback if a survey somehow has no candidates yet). Only for a
-- survey that is no longer collecting responses.
CREATE OR REPLACE FUNCTION public.generate_survey_candidates(p_survey_id uuid)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_survey surveys%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_survey FROM surveys WHERE id = p_survey_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'SURVEY_NOT_FOUND'; END IF;
  IF NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_survey.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_survey.status NOT IN ('closed', 'archived')
     AND NOT (v_survey.status = 'active' AND v_survey.closes_at IS NOT NULL AND v_survey.closes_at <= now()) THEN
    RAISE EXCEPTION 'SURVEY_NOT_CLOSED';
  END IF;
  RETURN public._generate_survey_candidates(p_survey_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.generate_survey_candidates(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.generate_survey_candidates(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_survey_candidate_status(p_candidate_id uuid, p_status text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_status NOT IN ('suggested', 'dismissed', 'used') THEN RAISE EXCEPTION 'INVALID_STATUS'; END IF;
  UPDATE survey_event_candidates c SET status = p_status
  WHERE c.id = p_candidate_id AND EXISTS (
    SELECT 1 FROM surveys s JOIN organizers o ON o.id = s.organizer_id
    WHERE s.id = c.survey_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  );
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_survey_candidate_status(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_survey_candidate_status(uuid, text) TO authenticated;

-- close_survey: same body as migration 114 plus candidate snapshotting in
-- the same transaction.
CREATE OR REPLACE FUNCTION public.close_survey(p_survey_id uuid)
RETURNS surveys
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
  IF v_survey.status != 'active' THEN RAISE EXCEPTION 'SURVEY_NOT_ACTIVE'; END IF;

  UPDATE surveys SET status = 'closed', closed_at = now(), closes_at = LEAST(closes_at, now())
  WHERE id = p_survey_id RETURNING * INTO v_survey;
  PERFORM public._generate_survey_candidates(p_survey_id);
  RETURN v_survey;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.close_survey(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.close_survey(uuid) TO authenticated;

-- Cron worker: same idempotent WHERE as 114, now also snapshotting
-- candidates for every survey it just closed.
CREATE OR REPLACE FUNCTION public.close_expired_surveys() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id uuid;
BEGIN
  FOR v_id IN
    UPDATE surveys SET status = 'closed', closed_at = now()
    WHERE status = 'active' AND closes_at IS NOT NULL AND closes_at <= now()
    RETURNING id
  LOOP
    PERFORM public._generate_survey_candidates(v_id);
  END LOOP;
END;
$$;

-- Backfill: every survey already closed/archived before this migration
-- (the reported "T2" case) gets its candidates now.
DO $$
DECLARE
  v_id uuid;
BEGIN
  FOR v_id IN SELECT id FROM surveys WHERE status IN ('closed', 'archived') LOOP
    PERFORM public._generate_survey_candidates(v_id);
  END LOOP;
END;
$$;
