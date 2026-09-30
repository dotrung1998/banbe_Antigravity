-- Migration: Interest surveys before an event (Slice B).
--
-- Confirmed by audit: no survey/poll/interest table, RPC or RLS exists
-- anywhere in this schema before this migration. Deliberately a single
-- structured `config` JSON block per survey (fixed MVP question set: date/
-- time options, location options, budget range, activities, group size,
-- interest level, free text) rather than a generic question/option engine
-- — the task's own "don't build an unrestricted complex form-builder in
-- this pass" instruction. Reuses this app's existing auth (a respondent
-- IS a signed-in Supabase Auth user, in-app or via the browser page's own
-- email-code sign-in — no new auth system), existing timestamptz + fixed
-- 'Asia/Ho_Chi_Minh' timezone convention events already use, and the same
-- host-ownership-via-organizers pattern every other host-only RPC here
-- uses.
--
-- Scope cut, stated honestly: survey AUDIENCE is public-by-link only in
-- this pass (anyone with the `/?survey=<public_id>` link can respond,
-- same trust model as this app's own SPA-only routing — see section 3's
-- comment) — a truly invite-gated private survey (reusing event_invites)
-- is not implemented here. No public LISTING of surveys exists either;
-- the public_id is the only way to reach one, same shape as a shared
-- event link.

CREATE TYPE survey_status AS ENUM ('draft', 'active', 'closed', 'archived');

-- ============ 1. surveys ============
CREATE TABLE IF NOT EXISTS surveys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id text NOT NULL REFERENCES organizers(id) ON DELETE CASCADE,
  -- Short, unguessable-enough public identifier for the browser route —
  -- NOT the primary key, so it can be regenerated/rotated later without
  -- touching foreign keys, same reasoning as events.slug vs events.id.
  -- pgcrypto lives in the `extensions` schema on Supabase, not `public` —
  -- schema-qualified because a column DEFAULT expression is resolved at
  -- CREATE TABLE time against the plain connection search_path, which has
  -- no equivalent of a function's own `SET search_path` to fall back on.
  -- (Confirmed live: an unqualified gen_random_bytes() call here is
  -- exactly what failed a real `supabase db push` with "function
  -- gen_random_bytes(integer) does not exist" — this is the fix, not a
  -- guess.)
  public_id text NOT NULL UNIQUE DEFAULT encode(extensions.gen_random_bytes(9), 'base64'),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  status survey_status NOT NULL DEFAULT 'draft',
  timezone text NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
  opens_at timestamptz,
  closes_at timestamptz,
  closed_at timestamptz,
  -- Fixed MVP question set, all in one JSON block:
  --   date_options: [{id, label}] — multi-select
  --   location_options: [{id, label}] — multi-select
  --   budget_options: [{id, label}] — single-select bucket, not a raw number
  --   activity_options: [{id, label}] — multi-select
  --   group_size_min / group_size_max: int bounds (including the
  --     respondent), validated server-side on every response write
  --   required: { interest_level, date_options, group_size,
  --     location_options, budget, activities, free_text } -> bool, host-set
  -- Stable ids (not array index) so a later host edit that reorders
  -- options doesn't reinterpret an old response's stored choices.
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Bumped only when config's OPTION SETS change after responses already
  -- exist (see submit_survey_response's own versioning note below) — old
  -- responses keep their own recorded config_version so their answers are
  -- never silently reinterpreted against options that no longer mean the
  -- same thing.
  config_version int NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_surveys_organizer ON surveys(organizer_id);

ALTER TABLE surveys ENABLE ROW LEVEL SECURITY;

-- Direct table access is HOST/ADMIN ONLY, on purpose — the public browser
-- page never reads this table directly (see get_survey_public below),
-- so a public route can't accidentally leak a draft's internal state,
-- unpublished title, or any field this pass later adds without an
-- explicit allowlist.
CREATE POLICY "surveys_select_host" ON surveys FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = surveys.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
  OR public.is_platform_admin()
);

-- ============ 2. survey_responses ============
CREATE TABLE IF NOT EXISTS survey_responses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id uuid NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
  respondent_id uuid NOT NULL REFERENCES auth.users(id),
  -- The config_version this response was validated against (see surveys.
  -- config_version) — never reinterpreted against a later structural edit.
  config_version int NOT NULL,
  interest_level int,
  date_options text[] NOT NULL DEFAULT '{}',
  group_size int,
  location_options text[] NOT NULL DEFAULT '{}',
  budget_option text,
  activities text[] NOT NULL DEFAULT '{}',
  free_text text NOT NULL DEFAULT '',
  -- Separate from answering, per the task's own explicit instruction:
  -- "optional contact/follow-up consent must be separate from answering."
  -- Never auto-true, never used to enroll anyone in marketing by itself.
  contact_consent boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (survey_id, respondent_id)
);

CREATE INDEX IF NOT EXISTS idx_survey_responses_survey ON survey_responses(survey_id);

ALTER TABLE survey_responses ENABLE ROW LEVEL SECURITY;

-- Respondents see only their own answer (never another respondent's name
-- or answers); host sees every response to their own survey; admin sees
-- all. No direct INSERT/UPDATE policy — submit_survey_response (below) is
-- the only write path, so the closure/validation/versioning rules below
-- can never be bypassed by a direct client upsert.
CREATE POLICY "survey_responses_select" ON survey_responses FOR SELECT TO authenticated USING (
  respondent_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM surveys s JOIN organizers o ON o.id = s.organizer_id
    WHERE s.id = survey_responses.survey_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
  OR public.is_platform_admin()
);

-- ============ 3. Host RPCs ============

CREATE OR REPLACE FUNCTION public.create_survey(
  p_organizer_id text, p_title text, p_description text,
  p_opens_at timestamptz, p_closes_at timestamptz, p_timezone text,
  p_config jsonb
) RETURNS surveys
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_survey surveys%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF trim(coalesce(p_title, '')) = '' THEN RAISE EXCEPTION 'TITLE_REQUIRED'; END IF;
  IF p_closes_at IS NULL OR p_opens_at IS NULL OR p_closes_at <= p_opens_at THEN
    RAISE EXCEPTION 'INVALID_WINDOW';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = p_organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  INSERT INTO surveys (organizer_id, title, description, timezone, opens_at, closes_at, config, created_by, status)
  VALUES (p_organizer_id, trim(p_title), coalesce(p_description, ''), coalesce(nullif(p_timezone, ''), 'Asia/Ho_Chi_Minh'), p_opens_at, p_closes_at, coalesce(p_config, '{}'::jsonb), auth.uid(), 'draft')
  RETURNING * INTO v_survey;
  RETURN v_survey;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.create_survey(text, text, text, timestamptz, timestamptz, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_survey(text, text, text, timestamptz, timestamptz, text, jsonb) TO authenticated;

-- Editing: title/description/closes_at are always editable by the host.
-- p_config is only accepted (non-NULL) while the survey has ZERO
-- responses — once a response exists, changing the option sets would
-- silently reinterpret what that respondent actually chose, exactly the
-- "lock structural changes, or version them" rule the task calls for.
-- This pass takes the LOCK branch (simpler, honest about the tradeoff);
-- config_version exists for a future pass that wants true versioning
-- instead of a hard lock.
CREATE OR REPLACE FUNCTION public.update_survey(
  p_survey_id uuid, p_title text DEFAULT NULL, p_description text DEFAULT NULL,
  p_closes_at timestamptz DEFAULT NULL, p_config jsonb DEFAULT NULL
) RETURNS surveys
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_survey surveys%ROWTYPE;
  v_response_count int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_survey FROM surveys WHERE id = p_survey_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SURVEY_NOT_FOUND'; END IF;
  IF NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_survey.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_survey.status = 'archived' THEN RAISE EXCEPTION 'SURVEY_ARCHIVED'; END IF;

  IF p_config IS NOT NULL THEN
    SELECT count(*) INTO v_response_count FROM survey_responses WHERE survey_id = p_survey_id;
    IF v_response_count > 0 THEN RAISE EXCEPTION 'STRUCTURAL_CHANGE_LOCKED'; END IF;
  END IF;

  UPDATE surveys SET
    title = coalesce(nullif(trim(p_title), ''), title),
    description = coalesce(p_description, description),
    closes_at = coalesce(p_closes_at, closes_at),
    config = coalesce(p_config, config)
  WHERE id = p_survey_id
  RETURNING * INTO v_survey;
  RETURN v_survey;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.update_survey(uuid, text, text, timestamptz, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_survey(uuid, text, text, timestamptz, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.publish_survey(p_survey_id uuid)
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
  IF v_survey.status != 'draft' THEN RAISE EXCEPTION 'SURVEY_NOT_DRAFT'; END IF;
  IF v_survey.closes_at <= now() THEN RAISE EXCEPTION 'CLOSES_AT_IN_PAST'; END IF;

  UPDATE surveys SET status = 'active', opens_at = COALESCE(opens_at, now())
  WHERE id = p_survey_id RETURNING * INTO v_survey;
  RETURN v_survey;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.publish_survey(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.publish_survey(uuid) TO authenticated;

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
  RETURN v_survey;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.close_survey(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.close_survey(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.archive_survey(p_survey_id uuid)
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

  UPDATE surveys SET status = 'archived' WHERE id = p_survey_id RETURNING * INTO v_survey;
  RETURN v_survey;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.archive_survey(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.archive_survey(uuid) TO authenticated;

-- ============ 4. Public read (the browser page's ONLY read path) ============
-- Deliberately an allowlisted field set, never `SELECT *` — a public
-- route must not be able to leak a field this pass or a later one adds to
-- `surveys` without an explicit decision to expose it. Effective status
-- is computed here (closes_at may have passed before the closure worker
-- runs), never trusted from the stored `status` column alone.
CREATE OR REPLACE FUNCTION public.get_survey_public(p_public_id text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_survey surveys%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_effective_status text;
BEGIN
  SELECT * INTO v_survey FROM surveys WHERE public_id = p_public_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;
  -- A draft is host-only; there is nothing dishonest about returning the
  -- same NOT_FOUND a truly-missing link would — a draft link was never
  -- meant to be reachable at all yet.
  IF v_survey.status = 'draft' THEN
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

-- ============ 5. Responding ============

-- One current response per authenticated respondent, editable until
-- closure, enforced atomically via UNIQUE(survey_id, respondent_id) +
-- ON CONFLICT DO UPDATE under the survey row's own FOR UPDATE lock (so a
-- host's close_survey() and a respondent's concurrent submit can't race
-- past each other — whichever acquires the row lock first wins, the
-- other sees the post-lock, authoritative status).
CREATE OR REPLACE FUNCTION public.submit_survey_response(
  p_survey_id uuid,
  p_interest_level int DEFAULT NULL,
  p_date_options text[] DEFAULT '{}',
  p_group_size int DEFAULT NULL,
  p_location_options text[] DEFAULT '{}',
  p_budget_option text DEFAULT NULL,
  p_activities text[] DEFAULT '{}',
  p_free_text text DEFAULT '',
  p_contact_consent boolean DEFAULT false
) RETURNS survey_responses
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_survey surveys%ROWTYPE;
  v_required jsonb;
  v_valid_date_ids text[];
  v_valid_location_ids text[];
  v_valid_budget_ids text[];
  v_valid_activity_ids text[];
  v_min_size int;
  v_max_size int;
  v_row survey_responses%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT * INTO v_survey FROM surveys WHERE id = p_survey_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SURVEY_NOT_FOUND'; END IF;
  IF v_survey.status NOT IN ('active') THEN RAISE EXCEPTION 'SURVEY_NOT_ACTIVE'; END IF;
  -- Enforced here regardless of whether the closure worker has already
  -- flipped `status` yet — the task's own explicit "enforce closes_at on
  -- response writes even if the worker is late" instruction.
  IF v_survey.opens_at IS NOT NULL AND v_survey.opens_at > now() THEN RAISE EXCEPTION 'SURVEY_NOT_OPEN_YET'; END IF;
  IF v_survey.closes_at IS NOT NULL AND v_survey.closes_at <= now() THEN RAISE EXCEPTION 'SURVEY_CLOSED'; END IF;

  v_required := COALESCE(v_survey.config->'required', '{}'::jsonb);
  SELECT array_agg(value->>'id') INTO v_valid_date_ids FROM jsonb_array_elements(COALESCE(v_survey.config->'date_options', '[]'::jsonb));
  SELECT array_agg(value->>'id') INTO v_valid_location_ids FROM jsonb_array_elements(COALESCE(v_survey.config->'location_options', '[]'::jsonb));
  SELECT array_agg(value->>'id') INTO v_valid_budget_ids FROM jsonb_array_elements(COALESCE(v_survey.config->'budget_options', '[]'::jsonb));
  SELECT array_agg(value->>'id') INTO v_valid_activity_ids FROM jsonb_array_elements(COALESCE(v_survey.config->'activity_options', '[]'::jsonb));
  v_min_size := COALESCE((v_survey.config->>'group_size_min')::int, 1);
  v_max_size := COALESCE((v_survey.config->>'group_size_max')::int, 50);

  -- Required-field + range/option-membership validation. Server is the
  -- real gate — the browser/app form is a UX nicety, same convention this
  -- codebase's own createSubmit() already follows for event creation.
  IF (v_required->>'interest_level')::boolean AND p_interest_level IS NULL THEN RAISE EXCEPTION 'INTEREST_LEVEL_REQUIRED'; END IF;
  IF p_interest_level IS NOT NULL AND (p_interest_level < 1 OR p_interest_level > 5) THEN RAISE EXCEPTION 'INVALID_INTEREST_LEVEL'; END IF;

  IF (v_required->>'date_options')::boolean AND coalesce(array_length(p_date_options, 1), 0) = 0 THEN RAISE EXCEPTION 'DATE_OPTIONS_REQUIRED'; END IF;
  IF NOT (p_date_options <@ COALESCE(v_valid_date_ids, '{}')) THEN RAISE EXCEPTION 'INVALID_DATE_OPTION'; END IF;

  IF (v_required->>'location_options')::boolean AND coalesce(array_length(p_location_options, 1), 0) = 0 THEN RAISE EXCEPTION 'LOCATION_OPTIONS_REQUIRED'; END IF;
  IF NOT (p_location_options <@ COALESCE(v_valid_location_ids, '{}')) THEN RAISE EXCEPTION 'INVALID_LOCATION_OPTION'; END IF;

  IF (v_required->>'budget')::boolean AND p_budget_option IS NULL THEN RAISE EXCEPTION 'BUDGET_REQUIRED'; END IF;
  IF p_budget_option IS NOT NULL AND NOT (p_budget_option = ANY(COALESCE(v_valid_budget_ids, '{}'))) THEN RAISE EXCEPTION 'INVALID_BUDGET_OPTION'; END IF;

  IF (v_required->>'activities')::boolean AND coalesce(array_length(p_activities, 1), 0) = 0 THEN RAISE EXCEPTION 'ACTIVITIES_REQUIRED'; END IF;
  IF NOT (p_activities <@ COALESCE(v_valid_activity_ids, '{}')) THEN RAISE EXCEPTION 'INVALID_ACTIVITY_OPTION'; END IF;

  IF (v_required->>'group_size')::boolean AND p_group_size IS NULL THEN RAISE EXCEPTION 'GROUP_SIZE_REQUIRED'; END IF;
  IF p_group_size IS NOT NULL AND (p_group_size < v_min_size OR p_group_size > v_max_size) THEN RAISE EXCEPTION 'INVALID_GROUP_SIZE'; END IF;

  IF (v_required->>'free_text')::boolean AND trim(coalesce(p_free_text, '')) = '' THEN RAISE EXCEPTION 'FREE_TEXT_REQUIRED'; END IF;
  IF length(coalesce(p_free_text, '')) > 2000 THEN RAISE EXCEPTION 'FREE_TEXT_TOO_LONG'; END IF;

  INSERT INTO survey_responses (
    survey_id, respondent_id, config_version, interest_level, date_options,
    group_size, location_options, budget_option, activities, free_text,
    contact_consent, updated_at
  ) VALUES (
    p_survey_id, auth.uid(), v_survey.config_version, p_interest_level, COALESCE(p_date_options, '{}'),
    p_group_size, COALESCE(p_location_options, '{}'), p_budget_option, COALESCE(p_activities, '{}'), COALESCE(p_free_text, ''),
    COALESCE(p_contact_consent, false), now()
  )
  ON CONFLICT (survey_id, respondent_id) DO UPDATE SET
    config_version = EXCLUDED.config_version,
    interest_level = EXCLUDED.interest_level,
    date_options = EXCLUDED.date_options,
    group_size = EXCLUDED.group_size,
    location_options = EXCLUDED.location_options,
    budget_option = EXCLUDED.budget_option,
    activities = EXCLUDED.activities,
    free_text = EXCLUDED.free_text,
    contact_consent = EXCLUDED.contact_consent,
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.submit_survey_response(uuid, int, text[], int, text[], text, text[], text, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.submit_survey_response(uuid, int, text[], int, text[], text, text[], text, boolean) TO authenticated;

-- ============ 6. Closure worker (pg_cron, same pattern as 008) ============
-- Deadline closure must work without the host opening the app — reuses
-- this project's existing pg_cron pattern (008) rather than inventing a
-- new job/outbox mechanism. Idempotent (only touches rows still 'active'
-- past their own closes_at), so a missed/overlapping run cannot double-
-- close or duplicate anything. Candidate generation (Slice C) is NOT
-- implemented — see the domain note — so this job only flips status today;
-- a later pass adds candidate snapshotting here, in the same transaction,
-- keyed by this same idempotent WHERE clause.
CREATE OR REPLACE FUNCTION public.close_expired_surveys() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE surveys SET status = 'closed', closed_at = now()
  WHERE status = 'active' AND closes_at IS NOT NULL AND closes_at <= now();
$$;

-- pg_cron already enabled by migration 008; cron.schedule() upserts by
-- job_name, so re-running this migration is idempotent, same as 008's own
-- jobs.
SELECT cron.schedule(
  job_name  => 'goc_close_expired_surveys',
  schedule  => '* * * * *',
  command   => $cmd$ SELECT public.close_expired_surveys(); $cmd$
);
