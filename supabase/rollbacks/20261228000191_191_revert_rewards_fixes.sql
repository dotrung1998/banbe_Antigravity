-- ROLLBACK for 191 (manual, NOT in the migration chain). Data-safe: no ledger, attendance or badge row is deleted.
-- Restores the function bodies and the event-status trigger as they were after 177-180, reactivates rules version 1
-- (no attendance window) and re-grants the legacy check_in. Awards and reversals written while 191 was live stay in
-- the append-only ledger. Attendances of removed events stay invalid (re-checking a guest in re-validates them).
BEGIN;
UPDATE public.reward_rule_versions SET is_active = false WHERE is_active AND version <> 1;
UPDATE public.reward_rule_versions SET is_active = true WHERE version = 1;

CREATE OR REPLACE FUNCTION public.rewards_desired_sources(p_booking uuid)
 RETURNS TABLE(user_id uuid, event_id text, kind text, ref_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH b AS (
    SELECT bk.* FROM public.bookings bk
     WHERE bk.id = p_booking
       AND bk.status NOT IN ('cancelled', 'expired')
       AND EXISTS (SELECT 1 FROM public.check_ins c WHERE c.booking_id = bk.id)
       AND EXISTS (SELECT 1 FROM public.events e WHERE e.id = bk.event_id AND e.status NOT IN ('cancelled', 'draft', 'review'))
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
$function$
;

CREATE OR REPLACE FUNCTION public.rewards_trg_event_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_b uuid; v_owner uuid;
BEGIN
  BEGIN
    IF NEW.status = 'cancelled' THEN
      FOR v_b IN SELECT booking_id FROM public.check_ins WHERE event_id = NEW.id AND booking_id IS NOT NULL LOOP
        PERFORM public.rewards_sync_booking(v_b);
      END LOOP;
    ELSIF NEW.status = 'ended' THEN
      FOR v_owner IN SELECT public.rewards_event_owner_ids(NEW.id) LOOP PERFORM public.rewards_refresh_badges(v_owner); END LOOP;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'rewards event-status sync failed for event %: % (%)', NEW.id, SQLERRM, SQLSTATE;
  END;
  RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rewards_award_attendance(p_uid uuid, p_event text, p_cycle integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.redeem_reward(p_item_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_item public.reward_catalog%ROWTYPE; v_bal int; v_lid uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
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
$function$
;

CREATE OR REPLACE FUNCTION public.record_active_day(p_source text, p_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.set_my_reward_timezone(p_tz text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$
;


DROP TRIGGER IF EXISTS rewards_event_status ON public.events;
CREATE TRIGGER rewards_event_status AFTER UPDATE OF status ON public.events
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status IN ('cancelled', 'ended'))
  EXECUTE FUNCTION public.rewards_trg_event_status();

GRANT EXECUTE ON FUNCTION public.check_in(text, boolean) TO authenticated;
DROP FUNCTION IF EXISTS public.rewards_flag(text, boolean);
COMMIT;
