-- 192: Rewards v2 (Phase 1) — weekly streak with earned grace weeks and repair-by-attending, tiered + seasonal
-- badges, "next badge", and a self-chosen monthly outing goal. Builds on 165, 177-180 and 191. EXPAND ONLY.
--
-- Why weeks: banbe is an offline-event app. A daily streak rewards opening the app, not going out; Strava's weekly
-- streak (1 activity per Mon-Sun week) is the closer fit. What keeps a week alive is unchanged from 165: ANY verified
-- active day in it (a server-verified save or a host-confirmed attendance) — the low bar that won Duolingo's test.
--
-- Everything new is DERIVED from rows that already exist (reward_active_days, reward_attendances): no new write
-- path, no backfill, no ledger rows. Streaks and goals never pay coins.
--
--  * Week = Monday-Sunday in the user's rewards timezone (177). The current week is never a miss while it is open.
--  * Grace weeks (earned, never bought): every `grace_every` (4) active weeks earn one, at most `grace_max` (2) held.
--    A finished week with no activity uses one automatically; the streak keeps its length (not extended).
--  * Repair: a streak of >= `repair_min_weeks` (4) that breaks can be restored by a host-confirmed attendance
--    (still valid) within `repair_days` (14) after the missed week ended. Saves cannot repair. One window per break.
--  * Not retroactive: grace accrues and repairs open only from week_streak.start (the day this migration ran);
--    history before that behaves exactly like a plain weekly count.
--  * Tiered badges: reward_badge_defs gets family / tier / metric / starts_on / ends_on / v2. The 6 existing codes are
--    kept as tier 1-3 of their families (no rename, no revocation, earned_at kept). New defs are v2 = true and are
--    returned to clients only while app_feature_flags.rewards_v2 is on; they are still earned/revoked silently, so
--    turning v2 on shows the right state. Seasonal badges count attendances at events STARTING in their window and
--    are only listed while the window is near/open or once earned (no countdowns, no "last chance" copy).
--  * Monthly goal: reward_user_settings.monthly_goal in (1, 2, 4) via set_my_outing_goal(int); progress = valid
--    attendances checked in this local month. No coins and no badge for meeting it (a goal you can lower after the
--    fact would make a "goals met" badge gameable).
--  * New switch 'rewards_v2' (seeded OFF; missing = off on the clients). Writes of v2 data refuse while it is off.
--  * Payloads: get_my_rewards ADDS week_streak, next_badge, goal and per-badge family/tier/starts_on/ends_on;
--    get_my_reward_summary ADDS week_streak + week_active. Every old key is unchanged (daily `streak` stays for builds
--    already in the field).
--
-- ROLLBACK: supabase/rollbacks/20261228000192_192_revert_rewards_v2.sql (restores 191's bodies, reactivates rules v2,
-- drops the v2 badge rows/defs, the new columns, functions and the switch). No ledger row is touched.

-- ---------------------------------------------------------------------------
-- 0. Switch + rules version 3
-- ---------------------------------------------------------------------------
ALTER TABLE public.app_feature_flags DROP CONSTRAINT IF EXISTS app_feature_flags_key_known;
ALTER TABLE public.app_feature_flags ADD CONSTRAINT app_feature_flags_key_known
  CHECK (key IN ('rewards', 'admin_event_wipe', 'rewards_v2'));
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('rewards_v2', false) ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_set_feature_flag(p_key text, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_enabled IS NULL OR p_key IS NULL OR p_key NOT IN ('rewards', 'admin_event_wipe', 'rewards_v2') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  INSERT INTO public.app_feature_flags (key, enabled, updated_by, updated_at)
  VALUES (p_key, p_enabled, v_admin, now())
  ON CONFLICT (key) DO UPDATE SET enabled = excluded.enabled, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  INSERT INTO public.app_feature_flags_audit (admin_id, key, enabled) VALUES (v_admin, p_key, p_enabled);
  RETURN jsonb_build_object('success', true, 'key', p_key, 'enabled', p_enabled);
END;
$$;

INSERT INTO public.reward_rule_versions (version, is_active, rules, notes)
SELECT 3, false,
       r.rules || jsonb_build_object('week_streak', jsonb_build_object(
         'grace_every', 4, 'grace_max', 2, 'repair_min_weeks', 4, 'repair_days', 14,
         'start', to_char((now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM-DD'))),
       '192: weekly streak (any active day keeps a Mon-Sun week), earned grace weeks, repair by attending'
  FROM public.reward_rule_versions r WHERE r.is_active
ON CONFLICT (version) DO NOTHING;
UPDATE public.reward_rule_versions SET is_active = false WHERE is_active AND version <> 3;
UPDATE public.reward_rule_versions SET is_active = true WHERE version = 3;

-- ---------------------------------------------------------------------------
-- 1. Weekly streak (derived)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rewards_week_streak_of(p_uid uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  c jsonb := COALESCE(public.rewards_rules() -> 'week_streak', '{}'::jsonb);
  v_every int := GREATEST(COALESCE((c ->> 'grace_every')::int, 4), 1);
  v_max int := GREATEST(COALESCE((c ->> 'grace_max')::int, 2), 0);
  v_rmin int := GREATEST(COALESCE((c ->> 'repair_min_weeks')::int, 4), 1);
  v_rdays int := GREATEST(COALESCE((c ->> 'repair_days')::int, 14), 0);
  v_start date := date_trunc('week', COALESCE((c ->> 'start')::date, now()::date))::date;
  v_today date := public.rewards_user_local_date(p_uid, now());
  v_this date := date_trunc('week', v_today)::date;
  v_weeks date[]; v_att date[]; w date;
  v_cur int := 0; v_best int := 0; v_held int := 0; v_since int := 0; v_used int := 0; v_repaired int := 0;
  v_pend_len int := 0; v_pend_until date;
BEGIN
  SELECT array_agg(DISTINCT date_trunc('week', d.local_date)::date) INTO v_weeks
    FROM public.reward_active_days d WHERE d.user_id = p_uid AND d.local_date <= v_today;
  -- Repair needs an attendance that is still valid (an undone or cancelled one cannot repair anything).
  SELECT array_agg(public.rewards_user_local_date(p_uid, a.first_valid_at)) INTO v_att
    FROM public.reward_attendances a WHERE a.user_id = p_uid AND a.valid;
  v_weeks := COALESCE(v_weeks, '{}'); v_att := COALESCE(v_att, '{}');

  IF cardinality(v_weeks) > 0 THEN
    w := (SELECT min(x) FROM unnest(v_weeks) x);
    WHILE w <= v_this LOOP
      IF v_pend_until IS NOT NULL AND w >= v_pend_until THEN v_pend_until := NULL; v_pend_len := 0; END IF;
      IF w = ANY (v_weeks) THEN
        IF v_pend_until IS NOT NULL
           AND EXISTS (SELECT 1 FROM unnest(v_att) d WHERE d >= w AND d < w + 7 AND d < v_pend_until) THEN
          v_cur := v_pend_len + v_cur; v_repaired := v_repaired + 1; v_pend_until := NULL; v_pend_len := 0;
        END IF;
        v_cur := v_cur + 1;
        IF w >= v_start THEN
          v_since := v_since + 1;
          IF v_since >= v_every THEN
            v_since := 0;
            IF v_held < v_max THEN v_held := v_held + 1; END IF;
          END IF;
        END IF;
        v_best := GREATEST(v_best, v_cur);
      ELSIF w < v_this THEN
        -- A finished week with nothing in it.
        IF v_cur > 0 AND v_held > 0 AND w >= v_start THEN
          v_held := v_held - 1; v_used := v_used + 1;          -- a grace week covers it; the streak keeps its length
        ELSIF v_cur > 0 THEN
          IF v_cur >= v_rmin AND w >= v_start THEN v_pend_len := v_cur; v_pend_until := w + 7 + v_rdays; END IF;
          v_cur := 0; v_since := 0;
        END IF;
      END IF;
      w := w + 7;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'unit', 'week', 'current', v_cur, 'longest', v_best,
    'this_week_active', v_this = ANY (v_weeks), 'week_start', v_this,
    'grace_held', v_held, 'grace_max', v_max, 'grace_every', v_every, 'grace_used', v_used,
    'next_grace_in', CASE WHEN v_held >= v_max THEN NULL ELSE v_every - v_since END,
    'repair', CASE WHEN v_pend_until IS NOT NULL AND v_pend_until > v_today
                   THEN jsonb_build_object('weeks', v_pend_len, 'until', v_pend_until - 1) END,
    'repaired', v_repaired, 'timezone', public.rewards_user_tz(p_uid));
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Tiered + seasonal badges
-- ---------------------------------------------------------------------------
ALTER TABLE public.reward_badge_defs
  ADD COLUMN IF NOT EXISTS family text,
  ADD COLUMN IF NOT EXISTS tier smallint,
  ADD COLUMN IF NOT EXISTS metric text,
  ADD COLUMN IF NOT EXISTS starts_on date,
  ADD COLUMN IF NOT EXISTS ends_on date,
  ADD COLUMN IF NOT EXISTS v2 boolean NOT NULL DEFAULT false;

UPDATE public.reward_badge_defs SET family = x.family, tier = x.tier, metric = x.metric, sort = x.sort
  FROM (VALUES ('ready_to_explore', 'start', 1, 'ready_to_explore', 10),
               ('first_outing', 'outings', 1, 'attended', 20),
               ('regular', 'outings', 2, 'attended', 21),
               ('community_regular', 'outings', 3, 'attended', 22),
               ('explorer', 'explorer', 1, 'categories', 40),
               ('host_milestone', 'host', 1, 'hosted', 60)) AS x(code, family, tier, metric, sort)
 WHERE reward_badge_defs.code = x.code;

INSERT INTO public.reward_badge_defs (code, sort, target, title_vi, title_en, desc_vi, desc_en, family, tier, metric, starts_on, ends_on, v2) VALUES
  ('outings_25', 23, 25, 'Người của cộng đồng', 'Community pillar', 'Tham dự 25 sự kiện khác nhau.', 'Attend 25 different events.', 'outings', 4, 'attended', NULL, NULL, true),
  ('outings_50', 24, 50, 'Huyền thoại banbe', 'banbe legend', 'Tham dự 50 sự kiện khác nhau.', 'Attend 50 different events.', 'outings', 5, 'attended', NULL, NULL, true),
  ('explorer_6', 41, 6, 'Nhà thám hiểm', 'Adventurer', 'Tham dự sự kiện thuộc 6 danh mục khác nhau.', 'Attend events in 6 different categories.', 'explorer', 2, 'categories', NULL, NULL, true),
  ('explorer_10', 42, 10, 'Không gì là lạ', 'Seen it all', 'Tham dự sự kiện thuộc 10 danh mục khác nhau.', 'Attend events in 10 different categories.', 'explorer', 3, 'categories', NULL, NULL, true),
  ('months_3', 50, 3, 'Ba tháng ra ngoài', 'Three months out', 'Có sự kiện được xác nhận tham dự trong 3 tháng khác nhau (không cần liên tiếp).', 'Attend at least one event in 3 different months (they need not be in a row).', 'months', 1, 'outing_months', NULL, NULL, true),
  ('months_6', 51, 6, 'Nửa năm ra ngoài', 'Half a year out', 'Có sự kiện được xác nhận tham dự trong 6 tháng khác nhau (không cần liên tiếp).', 'Attend at least one event in 6 different months (they need not be in a row).', 'months', 2, 'outing_months', NULL, NULL, true),
  ('months_12', 52, 12, 'Một năm ra ngoài', 'A year out', 'Có sự kiện được xác nhận tham dự trong 12 tháng khác nhau (không cần liên tiếp).', 'Attend at least one event in 12 different months (they need not be in a row).', 'months', 3, 'outing_months', NULL, NULL, true),
  ('host_10', 61, 10, 'Người tổ chức quen thuộc', 'Trusted host', 'Hoàn thành 10 sự kiện có khách hợp lệ.', 'Complete 10 events with legitimate attendees.', 'host', 2, 'hosted', NULL, NULL, true),
  ('host_25', 62, 25, 'Người kết nối', 'Community builder', 'Hoàn thành 25 sự kiện có khách hợp lệ.', 'Complete 25 events with legitimate attendees.', 'host', 3, 'hosted', NULL, NULL, true),
  ('season_tet_2027', 70, 1, 'Du xuân 2027', 'Lunar New Year 2027', 'Tham dự một sự kiện diễn ra từ 25/1 đến 21/2/2027.', 'Attend an event taking place between 25 Jan and 21 Feb 2027.', 'season', 1, 'season_attended', DATE '2027-01-25', DATE '2027-02-21', true)
ON CONFLICT (code) DO NOTHING;

ALTER TABLE public.reward_badge_defs ALTER COLUMN family SET NOT NULL, ALTER COLUMN tier SET NOT NULL, ALTER COLUMN metric SET NOT NULL;
ALTER TABLE public.reward_badge_defs DROP CONSTRAINT IF EXISTS reward_badge_defs_metric_known;
ALTER TABLE public.reward_badge_defs ADD CONSTRAINT reward_badge_defs_metric_known
  CHECK (metric IN ('ready_to_explore', 'attended', 'categories', 'hosted', 'outing_months', 'season_attended'));
ALTER TABLE public.reward_badge_defs DROP CONSTRAINT IF EXISTS reward_badge_defs_season_window;
ALTER TABLE public.reward_badge_defs ADD CONSTRAINT reward_badge_defs_season_window
  CHECK ((metric = 'season_attended') = (starts_on IS NOT NULL AND ends_on IS NOT NULL) AND (ends_on IS NULL OR ends_on >= starts_on));

-- Counts gain outing_months and one 'season:<code>' entry per seasonal badge.
CREATE OR REPLACE FUNCTION public.rewards_badge_counts(p_uid uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    'ready_to_explore', (SELECT count(*) FROM public.reward_ledger WHERE user_id = p_uid AND source_key = 'onboarding:preferences'),
    'attended',         (SELECT count(*) FROM public.reward_attendances WHERE user_id = p_uid AND valid),
    'categories',       (SELECT count(DISTINCT cat_key) FROM public.reward_attendances
                          WHERE user_id = p_uid AND valid AND cat_key IS NOT NULL AND cat_key <> ''),
    'hosted',           (SELECT count(*) FROM public.events e
                           JOIN public.organizers o ON o.id = e.organizer_id
                          WHERE (o.owner_id = p_uid OR o.user_id = p_uid) AND e.status = 'ended'
                            AND EXISTS (SELECT 1 FROM public.reward_attendances a
                                         WHERE a.event_id = e.id AND a.valid AND a.user_id <> p_uid)),
    'outing_months',    (SELECT count(DISTINCT date_trunc('month', public.rewards_user_local_date(p_uid, a.first_valid_at)))
                           FROM public.reward_attendances a WHERE a.user_id = p_uid AND a.valid))
  || COALESCE((SELECT jsonb_object_agg('season:' || d.code,
                 (SELECT count(*) FROM public.reward_attendances a JOIN public.events e ON e.id = a.event_id
                   WHERE a.user_id = p_uid AND a.valid AND e.starts_at IS NOT NULL
                     AND public.rewards_user_local_date(p_uid, e.starts_at) BETWEEN d.starts_on AND d.ends_on))
                 FROM public.reward_badge_defs d WHERE d.metric = 'season_attended'), '{}'::jsonb)
$$;

CREATE OR REPLACE FUNCTION public.rewards_badge_progress(p_metric text, p_code text, p_counts jsonb)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT COALESCE(CASE p_metric
    WHEN 'season_attended' THEN (p_counts ->> ('season:' || p_code))::int
    ELSE (p_counts ->> p_metric)::int END, 0)
$$;

-- Kept for anything still calling it by code; now reads the metric from the definition.
CREATE OR REPLACE FUNCTION public.rewards_badge_progress_of(p_code text, p_counts jsonb)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE((SELECT public.rewards_badge_progress(d.metric, d.code, p_counts) FROM public.reward_badge_defs d WHERE d.code = p_code), 0)
$$;

CREATE OR REPLACE FUNCTION public.rewards_refresh_badges(p_uid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_counts jsonb := public.rewards_badge_counts(p_uid); d record; v_p int;
BEGIN
  FOR d IN SELECT code, target, metric FROM public.reward_badge_defs LOOP
    v_p := public.rewards_badge_progress(d.metric, d.code, v_counts);
    IF v_p >= d.target THEN
      INSERT INTO public.reward_user_badges (user_id, badge_code) VALUES (p_uid, d.code)
      ON CONFLICT (user_id, badge_code) DO UPDATE
        SET revoked_at = NULL,
            earned_at = CASE WHEN public.reward_user_badges.revoked_at IS NULL THEN public.reward_user_badges.earned_at ELSE now() END;
    ELSE
      UPDATE public.reward_user_badges SET revoked_at = now()
       WHERE user_id = p_uid AND badge_code = d.code AND revoked_at IS NULL;
    END IF;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Monthly outing goal
-- ---------------------------------------------------------------------------
ALTER TABLE public.reward_user_settings
  ADD COLUMN IF NOT EXISTS monthly_goal smallint,
  ADD COLUMN IF NOT EXISTS goal_set_at timestamptz;
ALTER TABLE public.reward_user_settings DROP CONSTRAINT IF EXISTS reward_user_settings_goal_known;
ALTER TABLE public.reward_user_settings ADD CONSTRAINT reward_user_settings_goal_known CHECK (monthly_goal IN (1, 2, 4));

CREATE OR REPLACE FUNCTION public.rewards_goal_of(p_uid uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    'target', (SELECT s.monthly_goal FROM public.reward_user_settings s WHERE s.user_id = p_uid),
    'month', to_char(date_trunc('month', public.rewards_user_local_date(p_uid, now())), 'YYYY-MM-DD'),
    'progress', (SELECT count(*) FROM public.reward_attendances a
                  WHERE a.user_id = p_uid AND a.valid
                    AND date_trunc('month', public.rewards_user_local_date(p_uid, a.first_valid_at))
                        = date_trunc('month', public.rewards_user_local_date(p_uid, now()))))
$$;

CREATE OR REPLACE FUNCTION public.set_my_outing_goal(p_goal integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_goal int := NULLIF(p_goal, 0);
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  IF NOT public.rewards_flag('rewards', true) OR NOT public.rewards_flag('rewards_v2', false) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AVAILABLE');
  END IF;
  IF v_goal IS NOT NULL AND v_goal NOT IN (1, 2, 4) THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_GOAL'); END IF;
  PERFORM public.rewards_lock_user(v_uid);
  INSERT INTO public.reward_user_settings (user_id, monthly_goal, goal_set_at) VALUES (v_uid, v_goal, now())
  ON CONFLICT (user_id) DO UPDATE SET monthly_goal = excluded.monthly_goal, goal_set_at = excluded.goal_set_at, updated_at = now();
  RETURN jsonb_build_object('success', true, 'goal', public.rewards_goal_of(v_uid));
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Payloads (additive)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_reward_summary()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_s jsonb; v_w jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  v_s := public.rewards_streak_of(v_uid);
  v_w := public.rewards_week_streak_of(v_uid);
  RETURN jsonb_build_object('success', true, 'balance', public.rewards_balance(v_uid),
                            'streak', v_s -> 'current', 'active_today', v_s -> 'active_today',
                            'week_streak', v_w -> 'current', 'week_active', v_w -> 'this_week_active');
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_rewards()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid(); v_rules jsonb := public.rewards_rules(); v_counts jsonb;
  v_badges jsonb; v_hist jsonb; v_cat jsonb; v_paid int; v_offers jsonb := '[]'::jsonb;
  v_v2 boolean := public.rewards_flag('rewards_v2', false); v_today date; v_next jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  v_counts := public.rewards_badge_counts(v_uid);
  v_today := public.rewards_user_local_date(v_uid, now());

  -- Visible badges: the v1 six always; v2 rows only while 'rewards_v2' is on; a seasonal one only from 14 days
  -- before its window until it closes, or once earned. Old keys first, new keys after (old clients ignore them).
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'code', d.code, 'title_vi', d.title_vi, 'title_en', d.title_en, 'desc_vi', d.desc_vi, 'desc_en', d.desc_en,
           'target', d.target,
           'progress', LEAST(public.rewards_badge_progress(d.metric, d.code, v_counts), d.target),
           'earned', (b.badge_code IS NOT NULL AND b.revoked_at IS NULL),
           'earned_at', CASE WHEN b.revoked_at IS NULL THEN b.earned_at END,
           'family', d.family, 'tier', d.tier, 'starts_on', d.starts_on, 'ends_on', d.ends_on) ORDER BY d.sort), '[]'::jsonb)
    INTO v_badges
    FROM public.reward_badge_defs d
    LEFT JOIN public.reward_user_badges b ON b.badge_code = d.code AND b.user_id = v_uid
   WHERE (NOT d.v2 OR v_v2)
     AND (d.metric <> 'season_attended' OR (b.badge_code IS NOT NULL AND b.revoked_at IS NULL)
          OR v_today BETWEEN d.starts_on - 14 AND d.ends_on);

  -- Next badge (goal gradient): the visible unearned badge closest to done. Host badges only for people who host;
  -- a seasonal one only while its window is open.
  SELECT jsonb_build_object('code', x ->> 'code', 'family', x ->> 'family', 'tier', (x ->> 'tier')::int,
                            'progress', (x ->> 'progress')::int, 'target', (x ->> 'target')::int,
                            'remaining', (x ->> 'target')::int - (x ->> 'progress')::int,
                            'title_vi', x ->> 'title_vi', 'title_en', x ->> 'title_en',
                            'desc_vi', x ->> 'desc_vi', 'desc_en', x ->> 'desc_en')
    INTO v_next
    FROM jsonb_array_elements(v_badges) WITH ORDINALITY AS t(x, ord)
   WHERE NOT (x ->> 'earned')::boolean
     AND (x ->> 'family' <> 'host' OR COALESCE((v_counts ->> 'hosted')::int, 0) > 0)
     AND (x ->> 'family' <> 'season' OR v_today BETWEEN (x ->> 'starts_on')::date AND (x ->> 'ends_on')::date)
   ORDER BY (x ->> 'target')::int - (x ->> 'progress')::int, (x ->> 'tier')::int, ord
   LIMIT 1;

  SELECT COALESCE(jsonb_agg(h ORDER BY (h ->> 'created_at') DESC), '[]'::jsonb) INTO v_hist FROM (
    SELECT jsonb_build_object('id', l.id, 'type', l.entry_type, 'amount', l.amount, 'reason', l.reason,
                              'created_at', l.created_at, 'event_name', e.name, 'item_code', l.ref ->> 'item_code') AS h
      FROM public.reward_ledger l LEFT JOIN public.events e ON e.id = l.ref ->> 'event_id'
     WHERE l.user_id = v_uid ORDER BY l.created_at DESC LIMIT 40) x;

  -- `catalog` keeps ONLY keychain designs, with every old field. Offers go in the new `offers` key so a client
  -- built before 179 (iOS decodes design_id as a non-optional String) never sees a row it cannot read.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('code', c.code, 'kind', c.kind, 'design_id', c.design_id,
                                               'price', c.price, 'unlocked', u.user_id IS NOT NULL,
                                               'title_vi', c.title_vi, 'title_en', c.title_en, 'desc_vi', c.desc_vi, 'desc_en', c.desc_en,
                                               'status', CASE WHEN u.user_id IS NOT NULL THEN 'unlocked' ELSE 'available' END) ORDER BY c.sort), '[]'::jsonb)
    INTO v_cat FROM public.reward_catalog c
    LEFT JOIN public.reward_unlocks u ON u.item_code = c.code AND u.user_id = v_uid WHERE c.active AND c.kind = 'keychain_design';

  -- Partner offers: hidden (empty) unless the 'partner_offers' flag is on. Display only: no redemption path yet.
  IF COALESCE((SELECT f.enabled FROM public.reward_feature_flags f WHERE f.flag = 'partner_offers'), false) THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object('code', c.code, 'kind', c.kind, 'price', c.price,
                                                 'title_vi', c.title_vi, 'title_en', c.title_en, 'desc_vi', c.desc_vi, 'desc_en', c.desc_en,
                                                 'status', 'unavailable') ORDER BY c.sort), '[]'::jsonb)
      INTO v_offers FROM public.reward_catalog c WHERE c.active AND c.kind = 'partner_offer';
  END IF;

  v_paid := public.rewards_month_paid_count(v_uid);

  RETURN jsonb_build_object(
    'success', true, 'balance', public.rewards_balance(v_uid), 'rules', v_rules,
    'streak', public.rewards_streak_of(v_uid), 'badges', v_badges, 'history', v_hist, 'catalog', v_cat, 'offers', v_offers,
    'attendance_paid_this_month', v_paid,
    'timezone_settings', public.rewards_tz_settings(v_uid),
    'week_streak', public.rewards_week_streak_of(v_uid), 'next_badge', v_next, 'goal', public.rewards_goal_of(v_uid));
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Grants + earn the new tiers for everyone who already qualifies (badge rows only; no coins)
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.rewards_week_streak_of(uuid), public.rewards_goal_of(uuid),
                           public.rewards_badge_progress(text, text, jsonb), public.rewards_badge_progress_of(text, jsonb),
                           public.rewards_badge_counts(uuid), public.rewards_refresh_badges(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_my_outing_goal(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_outing_goal(integer), public.get_my_rewards(), public.get_my_reward_summary(),
                          public.admin_set_feature_flag(text, boolean) TO authenticated;

DO $$
DECLARE v_u uuid;
BEGIN
  FOR v_u IN SELECT DISTINCT user_id FROM public.reward_attendances
             UNION SELECT DISTINCT o.owner_id FROM public.organizers o WHERE o.owner_id IS NOT NULL
               AND EXISTS (SELECT 1 FROM public.events e WHERE e.organizer_id = o.id AND e.status = 'ended')
             UNION SELECT DISTINCT o.user_id FROM public.organizers o WHERE o.user_id IS NOT NULL
               AND EXISTS (SELECT 1 FROM public.events e WHERE e.organizer_id = o.id AND e.status = 'ended')
  LOOP
    PERFORM public.rewards_refresh_badges(v_u);
  END LOOP;
END $$;
