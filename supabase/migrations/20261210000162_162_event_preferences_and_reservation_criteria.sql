-- Migration 162: event preferences ("For You"), onboarding markers, and
-- host-declared reservation criteria. ADDITIVE ONLY — nothing here rewrites,
-- backfills or invalidates an existing row.
--
-- 1. profile_event_preferences — owner-only side table for each account's
--    versioned self-declared preferences + onboarding markers.
--    WHY NOT A profiles COLUMN: `profiles_select_for_organizer` (migration 021)
--    lets a host SELECT the whole profiles row of anyone who booked/messaged
--    them, and Postgres cannot hide one column from a row policy. A column on
--    profiles would hand hosts every guest's full answers. This table has RLS
--    on and NO grants to anon/authenticated: the only access is the SECURITY
--    DEFINER RPCs below, each scoped to auth.uid().
-- 2. events.reservation_criteria — validated jsonb, default Everyone.
-- 3. check / assert helpers; assertion wired into hold_seats and claim_seats
--    (hold_seats_with_attendees calls hold_seats, so it is covered).
--
-- Rollback: supabase/rollbacks/20261210000163_163_revert_event_preferences.sql

-- ---------------------------------------------------------------------------
-- 0. Taxonomy + validators (single source of truth for allowed ids)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.event_pref_ids(p_group text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_group
    WHEN 'interests'    THEN ARRAY['supper','fashion','gallery','music','popup']
    WHEN 'goals'        THEN ARRAY['meet_people','learn','experiences','networking']
    WHEN 'availability' THEN ARRAY['weekdays','weekends','daytime','evening']
    WHEN 'languages'    THEN ARRAY['vi','en','other']
    WHEN 'budget'       THEN ARRAY['free','low','medium','flexible']
  END;
$$;

-- A multi-select answer: a distinct array of known ids, or exactly
-- ["no_preference"] on its own. Absent/null key = question skipped.
CREATE OR REPLACE FUNCTION public.event_pref_multi_ok(p jsonb, p_group text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p IS NULL OR jsonb_typeof(p) = 'null' THEN true
    WHEN jsonb_typeof(p) <> 'array' THEN false
    WHEN jsonb_array_length(p) = 0 OR jsonb_array_length(p) > 12 THEN false
    WHEN p = '["no_preference"]'::jsonb THEN true
    ELSE
      (SELECT bool_and(jsonb_typeof(e) = 'string' AND (e #>> '{}') = ANY (public.event_pref_ids(p_group)))
         FROM jsonb_array_elements(p) e)
      AND (SELECT count(*) = count(DISTINCT e) FROM jsonb_array_elements(p) e)
  END;
$$;

CREATE OR REPLACE FUNCTION public.validate_event_preferences(p jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT p IS NULL OR (
    jsonb_typeof(p) = 'object'
    AND p ->> 'version' = '1'
    AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) k
                    WHERE k NOT IN ('version','interests','goals','availability','budget','languages'))
    AND public.event_pref_multi_ok(p -> 'interests', 'interests')
    AND public.event_pref_multi_ok(p -> 'goals', 'goals')
    AND public.event_pref_multi_ok(p -> 'availability', 'availability')
    AND public.event_pref_multi_ok(p -> 'languages', 'languages')
    AND (
      p -> 'budget' IS NULL OR jsonb_typeof(p -> 'budget') = 'null'
      OR (
        jsonb_typeof(p -> 'budget') = 'object'
        AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p -> 'budget') k WHERE k NOT IN ('tier','currency'))
        AND (p -> 'budget' ->> 'tier') = ANY (public.event_pref_ids('budget') || ARRAY['no_preference'])
        AND (
          (p -> 'budget' ->> 'tier') IN ('free','no_preference')
          OR (p -> 'budget' ->> 'currency') IN ('VND','USD')
        )
      )
    )
  );
$$;

-- reservation_criteria shape:
--   {"version":1,"mode":"everyone"}
--   {"version":1,"mode":"declared",
--    "interests":{"rule":"any"|"all","values":[...]},   (optional group)
--    "goals":    {"rule":"any"|"all","values":[...]}}   (optional group)
-- ANY = the guest declared at least one of the values; ALL = every value.
-- When both groups are present BOTH must be satisfied. Only interests/goals
-- from the shared taxonomy are allowed — never budget, schedule, language,
-- consent, location, DOB or any protected trait.
CREATE OR REPLACE FUNCTION public.validate_reservation_criteria(p jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT p IS NOT NULL AND jsonb_typeof(p) = 'object' AND p ->> 'version' = '1' AND (
    (p ->> 'mode' = 'everyone'
       AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) k WHERE k NOT IN ('version','mode')))
    OR
    (p ->> 'mode' = 'declared'
       AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) k WHERE k NOT IN ('version','mode','interests','goals'))
       AND (p ? 'interests' OR p ? 'goals')
       AND (NOT p ? 'interests' OR (
              jsonb_typeof(p -> 'interests') = 'object'
              AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p -> 'interests') k WHERE k NOT IN ('rule','values'))
              AND p -> 'interests' ->> 'rule' IN ('any','all')
              AND jsonb_typeof(p -> 'interests' -> 'values') = 'array'
              AND jsonb_array_length(p -> 'interests' -> 'values') BETWEEN 1 AND 5
              AND p -> 'interests' -> 'values' <> '["no_preference"]'::jsonb
              AND public.event_pref_multi_ok(p -> 'interests' -> 'values', 'interests')))
       AND (NOT p ? 'goals' OR (
              jsonb_typeof(p -> 'goals') = 'object'
              AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p -> 'goals') k WHERE k NOT IN ('rule','values'))
              AND p -> 'goals' ->> 'rule' IN ('any','all')
              AND jsonb_typeof(p -> 'goals' -> 'values') = 'array'
              AND jsonb_array_length(p -> 'goals' -> 'values') BETWEEN 1 AND 4
              AND p -> 'goals' -> 'values' <> '["no_preference"]'::jsonb
              AND public.event_pref_multi_ok(p -> 'goals' -> 'values', 'goals'))))
  );
$$;

-- ---------------------------------------------------------------------------
-- 1. profile_event_preferences (owner-only via RPC) + cutover config
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profile_event_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  event_preferences jsonb CONSTRAINT event_preferences_valid CHECK (public.validate_event_preferences(event_preferences)),
  preferences_version int NOT NULL DEFAULT 0,       -- bumps on every save (client refresh key)
  preferences_updated_at timestamptz,
  settings_onboarded_version int NOT NULL DEFAULT 0, -- 0 = never completed
  settings_onboarded_at timestamptz,
  prefs_onboarded_version int NOT NULL DEFAULT 0,
  prefs_onboarded_at timestamptz,
  prompt_requested_at timestamptz,                  -- one-time prompt for existing TEST users (backfill script only)
  prompt_batch text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.profile_event_preferences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.profile_event_preferences FROM anon, authenticated;

-- Accounts created BEFORE this instant are never prompted (unless a row with
-- prompt_requested_at exists). Set once, at apply time.
CREATE TABLE IF NOT EXISTS public.event_onboarding_config (
  key text PRIMARY KEY,
  cutover_at timestamptz NOT NULL,
  current_version int NOT NULL DEFAULT 1
);
INSERT INTO public.event_onboarding_config (key, cutover_at) VALUES ('onboarding', now())
ON CONFLICT (key) DO NOTHING;
ALTER TABLE public.event_onboarding_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.event_onboarding_config FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_my_event_preferences()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.profile_event_preferences%ROWTYPE;
  v_cfg public.event_onboarding_config%ROWTYPE;
  v_created timestamptz;
  v_new boolean;
  v_eligible boolean;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT * INTO v_row FROM public.profile_event_preferences WHERE user_id = v_uid;
  SELECT * INTO v_cfg FROM public.event_onboarding_config WHERE key = 'onboarding';
  SELECT created_at INTO v_created FROM public.profiles WHERE id = v_uid;
  v_new := v_created IS NOT NULL AND v_created >= v_cfg.cutover_at;
  v_eligible := v_new OR v_row.prompt_requested_at IS NOT NULL;
  RETURN jsonb_build_object(
    'success', true,
    'preferences', v_row.event_preferences,
    'preferences_version', COALESCE(v_row.preferences_version, 0),
    'is_new_account', v_new,
    'needs_settings_step', v_eligible AND COALESCE(v_row.settings_onboarded_version, 0) < v_cfg.current_version,
    'needs_preferences_step', v_eligible AND COALESCE(v_row.prefs_onboarded_version, 0) < v_cfg.current_version
  );
END;
$$;

-- Edit from Account (or the onboarding step). Does NOT mark onboarding done.
CREATE OR REPLACE FUNCTION public.save_my_event_preferences(p_preferences jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_ver int;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  IF p_preferences IS NULL OR NOT public.validate_event_preferences(p_preferences) THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_PREFERENCES');
  END IF;
  INSERT INTO public.profile_event_preferences (user_id, event_preferences, preferences_version, preferences_updated_at)
  VALUES (v_uid, p_preferences, 1, now())
  ON CONFLICT (user_id) DO UPDATE
    SET event_preferences = EXCLUDED.event_preferences,
        preferences_version = public.profile_event_preferences.preferences_version + 1,
        preferences_updated_at = now()
  RETURNING preferences_version INTO v_ver;
  RETURN jsonb_build_object('success', true, 'preferences_version', v_ver);
END;
$$;

-- Marks the settings-review step done (idempotent; never touches any setting).
CREATE OR REPLACE FUNCTION public.complete_settings_onboarding()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_cur int;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  SELECT current_version INTO v_cur FROM public.event_onboarding_config WHERE key = 'onboarding';
  INSERT INTO public.profile_event_preferences (user_id, settings_onboarded_version, settings_onboarded_at)
  VALUES (v_uid, v_cur, now())
  ON CONFLICT (user_id) DO UPDATE
    SET settings_onboarded_version = GREATEST(public.profile_event_preferences.settings_onboarded_version, v_cur),
        settings_onboarded_at = COALESCE(public.profile_event_preferences.settings_onboarded_at, now());
  RETURN jsonb_build_object('success', true);
END;
$$;

-- Finishes the five-question step. p_preferences NULL = skipped everything
-- (marker only — no answers are invented). Existing answers are only replaced
-- when a non-null object is passed.
CREATE OR REPLACE FUNCTION public.complete_preferences_onboarding(p_preferences jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_cur int; v_ver int;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  IF p_preferences IS NOT NULL AND NOT public.validate_event_preferences(p_preferences) THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_PREFERENCES');
  END IF;
  SELECT current_version INTO v_cur FROM public.event_onboarding_config WHERE key = 'onboarding';
  INSERT INTO public.profile_event_preferences
    (user_id, event_preferences, preferences_version, preferences_updated_at, prefs_onboarded_version, prefs_onboarded_at)
  VALUES (v_uid, p_preferences, CASE WHEN p_preferences IS NULL THEN 0 ELSE 1 END,
          CASE WHEN p_preferences IS NULL THEN NULL ELSE now() END, v_cur, now())
  ON CONFLICT (user_id) DO UPDATE
    SET event_preferences = COALESCE(EXCLUDED.event_preferences, public.profile_event_preferences.event_preferences),
        preferences_version = public.profile_event_preferences.preferences_version
                              + CASE WHEN p_preferences IS NULL THEN 0 ELSE 1 END,
        preferences_updated_at = CASE WHEN p_preferences IS NULL
                                      THEN public.profile_event_preferences.preferences_updated_at ELSE now() END,
        prefs_onboarded_version = GREATEST(public.profile_event_preferences.prefs_onboarded_version, v_cur),
        prefs_onboarded_at = COALESCE(public.profile_event_preferences.prefs_onboarded_at, now())
  RETURNING preferences_version INTO v_ver;
  RETURN jsonb_build_object('success', true, 'preferences_version', v_ver);
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_event_preferences() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.save_my_event_preferences(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_settings_onboarding() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_preferences_onboarding(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_event_preferences() TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_my_event_preferences(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_settings_onboarding() TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_preferences_onboarding(jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. events.reservation_criteria (default Everyone — existing events unchanged)
-- ---------------------------------------------------------------------------
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS reservation_criteria jsonb NOT NULL
  DEFAULT '{"version":1,"mode":"everyone"}'::jsonb;
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_reservation_criteria_valid;
ALTER TABLE public.events ADD CONSTRAINT events_reservation_criteria_valid
  CHECK (public.validate_reservation_criteria(reservation_criteria));

CREATE OR REPLACE FUNCTION public.set_event_reservation_criteria(p_event_id text, p_criteria jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_ev events%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_criteria IS NULL OR NOT public.validate_reservation_criteria(p_criteria) THEN
    RAISE EXCEPTION 'INVALID_CRITERIA';
  END IF;
  SELECT * INTO v_ev FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVENT_NOT_FOUND'; END IF;
  IF NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_ev.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  -- Existing bookings are untouched: criteria are only checked when a NEW
  -- reservation is made (hold_seats / claim_seats).
  UPDATE events SET reservation_criteria = p_criteria WHERE id = p_event_id;
  RETURN p_criteria;
END;
$$;
REVOKE ALL ON FUNCTION public.set_event_reservation_criteria(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_event_reservation_criteria(text, jsonb) TO authenticated;

-- Evaluate one group. Returns the exact values still needed:
--   all -> the values the guest has NOT declared
--   any -> every listed value when none is declared (they need at least one)
CREATE OR REPLACE FUNCTION public.criteria_group_missing(p_group jsonb, p_declared text[])
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_group IS NULL THEN ARRAY[]::text[]
    WHEN p_group ->> 'rule' = 'all' THEN
      COALESCE((SELECT array_agg(v) FROM jsonb_array_elements_text(p_group -> 'values') v
                 WHERE v <> ALL (COALESCE(p_declared, ARRAY[]::text[]))), ARRAY[]::text[])
    ELSE
      CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements_text(p_group -> 'values') v
                         WHERE v = ANY (COALESCE(p_declared, ARRAY[]::text[])))
           THEN ARRAY[]::text[]
           ELSE ARRAY(SELECT jsonb_array_elements_text(p_group -> 'values'))
      END
  END;
$$;

-- Internal: evaluates criteria for (event, user). Not exposed to clients.
CREATE OR REPLACE FUNCTION public.event_criteria_check(p_criteria jsonb, p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_prefs jsonb;
  v_int text[]; v_goal text[];
  v_mi text[]; v_mg text[];
BEGIN
  IF p_criteria IS NULL OR p_criteria ->> 'mode' IS DISTINCT FROM 'declared' THEN
    RETURN jsonb_build_object('eligible', true, 'mode', 'everyone',
                              'missing_interests', '[]'::jsonb, 'missing_goals', '[]'::jsonb);
  END IF;
  SELECT event_preferences INTO v_prefs FROM public.profile_event_preferences WHERE user_id = p_user;
  -- "no_preference" or a skipped question declares nothing.
  v_int := COALESCE(ARRAY(SELECT jsonb_array_elements_text(
             CASE WHEN jsonb_typeof(v_prefs -> 'interests') = 'array' THEN v_prefs -> 'interests' ELSE '[]'::jsonb END)), ARRAY[]::text[]);
  v_goal := COALESCE(ARRAY(SELECT jsonb_array_elements_text(
             CASE WHEN jsonb_typeof(v_prefs -> 'goals') = 'array' THEN v_prefs -> 'goals' ELSE '[]'::jsonb END)), ARRAY[]::text[]);
  v_mi := public.criteria_group_missing(p_criteria -> 'interests', v_int);
  v_mg := public.criteria_group_missing(p_criteria -> 'goals', v_goal);
  RETURN jsonb_build_object(
    'eligible', cardinality(v_mi) = 0 AND cardinality(v_mg) = 0,
    'mode', 'declared',
    'interest_rule', p_criteria -> 'interests' ->> 'rule',
    'goal_rule', p_criteria -> 'goals' ->> 'rule',
    'missing_interests', to_jsonb(v_mi),
    'missing_goals', to_jsonb(v_mg));
END;
$$;
REVOKE ALL ON FUNCTION public.event_criteria_check(jsonb, uuid) FROM PUBLIC, anon, authenticated;

-- Client-facing: "can I reserve this?" for the CALLER only. Reveals the
-- event's own requirement and the caller's own gap, nothing else.
CREATE OR REPLACE FUNCTION public.check_my_reservation_eligibility(p_event_id text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_ev events%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT * INTO v_ev FROM events WHERE id = p_event_id OR slug = p_event_id OR key = p_event_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND'); END IF;
  IF v_ev.visibility::text <> 'public' AND NOT public.is_event_host(v_ev.id)
     AND NOT public.has_event_invite_access(v_ev.id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;
  IF public.is_event_host(v_ev.id) THEN
    RETURN jsonb_build_object('success', true, 'eligible', true, 'mode', v_ev.reservation_criteria ->> 'mode',
                              'missing_interests', '[]'::jsonb, 'missing_goals', '[]'::jsonb);
  END IF;
  RETURN jsonb_build_object('success', true) || public.event_criteria_check(v_ev.reservation_criteria, auth.uid());
END;
$$;
REVOKE ALL ON FUNCTION public.check_my_reservation_eligibility(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_my_reservation_eligibility(text) TO authenticated;

-- Used inside the booking RPCs (same transaction, after the events row lock).
-- The organizer owner may always book their own event.
CREATE OR REPLACE FUNCTION public.assert_reservation_criteria(p_event events)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_res jsonb;
BEGIN
  IF p_event.reservation_criteria ->> 'mode' IS DISTINCT FROM 'declared' THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM organizers o WHERE o.id = p_event.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    RETURN;
  END IF;
  v_res := public.event_criteria_check(p_event.reservation_criteria, auth.uid());
  IF NOT (v_res ->> 'eligible')::boolean THEN
    RAISE EXCEPTION 'CRITERIA_NOT_MET' USING DETAIL = v_res::text, ERRCODE = 'P0001';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.assert_reservation_criteria(events) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Booking RPCs: byte-for-byte migration 113's versions plus ONE added
--    PERFORM (after the invite gate, before the capacity count — the events
--    row is already FOR UPDATE locked, so a concurrent criteria edit cannot
--    interleave). hold_seats_with_attendees (151) calls hold_seats().
--    gift_ticket / claim_gift_ticket TRANSFER an already-reserved seat; they
--    create no new reservation and are intentionally not gated.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION claim_seats(
  p_event text,
  p_qty int,
  p_note text DEFAULT NULL
)
RETURNS bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev events%ROWTYPE;
  v_taken int;
  v_user profiles%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_booking_code text;
  v_expires_at timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  SELECT * INTO v_user FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND';
  END IF;

  SELECT * INTO v_ev FROM events WHERE id = p_event OR slug = p_event OR key = p_event FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND';
  END IF;

  IF v_ev.status != 'live' AND v_ev.status::text != 'open' THEN
    RAISE EXCEPTION 'EVENT_NOT_LIVE';
  END IF;

  -- Invite-only gate: the organizer owner may always book their own event;
  -- anyone else needs a non-revoked, non-declined, non-expired invite row
  -- addressed to THEM specifically. A pending invite is enough to book —
  -- "accept" is a separate, informational RSVP acknowledgment (see
  -- respond_to_event_invite below), not a hard prerequisite for booking,
  -- per the spec's own "an invite grant is not a ticket" framing (the
  -- ticket rules below are what actually gate the seat, not this switch).
  IF v_ev.visibility = 'invite'
     AND NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_ev.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
  THEN
    IF NOT EXISTS (
      SELECT 1 FROM event_invites ei
      WHERE ei.event_id = v_ev.id AND ei.invited_user_id = auth.uid()
        AND ei.status IN ('pending', 'accepted') AND ei.expires_at > now()
    ) THEN
      RAISE EXCEPTION 'INVITE_REQUIRED';
    END IF;
  END IF;

  PERFORM public.assert_reservation_criteria(v_ev);

  SELECT COALESCE(SUM(qty), 0) INTO v_taken
  FROM bookings
  WHERE event_id = v_ev.id
    AND status IN ('confirmed', 'pending')
    AND (expires_at IS NULL OR expires_at > now());

  IF v_taken + p_qty > v_ev.capacity THEN
    RAISE EXCEPTION 'SOLD_OUT';
  END IF;

  v_booking_code := upper(substr(md5(gen_random_uuid()::text), 1, 6));

  IF v_ev.approval = 'instant' THEN
    INSERT INTO bookings (
      event_id, user_id, qty, total_vnd, code, status, guest_note, confirmed_at
    ) VALUES (
      v_ev.id, auth.uid(), p_qty, v_ev.price_vnd * p_qty, v_booking_code, 'confirmed', p_note, now()
    )
    RETURNING * INTO v_booking;
  ELSE
    v_expires_at := now() + interval '30 minutes';
    INSERT INTO bookings (
      event_id, user_id, qty, total_vnd, code, status, expires_at, guest_note
    ) VALUES (
      v_ev.id, auth.uid(), p_qty, v_ev.price_vnd * p_qty, v_booking_code, 'pending', v_expires_at, p_note
    )
    RETURNING * INTO v_booking;
  END IF;

  IF v_ev.organizer_id IS NOT NULL THEN
    INSERT INTO threads (event_id, guest_id, organizer_id)
    SELECT v_ev.id, auth.uid(), v_ev.organizer_id
    WHERE NOT EXISTS (
      SELECT 1 FROM threads
      WHERE event_id = v_ev.id AND guest_id = auth.uid()
    );
  END IF;

  RETURN v_booking;
END;
$$;
REVOKE EXECUTE ON FUNCTION claim_seats FROM anon;
GRANT EXECUTE ON FUNCTION claim_seats TO authenticated;

CREATE OR REPLACE FUNCTION public.hold_seats(
  p_event text, p_qty int, p_note text DEFAULT NULL,
  p_ip text DEFAULT NULL, p_user_agent text DEFAULT NULL
)
RETURNS bookings
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ev events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_user profiles%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_taken int;
  v_is_free boolean;
  v_hold_minutes int;
  v_ref text;
  v_thread_id uuid;
  v_recipient uuid;
  v_message text;
  v_amount_str text;
  v_pay_lines text := '';
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_qty IS NULL OR p_qty < 1 OR p_qty > 20 THEN RAISE EXCEPTION 'INVALID_QTY'; END IF;

  SELECT * INTO v_user FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;

  -- The lock that makes the count below trustworthy.
  SELECT * INTO v_ev FROM events
   WHERE id = p_event OR slug = p_event OR key = p_event
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVENT_NOT_FOUND'; END IF;
  IF v_ev.status != 'live' AND v_ev.status::text != 'open' THEN RAISE EXCEPTION 'EVENT_NOT_LIVE'; END IF;

  -- Strict invite-only events (migration 113) — same gate as claim_seats
  -- above: the organizer owner may always book their own event; anyone
  -- else needs a non-revoked/non-declined/non-expired invite addressed to
  -- them specifically. This is the check that actually matters, since
  -- this is the function the real reserve flow calls.
  IF v_ev.visibility = 'invite'
     AND NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_ev.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
  THEN
    IF NOT EXISTS (
      SELECT 1 FROM event_invites ei
      WHERE ei.event_id = v_ev.id AND ei.invited_user_id = auth.uid()
        AND ei.status IN ('pending', 'accepted') AND ei.expires_at > now()
    ) THEN
      RAISE EXCEPTION 'INVITE_REQUIRED';
    END IF;
  END IF;

  PERFORM public.assert_reservation_criteria(v_ev);

  SELECT COALESCE(SUM(b.qty), 0) INTO v_taken
  FROM bookings b
  WHERE b.event_id = v_ev.id
    AND booking_holds_seat(b.payment_state, b.hold_expires_at, b.status);

  IF v_taken + p_qty > v_ev.capacity THEN RAISE EXCEPTION 'SOLD_OUT'; END IF;

  IF v_ev.organizer_id IS NOT NULL THEN
    SELECT * INTO v_org FROM organizers WHERE id = v_ev.organizer_id;
  END IF;

  v_is_free := COALESCE(v_ev.price_vnd, 0) <= 0;
  v_hold_minutes := GREATEST(COALESCE(v_ev.hold_minutes, 30), 1);
  v_ref := 'ART' || lpad(nextval('payment_ref_seq')::text, 5, '0');

  INSERT INTO bookings (
    event_id, user_id, qty, total_vnd, code, status, guest_note,
    payment_state, payment_ref, hold_minutes, hold_expires_at, expires_at, confirmed_at
  ) VALUES (
    v_ev.id, auth.uid(), p_qty, COALESCE(v_ev.price_vnd, 0) * p_qty,
    upper(substr(md5(gen_random_uuid()::text), 1, 6)),
    -- Seat status still follows the event's approval mode; payment_state is
    -- the axis that decides whether a ticket exists.
    CASE WHEN v_ev.approval = 'instant' THEN 'confirmed'::booking_status
         ELSE 'pending'::booking_status END,
    p_note,
    CASE WHEN v_is_free THEN 'confirmed'::payment_state
         ELSE 'holding'::payment_state END,
    v_ref, v_hold_minutes,
    CASE WHEN v_is_free THEN NULL ELSE now() + make_interval(mins => v_hold_minutes) END,
    CASE WHEN v_is_free THEN NULL ELSE now() + make_interval(mins => v_hold_minutes) END,
    CASE WHEN v_ev.approval = 'instant' THEN now() ELSE NULL END
  )
  RETURNING * INTO v_booking;

  -- T1: reservation, with the buyer's session metadata.
  PERFORM log_payment_event(
    v_booking.id, 'T1_hold_created', NULL, v_booking.payment_state,
    auth.uid(), 'buyer', p_ip, p_user_agent,
    jsonb_build_object(
      'qty', p_qty, 'total_vnd', v_booking.total_vnd, 'payment_ref', v_ref,
      'hold_minutes', v_hold_minutes, 'hold_expires_at', v_booking.hold_expires_at,
      'is_free', v_is_free
    )
  );

  IF v_is_free THEN
    UPDATE bookings SET
      paid_marked_at = now(), paid_method = 'free',
      verified_at = now(), verified_via = 'free',
      confirmed_at = COALESCE(confirmed_at, now()), status = 'confirmed'
    WHERE id = v_booking.id
    RETURNING * INTO v_booking;

    PERFORM log_payment_event(v_booking.id, 'T3_verified', 'holding', 'confirmed',
                              NULL, 'system', NULL, NULL,
                              jsonb_build_object('via', 'free'));
    BEGIN
      PERFORM ensure_payment_document(v_booking.id, 'invoice');
      PERFORM ensure_payment_document(v_booking.id, 'receipt');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (auth.uid(), 'payment_confirmed', 'Đã xác nhận',
            'Bạn đã tham gia ' || v_ev.name || '. Vé đã sẵn sàng.',
            jsonb_build_object('booking_id', v_booking.id, 'event_id', v_ev.id, 'via', 'free'));
  ELSE
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (auth.uid(), 'hold_created', 'Đã giữ chỗ',
            'Chỗ của bạn cho ' || v_ev.name || ' đang được giữ trong ' || v_hold_minutes
              || ' phút ▪︎ mã ' || v_ref || '. Chuyển khoản và báo lại trước khi hết giờ.',
            jsonb_build_object('booking_id', v_booking.id, 'event_id', v_ev.id,
                               'payment_ref', v_ref, 'hold_expires_at', v_booking.hold_expires_at));
  END IF;

  IF v_ev.organizer_id IS NOT NULL THEN
    INSERT INTO threads (event_id, guest_id, organizer_id)
    SELECT v_ev.id, auth.uid(), v_ev.organizer_id
    WHERE NOT EXISTS (SELECT 1 FROM threads WHERE event_id = v_ev.id AND guest_id = auth.uid());
    SELECT id INTO v_thread_id FROM threads WHERE event_id = v_ev.id AND guest_id = auth.uid();

    IF v_thread_id IS NOT NULL THEN
      IF v_is_free THEN
        v_message := 'Đặt chỗ thành công ▪︎ sự kiện miễn phí, không cần thanh toán.';
      ELSE
        v_amount_str := replace(to_char(v_booking.total_vnd, 'FM999G999G999'), ',', '.') || '₫';
        IF COALESCE(v_org.bank_account_no, '') <> '' THEN
          v_pay_lines := v_pay_lines || 'Ngân hàng: ' || COALESCE(v_org.bank_name, '')
                       || ', STK ' || v_org.bank_account_no
                       || COALESCE(' (' || NULLIF(v_org.bank_account_name, '') || ')', '') || '. ';
        END IF;
        IF COALESCE(v_org.momo_phone, '') <> '' THEN
          v_pay_lines := v_pay_lines || 'MoMo: ' || v_org.momo_phone || '. ';
        END IF;

        v_message := 'Đặt chỗ thành công ▪︎ số tiền ' || v_amount_str
                  || '. Nội dung chuyển khoản bắt buộc: ' || v_ref
                  || '. Giữ chỗ trong ' || v_hold_minutes || ' phút.'
                  || CASE WHEN v_pay_lines = ''
                          THEN ' Người tổ chức sẽ gửi thông tin chuyển khoản sớm.'
                          ELSE ' Chuyển khoản tới: ' || v_pay_lines END
                  || COALESCE(NULLIF(v_org.pay_note, '') || ' ', '')
                  || 'Sau khi chuyển, bấm "Tôi đã chuyển khoản" để giữ chỗ không bị huỷ.';
      END IF;

      INSERT INTO messages (thread_id, sender_id, body, kind)
      VALUES (v_thread_id, auth.uid(), v_message, 'system');
    END IF;

    SELECT COALESCE(v_org.owner_id, v_org.user_id) INTO v_recipient;
    IF v_recipient IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_recipient, 'booking_requested',
        CASE WHEN v_is_free THEN 'Có người tham gia mới' ELSE 'Yêu cầu đặt chỗ mới' END,
        COALESCE(NULLIF(v_user.display_name, ''), 'Một người tham gia')
          || ' đã đặt ' || p_qty || ' chỗ cho ' || v_ev.name
          || CASE WHEN v_is_free THEN '.' ELSE ' ▪︎ mã ' || v_ref || '.' END,
        jsonb_build_object('booking_id', v_booking.id, 'event_id', v_ev.id,
                           'payment_ref', v_ref, 'qty', p_qty,
                           'total_vnd', v_booking.total_vnd, 'is_free', v_is_free)
      );
    END IF;
  END IF;

  RETURN v_booking;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.hold_seats(text, int, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.hold_seats(text, int, text, text, text) TO authenticated;
