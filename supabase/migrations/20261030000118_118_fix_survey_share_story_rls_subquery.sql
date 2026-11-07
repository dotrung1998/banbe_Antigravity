-- Migration: fix survey-story public-discovery RLS — CONFIRMED broken by a
-- real authenticated integration test against the deployed project
-- (tests/e2e/survey-story-visibility.integration.mjs), not assumed.
--
-- Root cause: migration 117's `stories_select_survey_share_public` policy
-- used a plain correlated subquery against `surveys`:
--   EXISTS (SELECT 1 FROM surveys sv WHERE sv.id = stories.survey_id AND sv.status <> 'draft')
-- A subquery inside an RLS policy's USING clause runs under the CALLING
-- user's own privileges, not the policy owner's — so for any viewer who
-- isn't the organizer's owner/admin, that subquery is itself subject to
-- `surveys_select_host` (host/admin-only SELECT), which returns ZERO rows
-- for them regardless of the real row's status. EXISTS(...) therefore
-- always evaluated to false for exactly the audience this policy existed
-- to serve (a non-owner, non-admin, non-follower viewer) — confirmed live:
-- a throwaway host published a real survey_share story, a throwaway
-- non-follower viewer's own authenticated `stories` SELECT returned 0 rows
-- for it, while get_survey_card() (a SECURITY DEFINER RPC, unaffected by
-- this class of bug) correctly returned the survey for that same viewer.
--
-- Fix: the SAME pattern note 21's own `is_event_host`/`has_event_invite_
-- access` helpers already established for an identical class of problem
-- (a policy needing to check another RLS-protected table without being
-- subject to that table's own RLS) — a small SECURITY DEFINER function,
-- owned by a role that bypasses RLS (same as every other SECURITY DEFINER
-- RPC in this schema, e.g. get_survey_public/get_host_refund_claims),
-- called FROM the policy instead of a raw subquery. This does not widen
-- who can read `surveys` directly at all — `surveys_select_host` is
-- completely untouched; only this one boolean check now sees through it,
-- exactly like get_survey_card() already safely does today.
CREATE OR REPLACE FUNCTION public.is_survey_publicly_shareable(p_survey_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM surveys sv WHERE sv.id = p_survey_id AND sv.status <> 'draft'
  );
$$;
REVOKE ALL ON FUNCTION public.is_survey_publicly_shareable(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_survey_publicly_shareable(uuid) TO authenticated;

DROP POLICY IF EXISTS "stories_select_survey_share_public" ON stories;
CREATE POLICY "stories_select_survey_share_public" ON stories FOR SELECT TO authenticated USING (
  kind = 'survey_share'
  AND survey_id IS NOT NULL
  AND public.is_survey_publicly_shareable(survey_id)
);
