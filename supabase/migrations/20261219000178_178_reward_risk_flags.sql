-- 178: host–friend fraud signals for rewards (Phase 0, step 2) — DETECT AND FLAG ONLY. Flag OFF by default.
--
-- Findings about check_in_guest (migration 151, still the live definition; 007/021/132/133 are older versions):
--   * NO time-window constraint: it never compares now() with events.starts_at (events have no end time at all).
--   * NO distance/location constraint: no coordinates are sent or checked.
--   * Only gates: caller is the event's organizer owner/user or a platform admin (accepted team members cannot
--     check in), the booking is 'confirmed'/'attended', and one check_ins row per booking.
--   So a host can confirm anyone, at any time, from anywhere. This migration does NOT change that.
--
-- What this adds (all new objects; check_in_guest, the ledger, bookings and hosts are untouched):
--   * reward_risk_config: single row, `enabled` DEFAULT false, thresholds in jsonb (NOT hard-coded in code).
--   * reward_risk_flags: admin-readable flags. A flag is a review prompt, nothing more.
--   * Admin-only RPCs: preview (writes NOTHING, works even while disabled — use it to measure on real data
--     before enabling), run scan (writes ONLY when enabled), list, review (open/dismissed/confirmed + note),
--     get/set config.
--   * No trigger on check_ins: the scan is pulled by an admin, so the check-in path cannot be slowed or broken.
--   * Reversing coins stays what it was: an admin-triggered `reversal` ledger row via existing tooling. Nothing
--     here revokes coins, blocks a host, or notifies anybody.
--
-- Signals (all computed from reward_attendances valid=true, i.e. already excluding owner/team/self/cancelled
-- and undone check-ins, plus check_ins for time):
--   repeat_guests  host: >= min attendees AND >= min host events AND share of attendees who attended >= N of
--                  that host's events is >= ratio.
--   new_accounts   host: >= K accounts created < D days before their first attendance with this host that each
--                  attended >= N of that host's events.
--   off_window     event: >= M check-ins and a share >= ratio recorded outside [starts_at - B h, starts_at + A h].
--   shared_phone   host: >= 2 attendee accounts with the same profiles.phone (no device data exists; auth.users
--                  phone is normally unique, so expect ~0 hits — kept because profiles.phone has no unique index).
-- Thresholds below are UNCALIBRATED placeholders (the real data has 0 check-ins at 2026-10-10). Expect false
-- positives for genuine regular communities (a host whose friends really attend every week) — that is why flags
-- only ask an admin to look.
--
-- ROLLBACK (data-safe): leave the tables; set enabled=false (set_reward_risk_config) and the feature is inert.
-- If the tables must go: supabase/rollbacks/20261219000178_178_revert_reward_risk.sql drops them (loses only flags).

CREATE TABLE IF NOT EXISTS public.reward_risk_config (
  id          int PRIMARY KEY CHECK (id = 1),
  enabled     boolean NOT NULL DEFAULT false,
  version     int NOT NULL DEFAULT 1,
  thresholds  jsonb NOT NULL DEFAULT '{}'::jsonb,   -- overrides on top of rewards_risk_defaults()
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);
INSERT INTO public.reward_risk_config (id, enabled) VALUES (1, false) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.reward_risk_flags (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dedupe_key     text NOT NULL UNIQUE,
  flag_type      text NOT NULL CHECK (flag_type IN ('repeat_guests', 'new_accounts', 'off_window', 'shared_phone')),
  organizer_id   text REFERENCES public.organizers(id) ON DELETE CASCADE,
  event_id       text,
  metrics        jsonb NOT NULL DEFAULT '{}'::jsonb,   -- counts + affected account ids; admin-only
  config_version int NOT NULL,
  status         text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'dismissed', 'confirmed')),
  review_note    text NOT NULL DEFAULT '',
  reviewed_by    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at    timestamptz,
  first_seen_at  timestamptz NOT NULL DEFAULT now(),
  last_seen_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS reward_risk_flags_status ON public.reward_risk_flags (status, last_seen_at DESC);

ALTER TABLE public.reward_risk_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reward_risk_flags ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reward_risk_config, public.reward_risk_flags FROM anon, authenticated, PUBLIC;

CREATE OR REPLACE FUNCTION public.rewards_risk_defaults()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'window_days', 90,
    'repeat_min_attendees', 5, 'repeat_min_host_events', 3, 'repeat_min_events_per_guest', 3, 'repeat_ratio', 0.8,
    'new_account_days', 14, 'new_account_min_events', 3, 'new_account_cluster_min', 3,
    'off_before_hours', 3, 'off_after_hours', 12, 'off_min_checkins', 3, 'off_ratio', 0.5,
    'shared_phone_min_accounts', 2)
$$;

CREATE OR REPLACE FUNCTION public.rewards_risk_cfg()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT public.rewards_risk_defaults() || COALESCE((SELECT thresholds FROM public.reward_risk_config WHERE id = 1), '{}'::jsonb)
$$;

-- Pure computation: returns candidate flags, writes nothing.
CREATE OR REPLACE FUNCTION public.rewards_risk_compute()
RETURNS TABLE (flag_type text, organizer_id text, event_id text, metrics jsonb, dedupe_key text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE c jsonb := public.rewards_risk_cfg();
BEGIN
  RETURN QUERY
  WITH base AS (
    SELECT ra.user_id, ra.event_id, e.organizer_id, ra.first_valid_at, ci.checked_in_at, e.starts_at,
           p.created_at AS acct_created, NULLIF(btrim(p.phone), '') AS phone
      FROM public.reward_attendances ra
      JOIN public.events e ON e.id = ra.event_id
      LEFT JOIN public.check_ins ci ON ci.booking_id = ra.booking_id
      LEFT JOIN public.profiles p ON p.id = ra.user_id
     WHERE ra.valid AND e.organizer_id IS NOT NULL
       AND COALESCE(ci.checked_in_at, ra.first_valid_at) >= now() - ((c ->> 'window_days')::int * interval '1 day')),
  pair AS (
    SELECT b.organizer_id AS org, b.user_id AS uid, count(DISTINCT b.event_id) AS n,
           min(b.first_valid_at) AS first_att, min(b.acct_created) AS acct_created
      FROM base b GROUP BY b.organizer_id, b.user_id),
  hostev AS (SELECT b.organizer_id AS org, count(DISTINCT b.event_id) AS events FROM base b GROUP BY b.organizer_id),
  s1 AS (
    SELECT pr.org, count(*) AS attendees,
           count(*) FILTER (WHERE pr.n >= (c ->> 'repeat_min_events_per_guest')::int) AS repeaters, h.events AS host_events
      FROM pair pr JOIN hostev h ON h.org = pr.org GROUP BY pr.org, h.events),
  s2 AS (
    SELECT pr.org, count(*) AS accounts, jsonb_agg(pr.uid) AS uids
      FROM pair pr
     WHERE pr.n >= (c ->> 'new_account_min_events')::int AND pr.acct_created IS NOT NULL
       AND pr.acct_created >= pr.first_att - ((c ->> 'new_account_days')::int * interval '1 day')
     GROUP BY pr.org),
  s3 AS (
    SELECT b.event_id AS ev, b.organizer_id AS org, count(*) AS total,
           count(*) FILTER (WHERE b.checked_in_at < b.starts_at - ((c ->> 'off_before_hours')::int * interval '1 hour')
                               OR b.checked_in_at > b.starts_at + ((c ->> 'off_after_hours')::int * interval '1 hour')) AS off
      FROM base b WHERE b.checked_in_at IS NOT NULL AND b.starts_at IS NOT NULL GROUP BY b.event_id, b.organizer_id),
  s4 AS (
    SELECT b.organizer_id AS org, md5(b.phone) AS ph, count(DISTINCT b.user_id) AS accounts, jsonb_agg(DISTINCT b.user_id) AS uids
      FROM base b WHERE b.phone IS NOT NULL GROUP BY b.organizer_id, md5(b.phone)
     HAVING count(DISTINCT b.user_id) >= (c ->> 'shared_phone_min_accounts')::int)
  SELECT 'repeat_guests'::text, s1.org, NULL::text,
         jsonb_build_object('attendees', s1.attendees, 'repeaters', s1.repeaters, 'host_events', s1.host_events,
                            'ratio', round(s1.repeaters::numeric / s1.attendees, 3)),
         'repeat_guests:' || s1.org
    FROM s1
   WHERE s1.attendees >= (c ->> 'repeat_min_attendees')::int AND s1.host_events >= (c ->> 'repeat_min_host_events')::int
     AND s1.repeaters::numeric / s1.attendees >= (c ->> 'repeat_ratio')::numeric
  UNION ALL
  SELECT 'new_accounts', s2.org, NULL, jsonb_build_object('accounts', s2.accounts, 'user_ids', s2.uids), 'new_accounts:' || s2.org
    FROM s2 WHERE s2.accounts >= (c ->> 'new_account_cluster_min')::int
  UNION ALL
  SELECT 'off_window', s3.org, s3.ev, jsonb_build_object('checkins', s3.total, 'off_window', s3.off,
                                                         'ratio', round(s3.off::numeric / s3.total, 3)), 'off_window:' || s3.ev
    FROM s3 WHERE s3.off >= (c ->> 'off_min_checkins')::int AND s3.off::numeric / s3.total >= (c ->> 'off_ratio')::numeric
  UNION ALL
  SELECT 'shared_phone', s4.org, NULL, jsonb_build_object('accounts', s4.accounts, 'user_ids', s4.uids), 'shared_phone:' || s4.org || ':' || s4.ph
    FROM s4;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reward_risk_preview()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_out jsonb;
BEGIN
  IF NOT public.is_platform_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_ADMIN'); END IF;
  SELECT jsonb_build_object('success', true, 'written', 0, 'enabled', (SELECT enabled FROM public.reward_risk_config WHERE id = 1),
           'would_flag', (SELECT count(*) FROM public.rewards_risk_compute()),
           'by_type', COALESCE((SELECT jsonb_object_agg(t, n) FROM (SELECT flag_type AS t, count(*) AS n FROM public.rewards_risk_compute() GROUP BY flag_type) x), '{}'::jsonb),
           'config', public.rewards_risk_cfg())
    INTO v_out;
  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_run_reward_risk_scan()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_cfg public.reward_risk_config%ROWTYPE; v_n int;
BEGIN
  IF NOT public.is_platform_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_ADMIN'); END IF;
  SELECT * INTO v_cfg FROM public.reward_risk_config WHERE id = 1;
  IF v_cfg.enabled IS NOT TRUE THEN RETURN jsonb_build_object('success', true, 'enabled', false, 'written', 0); END IF;
  WITH ins AS (
    INSERT INTO public.reward_risk_flags (dedupe_key, flag_type, organizer_id, event_id, metrics, config_version)
    SELECT c.dedupe_key, c.flag_type, c.organizer_id, c.event_id, c.metrics, v_cfg.version FROM public.rewards_risk_compute() c
    ON CONFLICT (dedupe_key) DO UPDATE
      SET metrics = EXCLUDED.metrics, last_seen_at = now(), config_version = EXCLUDED.config_version
      WHERE public.reward_risk_flags.status = 'open'      -- a dismissed/confirmed flag is never reopened or rewritten
    RETURNING 1)
  SELECT count(*) INTO v_n FROM ins;
  RETURN jsonb_build_object('success', true, 'enabled', true, 'written', v_n);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_reward_risk_flags(p_status text DEFAULT 'open', p_limit int DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_ADMIN'); END IF;
  RETURN jsonb_build_object('success', true, 'flags', COALESCE((
    SELECT jsonb_agg(to_jsonb(f) - 'dedupe_key' ORDER BY f.last_seen_at DESC)
      FROM (SELECT * FROM public.reward_risk_flags WHERE status = p_status ORDER BY last_seen_at DESC LIMIT LEAST(GREATEST(p_limit, 1), 200)) f), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_review_reward_risk_flag(p_id uuid, p_status text, p_note text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_ADMIN'); END IF;
  IF p_status NOT IN ('open', 'dismissed', 'confirmed') THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATUS'); END IF;
  -- Bookkeeping only: this never touches the ledger, bookings, check-ins or the host.
  UPDATE public.reward_risk_flags SET status = p_status, review_note = left(COALESCE(p_note, ''), 1000), reviewed_by = auth.uid(), reviewed_at = now()
   WHERE id = p_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND'); END IF;
  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_reward_risk_config()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_ADMIN'); END IF;
  RETURN jsonb_build_object('success', true, 'enabled', (SELECT enabled FROM public.reward_risk_config WHERE id = 1),
                            'version', (SELECT version FROM public.reward_risk_config WHERE id = 1), 'config', public.rewards_risk_cfg(),
                            'calibrated', false);
END;
$$;

-- p_thresholds: partial override; every key must be a known one with a positive number (ratios in (0,1]).
CREATE OR REPLACE FUNCTION public.admin_set_reward_risk_config(p_enabled boolean DEFAULT NULL, p_thresholds jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE k text; v jsonb; v_known jsonb := public.rewards_risk_defaults();
BEGIN
  IF NOT public.is_platform_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_ADMIN'); END IF;
  IF p_thresholds IS NOT NULL THEN
    IF jsonb_typeof(p_thresholds) <> 'object' THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_THRESHOLDS'); END IF;
    FOR k, v IN SELECT * FROM jsonb_each(p_thresholds) LOOP
      IF NOT (v_known ? k) OR jsonb_typeof(v) <> 'number' OR (v #>> '{}')::numeric <= 0
         OR (k LIKE '%ratio' AND (v #>> '{}')::numeric > 1) OR (v #>> '{}')::numeric > 100000 THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_THRESHOLDS', 'key', k);
      END IF;
    END LOOP;
  END IF;
  UPDATE public.reward_risk_config
     SET enabled = COALESCE(p_enabled, enabled),
         thresholds = CASE WHEN p_thresholds IS NULL THEN thresholds ELSE thresholds || p_thresholds END,
         version = version + CASE WHEN p_thresholds IS NULL THEN 0 ELSE 1 END,
         updated_at = now(), updated_by = auth.uid()
   WHERE id = 1;
  RETURN jsonb_build_object('success', true, 'enabled', (SELECT enabled FROM public.reward_risk_config WHERE id = 1));
END;
$$;

DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['rewards_risk_defaults()','rewards_risk_cfg()','rewards_risk_compute()'] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM anon, authenticated, PUBLIC', f);
  END LOOP;
  FOREACH f IN ARRAY ARRAY['admin_reward_risk_preview()','admin_run_reward_risk_scan()','admin_list_reward_risk_flags(text,int)',
                           'admin_review_reward_risk_flag(uuid,text,text)','admin_get_reward_risk_config()','admin_set_reward_risk_config(boolean,jsonb)'] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM anon, PUBLIC', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated', f);   -- each one re-checks is_platform_admin()
  END LOOP;
END $$;
