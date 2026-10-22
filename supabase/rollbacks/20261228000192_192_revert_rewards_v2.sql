-- ROLLBACK for 192 (manual, NOT in the migration chain). Data-safe for coins: no ledger row is touched.
-- Restores the function bodies as they were after 191, reactivates rules version 2, removes the v2 badge definitions
-- (and the badge rows earned for them), the badge-def columns, the v2 functions and the 'rewards_v2' switch.
-- reward_user_settings.monthly_goal / goal_set_at are KEPT (nullable, inert once the functions are gone): dropping
-- them would lose people's choice for nothing. Drop them by hand only if 192 will never come back.
BEGIN;
UPDATE public.reward_rule_versions SET is_active = false WHERE is_active AND version <> 2;
UPDATE public.reward_rule_versions SET is_active = true WHERE version = 2;

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
                                         WHERE a.event_id = e.id AND a.valid AND a.user_id <> p_uid)))
$$;

CREATE OR REPLACE FUNCTION public.rewards_badge_progress_of(p_code text, p_counts jsonb)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_code
    WHEN 'ready_to_explore'  THEN (p_counts ->> 'ready_to_explore')::int
    WHEN 'first_outing'      THEN (p_counts ->> 'attended')::int
    WHEN 'regular'           THEN (p_counts ->> 'attended')::int
    WHEN 'community_regular' THEN (p_counts ->> 'attended')::int
    WHEN 'explorer'          THEN (p_counts ->> 'categories')::int
    WHEN 'host_milestone'    THEN (p_counts ->> 'hosted')::int
    ELSE 0 END
$$;

CREATE OR REPLACE FUNCTION public.rewards_refresh_badges(p_uid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_counts jsonb := public.rewards_badge_counts(p_uid); d record; v_p int;
BEGIN
  FOR d IN SELECT code, target FROM public.reward_badge_defs LOOP
    v_p := public.rewards_badge_progress_of(d.code, v_counts);
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

CREATE OR REPLACE FUNCTION public.get_my_reward_summary()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_s jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  v_s := public.rewards_streak_of(v_uid);
  RETURN jsonb_build_object('success', true, 'balance', public.rewards_balance(v_uid),
                            'streak', v_s -> 'current', 'active_today', v_s -> 'active_today');
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_rewards()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid(); v_rules jsonb := public.rewards_rules(); v_counts jsonb;
  v_badges jsonb; v_hist jsonb; v_cat jsonb; v_paid int; v_offers jsonb := '[]'::jsonb;
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
                                               'price', c.price, 'unlocked', u.user_id IS NOT NULL,
                                               'title_vi', c.title_vi, 'title_en', c.title_en, 'desc_vi', c.desc_vi, 'desc_en', c.desc_en,
                                               'status', CASE WHEN u.user_id IS NOT NULL THEN 'unlocked' ELSE 'available' END) ORDER BY c.sort), '[]'::jsonb)
    INTO v_cat FROM public.reward_catalog c
    LEFT JOIN public.reward_unlocks u ON u.item_code = c.code AND u.user_id = v_uid WHERE c.active AND c.kind = 'keychain_design';

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
    'timezone_settings', public.rewards_tz_settings(v_uid));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_feature_flag(p_key text, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_enabled IS NULL OR p_key IS NULL OR p_key NOT IN ('rewards', 'admin_event_wipe') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  INSERT INTO public.app_feature_flags (key, enabled, updated_by, updated_at)
  VALUES (p_key, p_enabled, v_admin, now())
  ON CONFLICT (key) DO UPDATE SET enabled = excluded.enabled, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  INSERT INTO public.app_feature_flags_audit (admin_id, key, enabled) VALUES (v_admin, p_key, p_enabled);
  RETURN jsonb_build_object('success', true, 'key', p_key, 'enabled', p_enabled);
END;
$$;

DROP FUNCTION IF EXISTS public.set_my_outing_goal(integer);
DROP FUNCTION IF EXISTS public.rewards_goal_of(uuid);
DROP FUNCTION IF EXISTS public.rewards_week_streak_of(uuid);
DROP FUNCTION IF EXISTS public.rewards_badge_progress(text, text, jsonb);

DELETE FROM public.reward_user_badges WHERE badge_code IN (SELECT code FROM public.reward_badge_defs WHERE v2);
DELETE FROM public.reward_badge_defs WHERE v2;
UPDATE public.reward_badge_defs SET sort = x.sort
  FROM (VALUES ('ready_to_explore', 10), ('first_outing', 20), ('regular', 30), ('explorer', 40),
               ('community_regular', 50), ('host_milestone', 60)) AS x(code, sort)
 WHERE reward_badge_defs.code = x.code;
ALTER TABLE public.reward_badge_defs DROP CONSTRAINT IF EXISTS reward_badge_defs_metric_known;
ALTER TABLE public.reward_badge_defs DROP CONSTRAINT IF EXISTS reward_badge_defs_season_window;
ALTER TABLE public.reward_badge_defs DROP COLUMN IF EXISTS family, DROP COLUMN IF EXISTS tier, DROP COLUMN IF EXISTS metric,
  DROP COLUMN IF EXISTS starts_on, DROP COLUMN IF EXISTS ends_on, DROP COLUMN IF EXISTS v2;
ALTER TABLE public.reward_user_settings DROP CONSTRAINT IF EXISTS reward_user_settings_goal_known;

DELETE FROM public.app_feature_flags WHERE key = 'rewards_v2';
ALTER TABLE public.app_feature_flags DROP CONSTRAINT IF EXISTS app_feature_flags_key_known;
ALTER TABLE public.app_feature_flags ADD CONSTRAINT app_feature_flags_key_known CHECK (key IN ('rewards', 'admin_event_wipe'));
COMMIT;
