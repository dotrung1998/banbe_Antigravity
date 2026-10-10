-- 177: per-user rewards timezone (Phase 0, step 1) — EXPAND ONLY, backward compatible.
--
-- Before: one fixed zone (reward_rule_versions.rules.timezone = 'Asia/Ho_Chi_Minh') for the streak date and the
-- 10-events/month coin cap. That is wrong for US users (their "day" flipped at 09:00-13:00 local).
--
-- What changes, and what deliberately does NOT:
--  * New owner-only table reward_user_settings (tz NULL = legacy behaviour = Asia/Ho_Chi_Minh). Nobody is
--    migrated: a user with no row, or a NULL tz, gets byte-for-byte the previous behaviour.
--  * reward_ledger gets two NULLABLE columns, period_month + tz_used, stamped on NEW rows only. Existing rows stay
--    NULL and are read as "the month of created_at in Vietnam time" (the old rule). reward_active_days.local_date is
--    never recomputed or rewritten.
--  * Signatures of get_my_reward_summary / get_my_rewards / record_active_day / redeem_reward are unchanged.
--    get_my_rewards only ADDS the key `timezone_settings`; streak.timezone now reports the zone actually used.
--  * New RPC set_my_reward_timezone(text). A change takes effect from the START OF THE NEXT LOCAL DAY (in the
--    previously effective zone), at most 2 requests per rolling 30 days.
--
-- Cap month rule ("transition month"): the cap for the current month M counts every non-reversed coin-paying
-- attendance award whose month equals M, where a row's month is period_month if stamped, else the Vietnam-time month
-- of created_at. M itself is the current month in the user's effective zone. So a user who switches zone mid-month
-- keeps ONE counter for that calendar month; near the month boundary a row written under the old zone can fall into
-- the neighbouring month by up to the zone offset difference (a few hours, <= ~16 h VN<->US west coast). Accepted.
--
-- Streak across a change: nothing is deleted. Moving EAST (new offset > old offset) shortens the first local day
-- after the switch, so that one date is recorded as a "bridge" date: it keeps the run contiguous but is NOT counted
-- as an active day. Moving west repeats a date, which costs nothing. See rewards_streak_of.
--
-- ROLLBACK (data-safe): supabase/rollbacks/20261218000177_177_revert_user_timezone_functions.sql restores the 165
-- function bodies and drops the new RPC. It does NOT drop the table/columns (they are inert and nullable); users who
-- chose a zone simply go back to Vietnam-time day boundaries. Dropping the table would lose their choice, so don't.

-- ---------------------------------------------------------------------------
-- 1. Settings table (owner-only: RLS on, no client grants; clients use the RPCs)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rewards_tz_valid(p_tz text)
RETURNS boolean LANGUAGE sql STABLE SET search_path = public, pg_temp AS $$
  SELECT p_tz IS NOT NULL AND length(p_tz) <= 64 AND p_tz LIKE '%/%' AND p_tz !~ '^(posix|right)/'
         AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names n WHERE n.name = p_tz)
$$;

CREATE TABLE IF NOT EXISTS public.reward_user_settings (
  user_id         uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  tz              text,                 -- IANA zone; NULL = legacy default (Asia/Ho_Chi_Minh)
  pending_tz      text,                 -- requested zone, effective from pending_from_ts
  pending_from_ts timestamptz,
  pending_bridge  date,                 -- bridge date to add once the pending change is effective (eastward only)
  bridge_dates    date[] NOT NULL DEFAULT '{}',
  tz_changed_at   timestamptz[] NOT NULL DEFAULT '{}',
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reward_user_settings_pending_pair CHECK ((pending_tz IS NULL) = (pending_from_ts IS NULL))
);

CREATE OR REPLACE FUNCTION public.reward_user_settings_validate()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.tz IS NOT NULL AND NOT public.rewards_tz_valid(NEW.tz) THEN
    RAISE EXCEPTION 'invalid IANA timezone: %', NEW.tz USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF NEW.pending_tz IS NOT NULL AND NOT public.rewards_tz_valid(NEW.pending_tz) THEN
    RAISE EXCEPTION 'invalid IANA timezone: %', NEW.pending_tz USING ERRCODE = 'invalid_parameter_value';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS reward_user_settings_validate ON public.reward_user_settings;
CREATE TRIGGER reward_user_settings_validate BEFORE INSERT OR UPDATE ON public.reward_user_settings
  FOR EACH ROW EXECUTE FUNCTION public.reward_user_settings_validate();

ALTER TABLE public.reward_user_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reward_user_settings FROM anon, authenticated, PUBLIC;
DROP POLICY IF EXISTS reward_user_settings_owner_read ON public.reward_user_settings;
CREATE POLICY reward_user_settings_owner_read ON public.reward_user_settings FOR SELECT TO authenticated
  USING (user_id = auth.uid());  -- inert while no table grant exists; documents the intended scope

ALTER TABLE public.reward_ledger ADD COLUMN IF NOT EXISTS period_month date;
ALTER TABLE public.reward_ledger ADD COLUMN IF NOT EXISTS tz_used text;

-- ---------------------------------------------------------------------------
-- 2. Zone resolution (lazy: a pending change is "effective" once now() >= pending_from_ts)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rewards_user_tz(p_uid uuid, p_at timestamptz DEFAULT now())
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(
    (SELECT CASE WHEN s.pending_tz IS NOT NULL AND p_at >= s.pending_from_ts THEN s.pending_tz
                 ELSE COALESCE(s.tz, public.rewards_tz()) END
       FROM public.reward_user_settings s WHERE s.user_id = p_uid),
    public.rewards_tz())
$$;

CREATE OR REPLACE FUNCTION public.rewards_user_local_date(p_uid uuid, p_ts timestamptz)
RETURNS date LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT (p_ts AT TIME ZONE public.rewards_user_tz(p_uid, p_ts))::date
$$;

-- Coin-paying attendance awards in the current local month (user's zone), not reversed. Legacy rows (period_month
-- NULL) are placed in the month of created_at in the rules zone (Vietnam), exactly as before.
CREATE OR REPLACE FUNCTION public.rewards_month_paid_count(p_uid uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT count(*)::int FROM public.reward_ledger a
   WHERE a.user_id = p_uid AND a.entry_type = 'award' AND a.amount > 0 AND a.source_key LIKE 'attend:%'
     AND COALESCE(a.period_month, date_trunc('month', a.created_at AT TIME ZONE public.rewards_tz())::date)
         = date_trunc('month', now() AT TIME ZONE public.rewards_user_tz(p_uid))::date
     AND NOT EXISTS (SELECT 1 FROM public.reward_ledger r WHERE r.reverses_id = a.id)
$$;

CREATE OR REPLACE FUNCTION public.rewards_tz_settings(p_uid uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE s public.reward_user_settings%ROWTYPE; v_recent timestamptz[]; v_left int;
BEGIN
  SELECT * INTO s FROM public.reward_user_settings WHERE user_id = p_uid;
  SELECT COALESCE(array_agg(t ORDER BY t), '{}') INTO v_recent FROM unnest(COALESCE(s.tz_changed_at, '{}')) t WHERE t > now() - interval '30 days';
  v_left := GREATEST(0, 2 - COALESCE(cardinality(v_recent), 0));
  RETURN jsonb_build_object(
    'effective_tz', public.rewards_user_tz(p_uid),
    'chosen', s.user_id IS NOT NULL AND (s.tz IS NOT NULL OR s.pending_tz IS NOT NULL),
    'default_tz', public.rewards_tz(),
    'pending_tz', CASE WHEN s.pending_tz IS NOT NULL AND s.pending_from_ts > now() THEN s.pending_tz END,
    'pending_from', CASE WHEN s.pending_tz IS NOT NULL AND s.pending_from_ts > now() THEN s.pending_from_ts END,
    'changes_left', v_left,
    'next_change_at', CASE WHEN v_left = 0 THEN v_recent[1] + interval '30 days' END);
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Ledger: stamp month + zone on NEW rows (same signature as 165)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rewards_add_entry(
  p_uid uuid, p_type text, p_amount int, p_key text, p_reverses uuid, p_reason text, p_ref jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id uuid; v_tz text;
BEGIN
  PERFORM public.rewards_lock_user(p_uid);
  v_tz := public.rewards_user_tz(p_uid);
  INSERT INTO public.reward_ledger (user_id, entry_type, amount, source_key, reverses_id, rules_version, reason, ref, period_month, tz_used)
  VALUES (p_uid, p_type, p_amount, p_key, p_reverses, (public.rewards_rules() ->> 'version')::int, p_reason, COALESCE(p_ref, '{}'::jsonb),
          date_trunc('month', now() AT TIME ZONE v_tz)::date, v_tz)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Callers of the zone (bodies identical to 165 except the marked lines)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rewards_award_attendance(p_uid uuid, p_event text, p_cycle int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_rules jsonb := public.rewards_rules();
  v_coins int := COALESCE((v_rules ->> 'attendance_coins')::int, 0);
  v_cap int := COALESCE((v_rules ->> 'attendance_coin_cap_per_month')::int, 0);
  v_paid int; v_amount int; v_reason text := 'attendance';
BEGIN
  PERFORM public.rewards_lock_user(p_uid);
  v_paid := public.rewards_month_paid_count(p_uid);
  v_amount := v_coins;
  IF v_cap > 0 AND v_paid >= v_cap THEN v_amount := 0; v_reason := 'attendance_cap'; END IF;
  PERFORM public.rewards_add_entry(p_uid, 'award', v_amount, 'attend:' || p_event || ':' || p_cycle, NULL, v_reason,
                                   jsonb_build_object('event_id', p_event, 'cycle', p_cycle));
END;
$$;

CREATE OR REPLACE FUNCTION public.rewards_validate_attendance(p_uid uuid, p_event text, p_booking uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_prev public.reward_attendances%ROWTYPE; v_cycle int; v_owner uuid;
BEGIN
  PERFORM public.rewards_lock_user(p_uid);
  SELECT * INTO v_prev FROM public.reward_attendances WHERE user_id = p_uid AND event_id = p_event FOR UPDATE;
  IF FOUND AND v_prev.valid THEN RETURN; END IF; -- already valid through another source
  IF FOUND THEN
    v_cycle := v_prev.cycles + 1;
    UPDATE public.reward_attendances
       SET valid = true, cycles = v_cycle, booking_id = p_booking, last_changed_at = now()
     WHERE user_id = p_uid AND event_id = p_event;
  ELSE
    v_cycle := 1;
    INSERT INTO public.reward_attendances (user_id, event_id, booking_id, cat_key, valid, cycles)
    VALUES (p_uid, p_event, p_booking, (SELECT e.cat_key FROM public.events e WHERE e.id = p_event), true, 1);
  END IF;
  PERFORM public.rewards_award_attendance(p_uid, p_event, v_cycle);
  INSERT INTO public.reward_active_days (user_id, local_date, source)
  VALUES (p_uid, public.rewards_user_local_date(p_uid, now()), 'attendance') ON CONFLICT DO NOTHING;
  PERFORM public.rewards_refresh_badges(p_uid);
  FOR v_owner IN SELECT public.rewards_event_owner_ids(p_event) LOOP PERFORM public.rewards_refresh_badges(v_owner); END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_active_day(p_source text, p_ref text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_saved timestamptz;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  IF p_source IS DISTINCT FROM 'save' THEN RETURN jsonb_build_object('success', false, 'error', 'UNSUPPORTED_SOURCE'); END IF;
  SELECT created_at INTO v_saved FROM public.favorites WHERE user_id = v_uid AND event_id = p_ref;
  IF v_saved IS NULL OR v_saved < now() - interval '36 hours' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_VERIFIED');
  END IF;
  INSERT INTO public.reward_active_days (user_id, local_date, source)
  VALUES (v_uid, public.rewards_user_local_date(v_uid, v_saved), 'save') ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('success', true, 'streak', public.rewards_streak_of(v_uid) -> 'current');
END;
$$;

-- Streak: same output keys as 165. Differences: dates are the user's zone; bridge dates (set only by an eastward
-- zone change) keep a run contiguous without counting as active days. With no settings row the CTE is exactly the
-- old query over reward_active_days.
CREATE OR REPLACE FUNCTION public.rewards_streak_of(p_uid uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_tz text := public.rewards_user_tz(p_uid);
  v_today date := public.rewards_user_local_date(p_uid, now());
  v_last date; v_lastd date; v_cur int := 0; v_best int := 0; v_bridges date[];
BEGIN
  SELECT COALESCE(s.bridge_dates, '{}') || CASE WHEN s.pending_bridge IS NOT NULL AND s.pending_from_ts <= now() THEN ARRAY[s.pending_bridge] ELSE '{}'::date[] END
    INTO v_bridges FROM public.reward_user_settings s WHERE s.user_id = p_uid;
  v_bridges := COALESCE(v_bridges, '{}');
  SELECT max(local_date) INTO v_last FROM public.reward_active_days WHERE user_id = p_uid;
  WITH days AS (
    SELECT local_date AS d, false AS bridge FROM public.reward_active_days WHERE user_id = p_uid
    UNION ALL
    SELECT b, true FROM unnest(v_bridges) b
     WHERE b <= v_today AND NOT EXISTS (SELECT 1 FROM public.reward_active_days a WHERE a.user_id = p_uid AND a.local_date = b)),
  g AS (SELECT d, bridge, d - (row_number() OVER (ORDER BY d))::int AS grp FROM days)
  SELECT max(d) INTO v_lastd FROM g;
  IF v_lastd IS NOT NULL AND v_lastd >= v_today - 1 THEN
    -- A streak is alive through yesterday: not having acted yet today costs nothing.
    WITH days AS (
      SELECT local_date AS d, false AS bridge FROM public.reward_active_days WHERE user_id = p_uid
      UNION ALL
      SELECT b, true FROM unnest(v_bridges) b
       WHERE b <= v_today AND NOT EXISTS (SELECT 1 FROM public.reward_active_days a WHERE a.user_id = p_uid AND a.local_date = b)),
    g AS (SELECT d, bridge, d - (row_number() OVER (ORDER BY d))::int AS grp FROM days)
    SELECT count(*) FILTER (WHERE NOT bridge) INTO v_cur FROM g WHERE g.grp = (SELECT g2.grp FROM g g2 ORDER BY g2.d DESC LIMIT 1);
  END IF;
  WITH days AS (
    SELECT local_date AS d, false AS bridge FROM public.reward_active_days WHERE user_id = p_uid
    UNION ALL
    SELECT b, true FROM unnest(v_bridges) b
     WHERE b <= v_today AND NOT EXISTS (SELECT 1 FROM public.reward_active_days a WHERE a.user_id = p_uid AND a.local_date = b)),
  g AS (SELECT d, bridge, d - (row_number() OVER (ORDER BY d))::int AS grp FROM days)
  SELECT COALESCE(max(n), 0) INTO v_best FROM (SELECT count(*) FILTER (WHERE NOT bridge) AS n FROM g GROUP BY grp) x;
  RETURN jsonb_build_object('current', v_cur, 'longest', v_best, 'last_active_date', v_last,
                            'active_today', COALESCE(v_last = v_today, false), 'timezone', v_tz);
END;
$$;
CREATE OR REPLACE FUNCTION public.get_my_rewards()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid(); v_rules jsonb := public.rewards_rules(); v_counts jsonb;
  v_badges jsonb; v_hist jsonb; v_cat jsonb; v_paid int;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  v_counts := public.rewards_badge_counts(v_uid);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'code', d.code, 'title_vi', d.title_vi, 'title_en', d.title_en, 'desc_vi', d.desc_vi, 'desc_en', d.desc_en,
           'target', d.target,
           'progress', LEAST(public.rewards_badge_progress_of(d.code, v_counts), d.target),
           'earned', (b.badge_code IS NOT NULL AND b.revoked_at IS NULL),
           'earned_at', CASE WHEN b.revoked_at IS NULL THEN b.earned_at END) ORDER BY d.sort), '[]'::jsonb)
    INTO v_badges
    FROM public.reward_badge_defs d
    LEFT JOIN public.reward_user_badges b ON b.badge_code = d.code AND b.user_id = v_uid;

  SELECT COALESCE(jsonb_agg(h ORDER BY (h ->> 'created_at') DESC), '[]'::jsonb) INTO v_hist FROM (
    SELECT jsonb_build_object('id', l.id, 'type', l.entry_type, 'amount', l.amount, 'reason', l.reason,
                              'created_at', l.created_at, 'event_name', e.name, 'item_code', l.ref ->> 'item_code') AS h
      FROM public.reward_ledger l LEFT JOIN public.events e ON e.id = l.ref ->> 'event_id'
     WHERE l.user_id = v_uid ORDER BY l.created_at DESC LIMIT 40) x;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('code', c.code, 'kind', c.kind, 'design_id', c.design_id,
                                               'price', c.price, 'unlocked', u.user_id IS NOT NULL) ORDER BY c.sort), '[]'::jsonb)
    INTO v_cat FROM public.reward_catalog c
    LEFT JOIN public.reward_unlocks u ON u.item_code = c.code AND u.user_id = v_uid WHERE c.active;

  v_paid := public.rewards_month_paid_count(v_uid);

  RETURN jsonb_build_object(
    'success', true, 'balance', public.rewards_balance(v_uid), 'rules', v_rules,
    'streak', public.rewards_streak_of(v_uid), 'badges', v_badges, 'history', v_hist, 'catalog', v_cat,
    'attendance_paid_this_month', v_paid,
    'timezone_settings', public.rewards_tz_settings(v_uid));
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. set_my_reward_timezone: the only writer of reward_user_settings
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_my_reward_timezone(p_tz text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid(); s public.reward_user_settings%ROWTYPE; v_cur text; v_t timestamptz;
  v_recent timestamptz[]; v_bridge date;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  IF NOT public.rewards_tz_valid(p_tz) THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_TIMEZONE'); END IF;
  PERFORM public.rewards_lock_user(v_uid);

  INSERT INTO public.reward_user_settings (user_id) VALUES (v_uid) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO s FROM public.reward_user_settings WHERE user_id = v_uid FOR UPDATE;
  -- Materialise a pending change that has already taken effect (and keep its bridge date).
  IF s.pending_tz IS NOT NULL AND s.pending_from_ts <= now() THEN
    s.tz := s.pending_tz;
    IF s.pending_bridge IS NOT NULL THEN s.bridge_dates := s.bridge_dates || s.pending_bridge; END IF;
    s.pending_tz := NULL; s.pending_from_ts := NULL; s.pending_bridge := NULL;
  END IF;
  v_cur := COALESCE(s.tz, public.rewards_tz());

  IF p_tz = v_cur THEN
    -- Back to the zone already in force: cancels a not-yet-effective request, costs nothing (its count is refunded).
    UPDATE public.reward_user_settings
       SET tz = s.tz, pending_tz = NULL, pending_from_ts = NULL, pending_bridge = NULL, bridge_dates = s.bridge_dates,
           tz_changed_at = CASE WHEN s.pending_tz IS NOT NULL AND cardinality(s.tz_changed_at) > 0
                                THEN s.tz_changed_at[1:cardinality(s.tz_changed_at) - 1] ELSE s.tz_changed_at END,
           updated_at = now()
     WHERE user_id = v_uid;
    RETURN jsonb_build_object('success', true, 'changed', false, 'timezone_settings', public.rewards_tz_settings(v_uid));
  END IF;

  SELECT COALESCE(array_agg(t ORDER BY t), '{}') INTO v_recent FROM unnest(s.tz_changed_at) t WHERE t > now() - interval '30 days';
  -- Replacing a request that has not taken effect yet (fixing a mis-tap) is the same change: no extra count, no limit.
  IF s.pending_tz IS NULL AND cardinality(v_recent) >= 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'TZ_CHANGE_LIMIT',
                              'next_change_at', v_recent[1] + interval '30 days');
  END IF;

  -- Effective from the start of the NEXT local day in the zone currently in force.
  v_t := ((now() AT TIME ZONE v_cur)::date + 1)::timestamp AT TIME ZONE v_cur;
  -- Eastward (new offset > old offset at that instant): the first new-zone day is shorter -> bridge it.
  v_bridge := CASE WHEN (v_t AT TIME ZONE p_tz) - (v_t AT TIME ZONE 'UTC') > (v_t AT TIME ZONE v_cur) - (v_t AT TIME ZONE 'UTC')
                   THEN (v_t AT TIME ZONE p_tz)::date END;

  UPDATE public.reward_user_settings
     SET tz = s.tz, bridge_dates = s.bridge_dates, pending_tz = p_tz, pending_from_ts = v_t, pending_bridge = v_bridge,
         tz_changed_at = CASE WHEN s.pending_tz IS NULL THEN v_recent || now() ELSE s.tz_changed_at END, updated_at = now()
   WHERE user_id = v_uid;
  RETURN jsonb_build_object('success', true, 'changed', true, 'timezone_settings', public.rewards_tz_settings(v_uid));
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Privileges
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['rewards_user_tz(uuid,timestamptz)','rewards_user_local_date(uuid,timestamptz)',
                           'rewards_month_paid_count(uuid)','rewards_tz_settings(uuid)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM anon, authenticated, PUBLIC', f);
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.set_my_reward_timezone(text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_my_reward_timezone(text) TO authenticated;
