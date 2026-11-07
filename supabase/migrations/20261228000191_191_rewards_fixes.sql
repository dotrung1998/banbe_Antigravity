-- 191: rewards fixes (Rewards v2, Phase 0). Builds on 165 + 177-180. EXPAND ONLY; every RPC keeps its signature
-- and its JSON keys, so builds already in the field keep working.
--
-- 1. Removed events (188/189) never reversed coins: rewards_desired_sources only excluded cancelled/draft/review, and
--    the event-status trigger only fired on cancelled/ended. An event an admin REMOVES now invalidates its attendances
--    (coins reversed through the normal reversal path, badges refreshed); RESTORING it re-validates them. A
--    re-validation pays a new cycle exactly like an undo + re-check-in already does (165), and the window rule below
--    uses the ORIGINAL check-in time, so a restore never turns a fair award into an off-window zero.
--    One-time backfill: attendances at events that are already 'removed' are re-synced (reversed) below.
-- 2. The Rewards switch (187) was client-only. The client-callable WRITES now refuse with NOT_AVAILABLE while
--    app_feature_flags.rewards = false (missing row = on, same as the clients): redeem_reward, record_active_day,
--    set_my_reward_timezone. Reads stay available, and server-side awards keep accruing (note 51's intent), so
--    turning Rewards back on shows the right numbers.
-- 3. Attendance time window (rules version 2): a check-in recorded outside [starts_at - 3 h, starts_at + 24 h] still
--    counts as attendance (badges, streak) but pays 0 coins with reason 'off_window'. Events without starts_at are
--    not judged. 178's off_window risk flag stays stricter (+12 h) on purpose: it only flags, this one decides coins.
-- 4. The legacy check_in(text, boolean) from 007 still accepted calls and still triggered awards, outside every rule
--    check_in_guest enforces. No client calls it (web, iOS, api/ checked 2026-10-22): EXECUTE is revoked. The function
--    is kept so the rollback can re-grant it.
--
-- ROLLBACK: supabase/rollbacks/20261228000191_191_revert_rewards_fixes.sql (restores the previous function bodies and
-- trigger, reactivates rules version 1, re-grants check_in). Ledger rows written meanwhile are kept (append-only).

-- ---------------------------------------------------------------------------
-- 0. Flag helper: one place that reads app_feature_flags for the rewards RPCs.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rewards_flag(p_key text, p_default boolean)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE((SELECT f.enabled FROM public.app_feature_flags f WHERE f.key = p_key), p_default)
$$;

-- ---------------------------------------------------------------------------
-- 1. Rules version 2 = the active rules + the attendance window. Version 1 stays for the rollback.
-- ---------------------------------------------------------------------------
INSERT INTO public.reward_rule_versions (version, is_active, rules, notes)
SELECT 2, false,
       r.rules || jsonb_build_object('attendance_window_before_hours', 3, 'attendance_window_after_hours', 24),
       '191: attendance pays coins only when checked in within [starts_at - 3h, starts_at + 24h]'
  FROM public.reward_rule_versions r WHERE r.is_active
ON CONFLICT (version) DO NOTHING;
UPDATE public.reward_rule_versions SET is_active = false WHERE is_active AND version <> 2;
UPDATE public.reward_rule_versions SET is_active = true WHERE version = 2;

-- ---------------------------------------------------------------------------
-- 2. Removed events are not attendance; status changes re-sync.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rewards_desired_sources(p_booking uuid)
RETURNS TABLE(user_id uuid, event_id text, kind text, ref_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH b AS (
    SELECT bk.* FROM public.bookings bk
     WHERE bk.id = p_booking
       AND bk.status NOT IN ('cancelled', 'expired')
       AND EXISTS (SELECT 1 FROM public.check_ins c WHERE c.booking_id = bk.id)
       AND EXISTS (SELECT 1 FROM public.events e WHERE e.id = bk.event_id AND e.status NOT IN ('cancelled', 'draft', 'review', 'removed'))
  ), ci AS (SELECT c.checked_in_by FROM public.check_ins c WHERE c.booking_id = p_booking LIMIT 1)
  SELECT h.uid, b.event_id, 'booking'::text, b.id
    FROM b
    CROSS JOIN LATERAL (SELECT CASE WHEN b.recipient_name IS NOT NULL OR b.gifted_at IS NOT NULL
                                    THEN b.claimed_by_user_id ELSE b.user_id END AS uid) h
   WHERE h.uid IS NOT NULL
     AND public.rewards_attendee_eligible(h.uid, b.event_id, (SELECT checked_in_by FROM ci))
  UNION ALL
  SELECT a.claimed_by_user_id, b.event_id, 'seat'::text, a.id
    FROM b JOIN public.booking_attendees a ON a.booking_id = b.id
   WHERE a.checked_in_at IS NOT NULL AND a.claimed_by_user_id IS NOT NULL
     AND public.rewards_attendee_eligible(a.claimed_by_user_id, b.event_id, a.checked_in_by)
$$;

CREATE OR REPLACE FUNCTION public.rewards_trg_event_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_b uuid; v_owner uuid;
BEGIN
  BEGIN
    -- Cancelled / removed: attendance is no longer valid. Restored from removed: it may be valid again.
    IF NEW.status IN ('cancelled', 'removed') OR OLD.status = 'removed' THEN
      FOR v_b IN SELECT DISTINCT booking_id FROM public.check_ins WHERE event_id = NEW.id AND booking_id IS NOT NULL LOOP
        PERFORM public.rewards_sync_booking(v_b);
      END LOOP;
    END IF;
    -- Host milestone counts ENDED events: refresh the owners whenever an event enters or leaves that state.
    IF NEW.status IN ('ended', 'removed') OR OLD.status IN ('ended', 'removed') THEN
      FOR v_owner IN SELECT public.rewards_event_owner_ids(NEW.id) LOOP PERFORM public.rewards_refresh_badges(v_owner); END LOOP;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'rewards event-status sync failed for event %: % (%)', NEW.id, SQLERRM, SQLSTATE;
  END;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS rewards_event_status ON public.events;
CREATE TRIGGER rewards_event_status AFTER UPDATE OF status ON public.events
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status
                     AND (NEW.status IN ('cancelled', 'ended', 'removed') OR OLD.status IN ('ended', 'removed')))
  EXECUTE FUNCTION public.rewards_trg_event_status();

-- ---------------------------------------------------------------------------
-- 3. Attendance window. The time judged is the booking's first recorded check-in, not the moment of a re-sync.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rewards_award_attendance(p_uid uuid, p_event text, p_cycle integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_rules jsonb := public.rewards_rules();
  v_coins int := COALESCE((v_rules ->> 'attendance_coins')::int, 0);
  v_cap int := COALESCE((v_rules ->> 'attendance_coin_cap_per_month')::int, 0);
  v_before int := (v_rules ->> 'attendance_window_before_hours')::int;
  v_after int := (v_rules ->> 'attendance_window_after_hours')::int;
  v_start timestamptz; v_at timestamptz;
  v_paid int; v_amount int; v_reason text := 'attendance';
BEGIN
  PERFORM public.rewards_lock_user(p_uid);
  v_amount := v_coins;
  IF v_before IS NOT NULL AND v_after IS NOT NULL THEN
    SELECT e.starts_at INTO v_start FROM public.events e WHERE e.id = p_event;
    SELECT min(COALESCE(c.checked_in_at, c.checked_at)) INTO v_at
      FROM public.check_ins c
     WHERE c.booking_id = (SELECT a.booking_id FROM public.reward_attendances a WHERE a.user_id = p_uid AND a.event_id = p_event);
    v_at := COALESCE(v_at, now());
    IF v_start IS NOT NULL AND (v_at < v_start - make_interval(hours => v_before) OR v_at > v_start + make_interval(hours => v_after)) THEN
      v_amount := 0; v_reason := 'off_window';
    END IF;
  END IF;
  IF v_amount > 0 THEN
    v_paid := public.rewards_month_paid_count(p_uid);
    IF v_cap > 0 AND v_paid >= v_cap THEN v_amount := 0; v_reason := 'attendance_cap'; END IF;
  END IF;
  PERFORM public.rewards_add_entry(p_uid, 'award', v_amount, 'attend:' || p_event || ':' || p_cycle, NULL, v_reason,
                                   jsonb_build_object('event_id', p_event, 'cycle', p_cycle));
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Server-side Rewards switch on the client-callable writes (bodies otherwise unchanged from 177/179).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.redeem_reward(p_item_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_item public.reward_catalog%ROWTYPE; v_bal int; v_lid uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  IF NOT public.rewards_flag('rewards', true) THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AVAILABLE'); END IF;
  PERFORM public.rewards_lock_user(v_uid);
  SELECT * INTO v_item FROM public.reward_catalog WHERE code = p_item_code AND active;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_FOUND'); END IF;
  -- Only keychain designs can be redeemed here. A partner offer has no redemption path yet (Phase 1).
  IF v_item.kind IS DISTINCT FROM 'keychain_design' THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AVAILABLE'); END IF;
  v_bal := public.rewards_balance(v_uid);
  IF EXISTS (SELECT 1 FROM public.reward_unlocks WHERE user_id = v_uid AND item_code = v_item.code) THEN
    RETURN jsonb_build_object('success', true, 'already_unlocked', true, 'balance', v_bal);
  END IF;
  IF v_bal < v_item.price THEN
    RETURN jsonb_build_object('success', false, 'error', 'INSUFFICIENT_BALANCE', 'balance', v_bal, 'price', v_item.price);
  END IF;
  v_lid := public.rewards_add_entry(v_uid, 'redemption', -v_item.price, 'redeem:' || v_item.code, NULL, 'redemption',
                                    jsonb_build_object('item_code', v_item.code, 'design_id', v_item.design_id));
  IF v_lid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'TRY_AGAIN'); END IF;
  INSERT INTO public.reward_unlocks (user_id, item_code, ledger_id) VALUES (v_uid, v_item.code, v_lid);
  RETURN jsonb_build_object('success', true, 'balance', v_bal - v_item.price, 'design_id', v_item.design_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.record_active_day(p_source text, p_ref text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_saved timestamptz;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  IF NOT public.rewards_flag('rewards', true) THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AVAILABLE'); END IF;
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

CREATE OR REPLACE FUNCTION public.set_my_reward_timezone(p_tz text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid(); s public.reward_user_settings%ROWTYPE; v_cur text; v_t timestamptz;
  v_recent timestamptz[]; v_bridge date;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  IF NOT public.rewards_flag('rewards', true) THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AVAILABLE'); END IF;
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
-- 5. Legacy check_in (007): no caller left; it bypassed every check_in_guest rule.
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.check_in(text, boolean) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Grants + one-time backfill (removed events keep no coins).
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.rewards_flag(text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.rewards_desired_sources(uuid), public.rewards_award_attendance(uuid, text, integer),
                           public.rewards_trg_event_status() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_reward(text), public.record_active_day(text, text),
                          public.set_my_reward_timezone(text) TO authenticated;

DO $$
DECLARE v_b uuid; v_owner uuid; v_e text;
BEGIN
  FOR v_b IN SELECT DISTINCT c.booking_id FROM public.check_ins c JOIN public.events e ON e.id = c.event_id
              WHERE e.status = 'removed' AND c.booking_id IS NOT NULL LOOP
    PERFORM public.rewards_sync_booking(v_b);
  END LOOP;
  FOR v_e IN SELECT id FROM public.events WHERE status = 'removed' LOOP
    FOR v_owner IN SELECT public.rewards_event_owner_ids(v_e) LOOP PERFORM public.rewards_refresh_badges(v_owner); END LOOP;
  END LOOP;
END $$;
