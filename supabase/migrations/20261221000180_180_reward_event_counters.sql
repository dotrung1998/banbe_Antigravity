-- 180: minimal, NON-IDENTIFYING aggregate counters for offer activity (Phase 0, step 5). Flag OFF by default.
--
-- DESIGN: aggregate counters, not an event log. One row per (offer, UTC day, coarse region, event type) holding
-- only a count. There is no row per view/issue/redemption, so there is nothing to join back to a person, and no
-- exact time exists anywhere (date only). Why not an event log: even without user_id, per-event rows with
-- timestamps can be re-identified by correlation (time + offer + region) and invite later "just add a column".
-- A counter table cannot grow into that without a visible schema change.
--
-- WHAT IS (NOT) STORED
--   Stored: offer_id (reward_catalog.code of a partner_offer row), event_date (UTC date), region_coarse, event_type, count.
--   NOT stored, anywhere in these objects: user id, phone, email, device, IP, session, user agent, exact timestamp.
--   No created_at/updated_at (an updated_at would be an exact time). The RPC authenticates the caller
--   (auth.uid() IS NOT NULL, anon refused) but never reads it into a variable, writes it, or logs it. No RAISE LOG/
--   NOTICE/WARNING, no audit trigger, no side table.
--   LIMIT of that claim: it covers OUR database objects. The Supabase/PostgREST API gateway logs of the platform
--   record the request (time, path, JWT subject) outside our schema; retention there is a platform setting, not
--   something this migration controls. Say so in the policy.
--
-- region_coarse: 'VN' | 'US' | 'OTHER' | 'UNKNOWN' (CHECK). Country level is the coarsest cut that still matters to
--   a VN/US program and is deliberately NOT a city or district: finer areas make small cells that identify people.
--   The client supplies it (the server stores no location for this); an invalid value is stored as 'UNKNOWN'.
--
-- WRITERS
--   * record_reward_event(): the ONLY client door. It accepts 'offer_viewed' ONLY. A client must not be able to claim
--     'offer_issued'/'offer_redeemed' (spoofing); those two are bumped by the server-only helper
--     rewards_bump_event_counter() from the future issuing/confirm RPCs (not part of this migration; no grants).
--   * Flag OFF (reward_feature_flags 'reward_events', default false): record_reward_event writes nothing and returns
--     {success:true, recorded:false} — identical for every caller/offer, so it leaks nothing either.
--   * Atomic upsert (ON CONFLICT DO UPDATE count = count + 1). Contention on one hot key is fine at this scale.
--
-- READER: admin_reward_event_report() — platform admin only (not for partners). Cells with count < the configured
--   minimum group size (reward_event_config.min_group_size, default 20, CHECK >= 5) are suppressed and only counted.
--
-- KNOWN LIMITS (read before enabling)
--   * No de-duplication is possible without identity: one person tapping N times adds N. Counts are EVENTS, never
--     "people"; label reports that way. Mitigation: the client sends at most once per offer per session/day
--     (client-side; NOT built here) and reports are described as "views".
--   * Anyone with a login can inflate 'offer_viewed' for any live offer. Treat counters as indicative, not billing
--     evidence; settlement must use reward_redemptions (exact) once it exists.
--   * Differencing across overlapping report windows can still reveal small deltas; the threshold limits, not
--     eliminates, that. Admin-only access is the real control.
--   * Policy: even though nothing identifies a person, the policy must describe this measurement and a lawyer should
--     review it BEFORE the flag is turned on (docs/rewards-phase0-summary.md).
--
-- ROLLBACK (data-safe): supabase/rollbacks/20261221000180_180_revert_reward_event_counters.sql turns the flag off and,
-- ONLY if the counter table is empty, drops the new objects; with data it only turns the flag off.

CREATE TABLE IF NOT EXISTS public.reward_event_config (
  id             int PRIMARY KEY CHECK (id = 1),
  min_group_size int NOT NULL DEFAULT 20 CHECK (min_group_size >= 5)
);
INSERT INTO public.reward_event_config (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.reward_event_counters (
  offer_id      text   NOT NULL REFERENCES public.reward_catalog(code) ON DELETE CASCADE,   -- a partner_offer catalog code
  event_date    date   NOT NULL,                                                              -- UTC calendar date only
  region_coarse text   NOT NULL CHECK (region_coarse IN ('VN', 'US', 'OTHER', 'UNKNOWN')),
  event_type    text   NOT NULL CHECK (event_type IN ('offer_viewed', 'offer_issued', 'offer_redeemed')),
  count         bigint NOT NULL DEFAULT 0 CHECK (count >= 0),
  PRIMARY KEY (offer_id, event_date, region_coarse, event_type)
);

INSERT INTO public.reward_feature_flags (flag, enabled) VALUES ('reward_events', false) ON CONFLICT (flag) DO NOTHING;

ALTER TABLE public.reward_event_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reward_event_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reward_event_config, public.reward_event_counters FROM anon, authenticated, PUBLIC;

-- Server-only incrementer (no grants). Validates and upserts; knows nothing about any user.
CREATE OR REPLACE FUNCTION public.rewards_bump_event_counter(p_offer_id text, p_event_type text, p_region text DEFAULT 'UNKNOWN')
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_region text := CASE WHEN p_region IN ('VN', 'US', 'OTHER', 'UNKNOWN') THEN p_region ELSE 'UNKNOWN' END;
BEGIN
  IF p_event_type NOT IN ('offer_viewed', 'offer_issued', 'offer_redeemed') THEN RETURN false; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.reward_catalog c WHERE c.code = p_offer_id AND c.kind = 'partner_offer' AND c.active) THEN RETURN false; END IF;
  INSERT INTO public.reward_event_counters (offer_id, event_date, region_coarse, event_type, count)
  VALUES (p_offer_id, (now() AT TIME ZONE 'UTC')::date, v_region, p_event_type, 1)
  ON CONFLICT (offer_id, event_date, region_coarse, event_type) DO UPDATE SET count = public.reward_event_counters.count + 1;
  RETURN true;
END;
$$;

-- The client door: authenticated, anonymous-by-design (the caller is checked, never recorded), 'offer_viewed' only.
CREATE OR REPLACE FUNCTION public.record_reward_event(p_offer_id text, p_event_type text DEFAULT 'offer_viewed', p_region text DEFAULT 'UNKNOWN')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT COALESCE((SELECT f.enabled FROM public.reward_feature_flags f WHERE f.flag = 'reward_events'), false) THEN
    RETURN jsonb_build_object('success', true, 'recorded', false);          -- flag off: write nothing, neutral answer
  END IF;
  IF p_event_type IS DISTINCT FROM 'offer_viewed' THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_EVENT'); END IF;
  RETURN jsonb_build_object('success', true, 'recorded', public.rewards_bump_event_counter(p_offer_id, p_event_type, p_region));
END;
$$;

-- Admin-only aggregate report with small-cell suppression. Returns suppressed_cells as a NUMBER only (never their sums).
CREATE OR REPLACE FUNCTION public.admin_reward_event_report(p_from date DEFAULT NULL, p_to date DEFAULT NULL, p_by_day boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_min int := (SELECT min_group_size FROM public.reward_event_config WHERE id = 1);
        v_from date := COALESCE(p_from, (now() AT TIME ZONE 'UTC')::date - 30);
        v_to date := COALESCE(p_to, (now() AT TIME ZONE 'UTC')::date);
        v_rows jsonb; v_hidden int;
BEGIN
  IF NOT public.is_platform_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_ADMIN'); END IF;
  WITH cells AS (
    SELECT c.offer_id, CASE WHEN p_by_day THEN c.event_date END AS day, c.region_coarse, c.event_type, sum(c.count)::bigint AS n
      FROM public.reward_event_counters c WHERE c.event_date BETWEEN v_from AND v_to
     GROUP BY c.offer_id, CASE WHEN p_by_day THEN c.event_date END, c.region_coarse, c.event_type)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('offer_id', offer_id, 'date', day, 'region', region_coarse, 'event_type', event_type, 'count', n)
                            ORDER BY offer_id, day, region_coarse, event_type) FILTER (WHERE n >= v_min), '[]'::jsonb),
         count(*) FILTER (WHERE n < v_min)
    INTO v_rows, v_hidden FROM cells;
  RETURN jsonb_build_object('success', true, 'min_group_size', v_min, 'from', v_from, 'to', v_to, 'rows', v_rows, 'suppressed_cells', v_hidden);
END;
$$;

REVOKE ALL ON FUNCTION public.rewards_bump_event_counter(text, text, text) FROM anon, authenticated, PUBLIC;
REVOKE ALL ON FUNCTION public.record_reward_event(text, text, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_reward_event(text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_reward_event_report(date, date, boolean) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reward_event_report(date, date, boolean) TO authenticated;   -- re-checks is_platform_admin()
