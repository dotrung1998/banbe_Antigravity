-- ROLLBACK for 177 (manual, NOT in the migration chain). Data-safe: restores the 165 function bodies and drops the
-- new RPC; keeps reward_user_settings and reward_ledger.period_month/tz_used (inert, nullable) so no choice or ledger
-- data is lost. Effect: users who chose a zone go back to Vietnam-time day/month boundaries.
-- Do NOT drop the table/columns unless the data is confirmed disposable.
BEGIN;
DROP FUNCTION IF EXISTS public.set_my_reward_timezone(text);
CREATE OR REPLACE FUNCTION public.rewards_add_entry(
  p_uid uuid, p_type text, p_amount int, p_key text, p_reverses uuid, p_reason text, p_ref jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
  PERFORM public.rewards_lock_user(p_uid);
  INSERT INTO public.reward_ledger (user_id, entry_type, amount, source_key, reverses_id, rules_version, reason, ref)
  VALUES (p_uid, p_type, p_amount, p_key, p_reverses, (public.rewards_rules() ->> 'version')::int, p_reason, COALESCE(p_ref, '{}'::jsonb))
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.rewards_award_attendance(p_uid uuid, p_event text, p_cycle int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_rules jsonb := public.rewards_rules();
  v_coins int := COALESCE((v_rules ->> 'attendance_coins')::int, 0);
  v_cap int := COALESCE((v_rules ->> 'attendance_coin_cap_per_month')::int, 0);
  v_paid int; v_amount int; v_reason text := 'attendance';
BEGIN
  PERFORM public.rewards_lock_user(p_uid);
  -- Coin-paying attendance awards already made in this local month and not reversed.
  SELECT count(*) INTO v_paid FROM public.reward_ledger a
   WHERE a.user_id = p_uid AND a.entry_type = 'award' AND a.amount > 0 AND a.source_key LIKE 'attend:%'
     AND date_trunc('month', a.created_at AT TIME ZONE public.rewards_tz()) = date_trunc('month', now() AT TIME ZONE public.rewards_tz())
     AND NOT EXISTS (SELECT 1 FROM public.reward_ledger r WHERE r.reverses_id = a.id);
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
  VALUES (p_uid, public.rewards_local_date(now()), 'attendance') ON CONFLICT DO NOTHING;
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
  VALUES (v_uid, public.rewards_local_date(v_saved), 'save') ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('success', true, 'streak', public.rewards_streak_of(v_uid) -> 'current');
END;
$$;

CREATE OR REPLACE FUNCTION public.rewards_streak_of(p_uid uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_today date := public.rewards_local_date(now()); v_last date; v_cur int := 0; v_best int := 0;
BEGIN
  SELECT max(local_date) INTO v_last FROM public.reward_active_days WHERE user_id = p_uid;
  IF v_last IS NOT NULL AND v_last >= v_today - 1 THEN
    -- A streak is alive through yesterday: not having acted yet today costs nothing.
    WITH d AS (
      SELECT local_date, local_date - (row_number() OVER (ORDER BY local_date))::int AS grp
        FROM public.reward_active_days WHERE user_id = p_uid AND local_date <= v_last)
    SELECT count(*) INTO v_cur FROM d WHERE d.grp = (SELECT d2.grp FROM d d2 ORDER BY d2.local_date DESC LIMIT 1);
  END IF;
  SELECT COALESCE(max(n), 0) INTO v_best FROM (
    SELECT count(*) AS n FROM (
      SELECT local_date - (row_number() OVER (ORDER BY local_date))::int AS grp
        FROM public.reward_active_days WHERE user_id = p_uid
    ) g GROUP BY grp
  ) x;
  RETURN jsonb_build_object('current', v_cur, 'longest', v_best, 'last_active_date', v_last,
                            'active_today', COALESCE(v_last = v_today, false), 'timezone', public.rewards_tz());
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

  SELECT count(*) INTO v_paid FROM public.reward_ledger a
   WHERE a.user_id = v_uid AND a.entry_type = 'award' AND a.amount > 0 AND a.source_key LIKE 'attend:%'
     AND date_trunc('month', a.created_at AT TIME ZONE public.rewards_tz()) = date_trunc('month', now() AT TIME ZONE public.rewards_tz())
     AND NOT EXISTS (SELECT 1 FROM public.reward_ledger r WHERE r.reverses_id = a.id);

  RETURN jsonb_build_object(
    'success', true, 'balance', public.rewards_balance(v_uid), 'rules', v_rules,
    'streak', public.rewards_streak_of(v_uid), 'badges', v_badges, 'history', v_hist, 'catalog', v_cat,
    'attendance_paid_this_month', v_paid);
END;
$$;

COMMIT;
