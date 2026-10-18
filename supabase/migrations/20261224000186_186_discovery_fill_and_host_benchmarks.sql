-- 186 — Real seat fill for discovery cards + aggregate host benchmarks ("recipe for success") + per-event host goal.
--
-- Why (note 50):
-- - `events.seats_remaining` is written once at insert and never decremented: hold_seats / claim_seats count
--   bookings directly with booking_holds_seat() (026:112, 162:543). Any "N left" / "Almost full" / "9 going" the
--   client derives from seats_remaining is stale. get_public_event_fill() counts the SAME rule the booking path
--   enforces, so the badge can never disagree with what hold_seats would accept.
-- - Event creation had no cross-event data at all (the "similar price" hint sampled the client's 300 oldest
--   discovery rows, cancelled ones included). get_host_benchmarks() aggregates public, non-cancelled events.
-- - The optional "What matters most for this event?" answer must never reach guests. `events` is readable by
--   anyone who can see the event, so it lives in an owner-only side table (same reasoning as 162's
--   profile_event_preferences), reachable only through SECURITY DEFINER RPCs scoped to the host.
--
-- Privacy rules (enforced here, not in the client):
-- - Benchmarks: a slice (whole sample, one weekday×slot cell, one well-filled/other group, one keyword) is
--   returned only when it covers >= 5 events from >= 3 distinct organizers. Smaller slices come back NULL, so no
--   single host's sales can be read off a cell.
-- - Audience demand reads profile_event_preferences only as a count, floored to the nearest 10, NULL below 10.
--   No ids, no answers, no per-person rows. Preferences have no city, so demand is platform-wide by design.
-- - Fill is returned for LIVE PUBLIC events only (invite-only / draft / review / cancelled / ended excluded).
--   A public event's capacity and seats-left were already public (seats_remaining was always selectable).
--
-- Additive only. Rollback: supabase/rollbacks/20261224000186_186_revert_discovery_fill_and_host_benchmarks.sql

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Seat fill for discovery cards
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_public_event_fill(p_event_ids text[])
RETURNS TABLE (event_id text, booked int, capacity int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT e.id,
         COALESCE((
           SELECT SUM(b.qty)::int FROM bookings b
           WHERE b.event_id = e.id
             AND booking_holds_seat(b.payment_state, b.hold_expires_at, b.status)
         ), 0) AS booked,
         e.capacity
  FROM events e
  WHERE e.id = ANY ((COALESCE(p_event_ids, '{}'))[1:300])
    AND e.status = 'live'
    AND e.visibility = 'public'
    AND e.cancelled_at IS NULL;
$$;
REVOKE ALL ON FUNCTION public.get_public_event_fill(text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_event_fill(text[]) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Host benchmarks
-- ---------------------------------------------------------------------------
-- Time slot in the platform's local time (all launch markets are VN; US events are rare and still sort
-- sensibly). afternoon < 17:00 <= evening < 21:00 <= late.
CREATE OR REPLACE FUNCTION public.benchmark_slot(p_starts_at timestamptz)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN extract(hour FROM p_starts_at AT TIME ZONE 'Asia/Ho_Chi_Minh') < 17 THEN 'afternoon'
    WHEN extract(hour FROM p_starts_at AT TIME ZONE 'Asia/Ho_Chi_Minh') < 21 THEN 'evening'
    ELSE 'late'
  END;
$$;

CREATE OR REPLACE FUNCTION public.get_host_benchmarks(p_cat_key text, p_city text)
RETURNS jsonb
-- VOLATILE (not STABLE): it fills a session temp table. It writes nothing persistent.
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  k_events constant int := 5;
  k_orgs   constant int := 3;
  v_cat  text := lower(trim(COALESCE(p_cat_key, '')));
  v_city text := lower(trim(COALESCE(p_city, '')));
  v_level text;
  v_out jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  -- Base pool: public, not cancelled, started in the last 180 days or starting in the next 60.
  CREATE TEMP TABLE IF NOT EXISTS _bm_pool (
    id text, organizer_id text, cat_key text, city text, price_vnd int, capacity int,
    starts_at timestamptz, submitted_at timestamptz, started boolean, booked int,
    fill numeric, photos int, has_intro boolean, has_included boolean, keywords text[]
  ) ON COMMIT DROP;
  TRUNCATE _bm_pool;

  INSERT INTO _bm_pool
  SELECT e.id, e.organizer_id, lower(COALESCE(e.cat_key, '')), lower(trim(COALESCE(e.city, ''))),
         e.price_vnd, e.capacity, e.starts_at, e.submitted_at, e.starts_at < now(),
         f.booked,
         CASE WHEN e.capacity > 0 THEN LEAST(f.booked::numeric / e.capacity, 1) END,
         (SELECT count(*)::int FROM event_photos p WHERE p.event_id = e.id),
         length(trim(COALESCE(e.intro, ''))) > 0,
         jsonb_typeof(e.included_items) = 'array' AND jsonb_array_length(e.included_items) > 0,
         COALESCE(e.keywords, '{}')
  FROM events e
  CROSS JOIN LATERAL (
    SELECT COALESCE(SUM(b.qty), 0)::int AS booked FROM bookings b
    WHERE b.event_id = e.id AND booking_holds_seat(b.payment_state, b.hold_expires_at, b.status)
  ) f
  WHERE e.visibility = 'public'
    AND e.status IN ('live', 'ended')
    AND e.cancelled_at IS NULL
    AND e.organizer_id IS NOT NULL
    AND e.starts_at IS NOT NULL
    AND e.starts_at BETWEEN now() - interval '180 days' AND now() + interval '60 days';

  -- Fallback cascade: category+city -> category -> everything. First level that clears k wins.
  IF v_cat <> '' AND v_city <> '' AND (
       SELECT count(*) >= k_events AND count(DISTINCT organizer_id) >= k_orgs
       FROM _bm_pool WHERE cat_key = v_cat AND city = v_city) THEN
    v_level := 'category_city';
  ELSIF v_cat <> '' AND (
       SELECT count(*) >= k_events AND count(DISTINCT organizer_id) >= k_orgs
       FROM _bm_pool WHERE cat_key = v_cat) THEN
    v_level := 'category';
  ELSIF (SELECT count(*) >= k_events AND count(DISTINCT organizer_id) >= k_orgs FROM _bm_pool) THEN
    v_level := 'all';
  ELSE
    RETURN jsonb_build_object('success', true, 'level', NULL, 'n', 0);
  END IF;

  DELETE FROM _bm_pool
  WHERE NOT (CASE v_level
    WHEN 'category_city' THEN cat_key = v_cat AND city = v_city
    WHEN 'category' THEN cat_key = v_cat
    ELSE true END);

  WITH paid AS (SELECT price_vnd FROM _bm_pool WHERE price_vnd > 0),
  paid_stats AS (
    SELECT count(*) AS n, count(DISTINCT p.organizer_id) AS orgs,
           percentile_cont(0.25) WITHIN GROUP (ORDER BY p.price_vnd) AS p25,
           percentile_cont(0.5)  WITHIN GROUP (ORDER BY p.price_vnd) AS p50,
           percentile_cont(0.75) WITHIN GROUP (ORDER BY p.price_vnd) AS p75,
           min(p.price_vnd) AS lo, max(p.price_vnd) AS hi
    FROM _bm_pool p WHERE p.price_vnd > 0
  ),
  hist AS (
    SELECT CASE WHEN s.hi > s.lo THEN LEAST(width_bucket(p.price_vnd::numeric, s.lo::numeric, (s.hi + 1)::numeric, 10), 10) ELSE 1 END AS bucket,
           count(*) AS c
    FROM paid p CROSS JOIN paid_stats s
    GROUP BY 1
  ),
  started AS (SELECT * FROM _bm_pool WHERE started AND fill IS NOT NULL),
  started_stats AS (
    SELECT count(*) AS n, count(DISTINCT organizer_id) AS orgs,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY fill) AS fill_p50,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY capacity) AS cap_p50,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY booked) AS booked_p50
    FROM started
  ),
  cells AS (
    SELECT extract(isodow FROM starts_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::int AS dow,
           benchmark_slot(starts_at) AS slot,
           count(*) AS n, count(DISTINCT organizer_id) AS orgs,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY fill) AS fill_p50
    FROM started GROUP BY 1, 2
  ),
  groups AS (
    SELECT (fill >= 0.8) AS well_filled,
           count(*) AS n, count(DISTINCT organizer_id) AS orgs,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY photos) AS photos_p50,
           avg(has_intro::int) AS intro_share,
           avg(has_included::int) AS included_share,
           percentile_cont(0.5) WITHIN GROUP (
             ORDER BY extract(epoch FROM (starts_at - submitted_at)) / 86400.0
           ) FILTER (WHERE submitted_at IS NOT NULL AND submitted_at < starts_at) AS lead_days_p50,
           count(*) FILTER (WHERE submitted_at IS NOT NULL AND submitted_at < starts_at) AS lead_n
    FROM started GROUP BY 1
  ),
  kw AS (
    SELECT lower(trim(k)) AS keyword, count(DISTINCT p.id) AS events, count(DISTINCT p.organizer_id) AS orgs
    FROM _bm_pool p CROSS JOIN LATERAL unnest(p.keywords) AS k
    WHERE length(trim(k)) > 0
    GROUP BY 1
  )
  SELECT jsonb_build_object(
    'success', true,
    'level', v_level,
    'n', (SELECT count(*) FROM _bm_pool),
    'free_share', (SELECT round(avg((price_vnd = 0)::int)::numeric, 3) FROM _bm_pool),
    'price', (
      SELECT CASE WHEN s.n >= k_events AND s.orgs >= k_orgs THEN jsonb_build_object(
        'n', s.n, 'p25', round(s.p25), 'median', round(s.p50), 'p75', round(s.p75),
        'min', s.lo, 'max', s.hi,
        'histogram', (SELECT jsonb_agg(COALESCE(h.c, 0) ORDER BY g.b)
                      FROM generate_series(1, 10) AS g(b) LEFT JOIN hist h ON h.bucket = g.b)
      ) END FROM paid_stats s
    ),
    'fill', (
      SELECT CASE WHEN s.n >= k_events AND s.orgs >= k_orgs THEN jsonb_build_object(
        'n', s.n, 'median_fill', round(s.fill_p50::numeric, 3),
        'median_capacity', round(s.cap_p50), 'median_booked', round(s.booked_p50)
      ) END FROM started_stats s
    ),
    'slots', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('dow', c.dow, 'slot', c.slot, 'n', c.n,
                                          'median_fill', round(c.fill_p50::numeric, 3))
                       ORDER BY c.dow, c.slot)
      FROM cells c WHERE c.n >= k_events AND c.orgs >= k_orgs
    ), '[]'::jsonb),
    'well_filled', (
      SELECT CASE WHEN g.n >= k_events AND g.orgs >= k_orgs THEN jsonb_build_object(
        'n', g.n, 'median_photos', round(g.photos_p50::numeric, 1),
        'intro_share', round(g.intro_share::numeric, 3), 'included_share', round(g.included_share::numeric, 3),
        'median_lead_days', CASE WHEN g.lead_n >= k_events THEN round(g.lead_days_p50::numeric, 1) END
      ) END FROM groups g WHERE g.well_filled
    ),
    'others', (
      SELECT CASE WHEN g.n >= k_events AND g.orgs >= k_orgs THEN jsonb_build_object(
        'n', g.n, 'median_photos', round(g.photos_p50::numeric, 1),
        'intro_share', round(g.intro_share::numeric, 3), 'included_share', round(g.included_share::numeric, 3),
        'median_lead_days', CASE WHEN g.lead_n >= k_events THEN round(g.lead_days_p50::numeric, 1) END
      ) END FROM groups g WHERE NOT g.well_filled
    ),
    'keywords', COALESCE((
      SELECT jsonb_agg(t.keyword ORDER BY t.events DESC, t.keyword)
      FROM (SELECT * FROM kw WHERE orgs >= 2 ORDER BY events DESC, keyword LIMIT 10) t
    ), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION public.get_host_benchmarks(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_host_benchmarks(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_host_benchmarks(text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Audience demand (rounded count only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_audience_demand(p_cat_key text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cat text := lower(trim(COALESCE(p_cat_key, '')));
  v_n int;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF NOT v_cat = ANY (public.event_pref_ids('interests')) THEN
    RETURN jsonb_build_object('success', true, 'interested_people', NULL);
  END IF;

  SELECT count(*) INTO v_n
  FROM profile_event_preferences p
  WHERE p.event_preferences -> 'interests' ? v_cat;

  RETURN jsonb_build_object(
    'success', true,
    'interested_people', CASE WHEN v_n >= 10 THEN (v_n / 10) * 10 END
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_audience_demand(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_audience_demand(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_audience_demand(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. Per-event host goal (host-only side table)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_host_meta (
  event_id text PRIMARY KEY REFERENCES events(id) ON DELETE CASCADE,
  host_goal text CONSTRAINT event_host_meta_goal_valid
    CHECK (host_goal IS NULL OR host_goal IN ('fill_seats', 'regular_crowd', 'try_idea', 'small_premium')),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.event_host_meta ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.event_host_meta FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.set_event_host_goal(p_event_id text, p_goal text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_goal text := NULLIF(trim(COALESCE(p_goal, '')), '');
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF v_goal IS NOT NULL AND v_goal NOT IN ('fill_seats', 'regular_crowd', 'try_idea', 'small_premium') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_GOAL');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;

  INSERT INTO event_host_meta (event_id, host_goal, updated_at)
  VALUES (p_event_id, v_goal, now())
  ON CONFLICT (event_id) DO UPDATE SET host_goal = EXCLUDED.host_goal, updated_at = now();

  RETURN jsonb_build_object('success', true, 'host_goal', v_goal);
END;
$$;
REVOKE ALL ON FUNCTION public.set_event_host_goal(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_event_host_goal(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_event_host_goal(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_event_host_goal(p_event_id text)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT m.host_goal
  FROM event_host_meta m
  JOIN events e ON e.id = m.event_id
  JOIN organizers o ON o.id = e.organizer_id
  WHERE m.event_id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid());
$$;
REVOKE ALL ON FUNCTION public.get_event_host_goal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_event_host_goal(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_event_host_goal(text) TO authenticated;

COMMIT;
