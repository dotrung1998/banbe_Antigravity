-- 165: rewards (coins), milestone badges, activity streak, cosmetic unlocks.
-- Additive only. Nothing here is applied until `supabase db push`; see
-- .claude/notes/36-rewards-badges-following-map-foryou.md for the product rules.
--
-- Principles
--   * Server-authoritative: every award comes from a database fact (a host-confirmed
--     check_ins row, a completed preferences onboarding). No client call can credit coins,
--     set a balance, claim attendance or choose an award amount.
--   * Append-only ledger (reward_ledger): UPDATE/DELETE are blocked; a wrong award is undone
--     by a REVERSAL entry, never an edit. UNIQUE (user_id, source_key) makes every award
--     idempotent across devices, retries and check-in undo / re-check-in cycles.
--   * Everything is private and owner-scoped. Tables have RLS on and NO client grants; the only
--     doors are the SECURITY DEFINER RPCs below, which read auth.uid().
--   * Coins have no cash value, cannot be bought or transferred, and never affect booking,
--     priority or eligibility: nothing outside this file reads them.
--   * A failure in reward bookkeeping NEVER blocks a legitimate check-in or booking: the
--     triggers catch errors, log a WARNING and let the original statement succeed.

-- ---------------------------------------------------------------------------
-- 1. Versioned rules (one active row). Values are an MVP product proposal.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.reward_rule_versions (
  version    int PRIMARY KEY,
  is_active  boolean NOT NULL DEFAULT false,
  rules      jsonb NOT NULL,
  notes      text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS reward_rule_versions_one_active ON public.reward_rule_versions ((true)) WHERE is_active;

INSERT INTO public.reward_rule_versions (version, is_active, rules, notes) VALUES (
  1, true,
  jsonb_build_object(
    'timezone', 'Asia/Ho_Chi_Minh',            -- one fixed zone for every streak date and monthly cap (no DST)
    'onboarding_coins', 10,                    -- once per account, when the preference questions are completed
    'attendance_coins', 20,                    -- per DISTINCT event, host-confirmed
    'attendance_coin_cap_per_month', 10        -- events/month that still pay coins (= 200 coins); beyond it the award is 0
  ),
  'MVP proposal, not market-derived. No coins for app opens, spending, likes, follows, repeated saves, uploads, cancellations or consent.'
) ON CONFLICT (version) DO NOTHING;

CREATE OR REPLACE FUNCTION public.rewards_rules()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT r.rules || jsonb_build_object('version', r.version) FROM public.reward_rule_versions r WHERE r.is_active LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.rewards_tz()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(public.rewards_rules() ->> 'timezone', 'Asia/Ho_Chi_Minh')
$$;

-- The streak/cap calendar date of an instant, in the fixed policy zone.
CREATE OR REPLACE FUNCTION public.rewards_local_date(p_ts timestamptz)
RETURNS date LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT (p_ts AT TIME ZONE public.rewards_tz())::date
$$;

-- ---------------------------------------------------------------------------
-- 2. Append-only ledger
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.reward_ledger (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  entry_type    text NOT NULL CHECK (entry_type IN ('award', 'reversal', 'redemption')),
  amount        int  NOT NULL,
  source_key    text NOT NULL,
  reverses_id   uuid REFERENCES public.reward_ledger(id),
  rules_version int  NOT NULL,
  reason        text NOT NULL,
  ref           jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reward_ledger_unique_source UNIQUE (user_id, source_key),
  CONSTRAINT reward_ledger_sign CHECK (
    (entry_type = 'award' AND amount >= 0) OR (entry_type IN ('reversal', 'redemption') AND amount <= 0)),
  CONSTRAINT reward_ledger_reversal_link CHECK ((entry_type = 'reversal') = (reverses_id IS NOT NULL))
);
-- An award can be reversed at most once.
CREATE UNIQUE INDEX IF NOT EXISTS reward_ledger_one_reversal ON public.reward_ledger (reverses_id) WHERE reverses_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS reward_ledger_user_time ON public.reward_ledger (user_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.reward_ledger_append_only()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- The only permitted removal is the cascade from deleting the account itself.
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = OLD.user_id) THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'reward_ledger is append-only (use a reversal entry)' USING ERRCODE = 'restrict_violation';
END;
$$;
DROP TRIGGER IF EXISTS reward_ledger_no_update ON public.reward_ledger;
CREATE TRIGGER reward_ledger_no_update BEFORE UPDATE OR DELETE ON public.reward_ledger
  FOR EACH ROW EXECUTE FUNCTION public.reward_ledger_append_only();

-- ---------------------------------------------------------------------------
-- 3. Qualifying-attendance facts (what badges and awards are derived from)
-- ---------------------------------------------------------------------------
-- reward_attendance_sources: WHICH booking/seat currently proves a user attended an event.
-- reward_attendances: one row per (user, event); valid while at least one source exists.
CREATE TABLE IF NOT EXISTS public.reward_attendances (
  user_id         uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_id        text NOT NULL,
  booking_id      uuid,
  cat_key         text,
  valid           boolean NOT NULL DEFAULT true,
  cycles          int NOT NULL DEFAULT 1,
  first_valid_at  timestamptz NOT NULL DEFAULT now(),
  last_changed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, event_id)
);
CREATE INDEX IF NOT EXISTS reward_attendances_event ON public.reward_attendances (event_id) WHERE valid;

CREATE TABLE IF NOT EXISTS public.reward_attendance_sources (
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_id   text NOT NULL,
  booking_id uuid NOT NULL,
  kind       text NOT NULL CHECK (kind IN ('booking', 'seat')),
  ref_id     uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, ref_id)
);
CREATE INDEX IF NOT EXISTS reward_attendance_sources_booking ON public.reward_attendance_sources (booking_id);

-- Active days (streak). Written only by the server (verified save, valid attendance).
CREATE TABLE IF NOT EXISTS public.reward_active_days (
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  local_date date NOT NULL,
  source     text NOT NULL CHECK (source IN ('save', 'attendance')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, local_date)
);

-- ---------------------------------------------------------------------------
-- 4. Badges, cosmetic catalog, unlocks
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.reward_badge_defs (
  code     text PRIMARY KEY,
  sort     int  NOT NULL,
  target   int  NOT NULL CHECK (target > 0),
  title_vi text NOT NULL, title_en text NOT NULL,
  desc_vi  text NOT NULL, desc_en  text NOT NULL
);
INSERT INTO public.reward_badge_defs (code, sort, target, title_vi, title_en, desc_vi, desc_en) VALUES
  ('ready_to_explore', 10, 1, 'Sẵn sàng khám phá', 'Ready to explore',
     'Hoàn thành các câu hỏi sở thích sự kiện.', 'Complete the event preference questions.'),
  ('first_outing', 20, 1, 'Buổi đầu tiên', 'First outing',
     'Có 1 sự kiện được người tổ chức xác nhận bạn đã tham dự.', '1 event where the host confirmed you attended.'),
  ('regular', 30, 5, 'Thường xuyên', 'Regular',
     'Tham dự 5 sự kiện khác nhau.', 'Attend 5 different events.'),
  ('explorer', 40, 3, 'Người khám phá', 'Explorer',
     'Tham dự sự kiện thuộc 3 danh mục khác nhau.', 'Attend events in 3 different categories.'),
  ('community_regular', 50, 10, 'Gương mặt quen thuộc', 'Community regular',
     'Tham dự 10 sự kiện khác nhau.', 'Attend 10 different events.'),
  ('host_milestone', 60, 3, 'Cột mốc người tổ chức', 'Host milestone',
     'Hoàn thành 3 sự kiện, mỗi sự kiện có ít nhất một khách hợp lệ không phải chủ sự kiện.',
     'Complete 3 events, each with at least one legitimate attendee who is not the owner.')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.reward_user_badges (
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  badge_code text NOT NULL REFERENCES public.reward_badge_defs(code),
  earned_at  timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  PRIMARY KEY (user_id, badge_code)
);
-- Badges are private. There is deliberately no public/visitor read of this table.

-- Cosmetic catalog: each item unlocks one optional keychain design (the existing charm system).
CREATE TABLE IF NOT EXISTS public.reward_catalog (
  code      text PRIMARY KEY,
  kind      text NOT NULL CHECK (kind IN ('keychain_design')),
  design_id text NOT NULL UNIQUE,
  price     int  NOT NULL CHECK (price > 0),
  sort      int  NOT NULL DEFAULT 0,
  active    boolean NOT NULL DEFAULT true
);
INSERT INTO public.reward_catalog (code, kind, design_id, price, sort) VALUES
  ('rwd-comet',   'keychain_design', 'rwd-comet',   40, 10),
  ('rwd-lantern', 'keychain_design', 'rwd-lantern', 80, 20),
  ('rwd-crown',   'keychain_design', 'rwd-crown',  120, 30)
ON CONFLICT (code) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.reward_unlocks (
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  item_code   text NOT NULL REFERENCES public.reward_catalog(code),
  ledger_id   uuid NOT NULL UNIQUE REFERENCES public.reward_ledger(id),
  unlocked_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, item_code)
);

-- No client access to any of these tables; the RPCs below are the only doors.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['reward_rule_versions','reward_ledger','reward_attendances','reward_attendance_sources',
                           'reward_active_days','reward_badge_defs','reward_user_badges','reward_catalog','reward_unlocks']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated, PUBLIC', t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 5. favorites.created_at (so a "save" can be verified as new). Old rows stay NULL = never eligible.
-- ---------------------------------------------------------------------------
ALTER TABLE public.favorites ADD COLUMN IF NOT EXISTS created_at timestamptz;
ALTER TABLE public.favorites ALTER COLUMN created_at SET DEFAULT now();
CREATE OR REPLACE FUNCTION public.favorites_stamp_created_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.created_at := now(); RETURN NEW; END;
$$;
DROP TRIGGER IF EXISTS favorites_stamp_created_at ON public.favorites;
CREATE TRIGGER favorites_stamp_created_at BEFORE INSERT ON public.favorites
  FOR EACH ROW EXECUTE FUNCTION public.favorites_stamp_created_at();

-- ---------------------------------------------------------------------------
-- 6. Internal ledger helpers (not callable by clients)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rewards_lock_user(p_uid uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT pg_advisory_xact_lock(hashtextextended('rewards-user:' || p_uid::text, 0))
$$;

CREATE OR REPLACE FUNCTION public.rewards_balance(p_uid uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(sum(amount), 0)::int FROM public.reward_ledger WHERE user_id = p_uid
$$;

-- Idempotent insert: a repeated source_key (retry, second device, undo/redo) is a no-op returning NULL.
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

-- Event owner account ids (organizer owner_id / user_id).
CREATE OR REPLACE FUNCTION public.rewards_event_owner_ids(p_event text)
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT x FROM (
    SELECT o.owner_id AS x FROM public.events e JOIN public.organizers o ON o.id = e.organizer_id WHERE e.id = p_event
    UNION
    SELECT o.user_id FROM public.events e JOIN public.organizers o ON o.id = e.organizer_id WHERE e.id = p_event
  ) s WHERE x IS NOT NULL
$$;

-- Excludes own-event farming: the event's owner, any accepted team member, and self check-ins.
CREATE OR REPLACE FUNCTION public.rewards_attendee_eligible(p_uid uuid, p_event text, p_checked_in_by uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT p_uid IS NOT NULL
     AND p_checked_in_by IS DISTINCT FROM p_uid
     AND NOT EXISTS (SELECT 1 FROM public.rewards_event_owner_ids(p_event) o WHERE o = p_uid)
     AND NOT EXISTS (SELECT 1 FROM public.events e
                       JOIN public.organizer_members m ON m.organizer_id = e.organizer_id
                      WHERE e.id = p_event AND m.user_id = p_uid AND m.status = 'accepted'::organizer_member_status)
$$;

-- ---------------------------------------------------------------------------
-- 7. Badges
-- ---------------------------------------------------------------------------
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
RETURNS int LANGUAGE sql IMMUTABLE AS $$
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

-- ---------------------------------------------------------------------------
-- 8. Attendance awards
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

CREATE OR REPLACE FUNCTION public.rewards_reverse_attendance(p_uid uuid, p_event text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE a public.reward_ledger%ROWTYPE;
BEGIN
  PERFORM public.rewards_lock_user(p_uid);
  FOR a IN SELECT * FROM public.reward_ledger l
            WHERE l.user_id = p_uid AND l.entry_type = 'award' AND l.source_key LIKE 'attend:%'
              AND l.ref ->> 'event_id' = p_event
              AND NOT EXISTS (SELECT 1 FROM public.reward_ledger r WHERE r.reverses_id = l.id)
  LOOP
    PERFORM public.rewards_add_entry(p_uid, 'reversal', -a.amount, 'reverse:' || a.id::text, a.id, 'attendance_reversed', a.ref);
  END LOOP;
END;
$$;

-- A source appeared for (user, event): mark the fact valid; award once per validity cycle.
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

-- The last source for (user, event) disappeared: invalidate and reverse the award.
CREATE OR REPLACE FUNCTION public.rewards_invalidate_if_orphan(p_uid uuid, p_event text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_owner uuid;
BEGIN
  PERFORM public.rewards_lock_user(p_uid);
  IF EXISTS (SELECT 1 FROM public.reward_attendance_sources WHERE user_id = p_uid AND event_id = p_event) THEN RETURN; END IF;
  UPDATE public.reward_attendances SET valid = false, last_changed_at = now()
   WHERE user_id = p_uid AND event_id = p_event AND valid;
  IF NOT FOUND THEN RETURN; END IF;
  PERFORM public.rewards_reverse_attendance(p_uid, p_event);
  PERFORM public.rewards_refresh_badges(p_uid);
  FOR v_owner IN SELECT public.rewards_event_owner_ids(p_event) LOOP PERFORM public.rewards_refresh_badges(v_owner); END LOOP;
END;
$$;

-- Who SHOULD currently be credited for this booking, from live facts only.
--   * 'booking': the account the booking is for — for a gifted seat ONLY the claiming recipient
--     (an unclaimed gift credits nobody, never the purchaser who did not attend).
--   * 'seat': an attendee seat imported by another account, once that seat itself is checked in.
CREATE OR REPLACE FUNCTION public.rewards_desired_sources(p_booking uuid)
RETURNS TABLE (user_id uuid, event_id text, kind text, ref_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
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
$$;

-- Reconciles the stored sources for one booking with the desired set. Idempotent: running it
-- twice (retry, trigger + trigger) changes nothing the second time.
CREATE OR REPLACE FUNCTION public.rewards_sync_booking(p_booking uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE r record;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('rewards-booking:' || p_booking::text, 0));
  FOR r IN SELECT s.user_id, s.event_id, s.ref_id FROM public.reward_attendance_sources s
            WHERE s.booking_id = p_booking
              AND NOT EXISTS (SELECT 1 FROM public.rewards_desired_sources(p_booking) d WHERE d.user_id = s.user_id AND d.ref_id = s.ref_id)
  LOOP
    DELETE FROM public.reward_attendance_sources WHERE user_id = r.user_id AND ref_id = r.ref_id;
    PERFORM public.rewards_invalidate_if_orphan(r.user_id, r.event_id);
  END LOOP;
  FOR r IN SELECT d.user_id, d.event_id, d.kind, d.ref_id FROM public.rewards_desired_sources(p_booking) d
            WHERE NOT EXISTS (SELECT 1 FROM public.reward_attendance_sources s WHERE s.user_id = d.user_id AND s.ref_id = d.ref_id)
  LOOP
    INSERT INTO public.reward_attendance_sources (user_id, event_id, booking_id, kind, ref_id)
    VALUES (r.user_id, r.event_id, p_booking, r.kind, r.ref_id) ON CONFLICT DO NOTHING;
    PERFORM public.rewards_validate_attendance(r.user_id, r.event_id, p_booking);
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. Triggers (never allowed to break the original statement)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rewards_trg_checkin()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_b uuid := COALESCE(CASE WHEN TG_OP = 'DELETE' THEN OLD.booking_id ELSE NEW.booking_id END, NULL);
BEGIN
  IF v_b IS NOT NULL THEN
    BEGIN
      PERFORM public.rewards_sync_booking(v_b);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'rewards sync failed for booking %: % (%)', v_b, SQLERRM, SQLSTATE;
    END;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS rewards_checkin_ins ON public.check_ins;
DROP TRIGGER IF EXISTS rewards_checkin_del ON public.check_ins;
CREATE TRIGGER rewards_checkin_ins AFTER INSERT ON public.check_ins FOR EACH ROW EXECUTE FUNCTION public.rewards_trg_checkin();
CREATE TRIGGER rewards_checkin_del AFTER DELETE ON public.check_ins FOR EACH ROW EXECUTE FUNCTION public.rewards_trg_checkin();

CREATE OR REPLACE FUNCTION public.rewards_trg_seat_checkin()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  BEGIN
    PERFORM public.rewards_sync_booking(NEW.booking_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'rewards seat sync failed for booking %: % (%)', NEW.booking_id, SQLERRM, SQLSTATE;
  END;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS rewards_seat_checkin ON public.booking_attendees;
CREATE TRIGGER rewards_seat_checkin AFTER UPDATE OF checked_in_at ON public.booking_attendees
  FOR EACH ROW WHEN (OLD.checked_in_at IS DISTINCT FROM NEW.checked_in_at) EXECUTE FUNCTION public.rewards_trg_seat_checkin();

-- Cancelling an event invalidates its attendance (and reverses the coins); ending it can complete a host milestone.
CREATE OR REPLACE FUNCTION public.rewards_trg_event_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
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
$$;
DROP TRIGGER IF EXISTS rewards_event_status ON public.events;
CREATE TRIGGER rewards_event_status AFTER UPDATE OF status ON public.events
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status IN ('cancelled', 'ended'))
  EXECUTE FUNCTION public.rewards_trg_event_status();

-- Completing the preference onboarding with answers (not skipping) pays once, on the FIRST
-- 0 -> completed transition. Accounts that completed earlier are never back-filled by this trigger.
CREATE OR REPLACE FUNCTION public.rewards_trg_onboarding()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_coins int;
BEGIN
  BEGIN
    IF NEW.prefs_onboarded_version > 0 AND NEW.event_preferences IS NOT NULL
       AND (TG_OP = 'INSERT' OR COALESCE(OLD.prefs_onboarded_version, 0) = 0) THEN
      v_coins := COALESCE((public.rewards_rules() ->> 'onboarding_coins')::int, 0);
      PERFORM public.rewards_add_entry(NEW.user_id, 'award', v_coins, 'onboarding:preferences', NULL, 'onboarding_preferences', '{}'::jsonb);
      PERFORM public.rewards_refresh_badges(NEW.user_id);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'rewards onboarding award failed for user %: % (%)', NEW.user_id, SQLERRM, SQLSTATE;
  END;
  RETURN NULL;
END;
$$;
DO $$
BEGIN
  IF to_regclass('public.profile_event_preferences') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS rewards_onboarding ON public.profile_event_preferences';
    EXECUTE 'CREATE TRIGGER rewards_onboarding AFTER INSERT OR UPDATE OF prefs_onboarded_version ON public.profile_event_preferences
             FOR EACH ROW EXECUTE FUNCTION public.rewards_trg_onboarding()';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 10. Streak
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 11. Client RPCs (authenticated, owner-scoped via auth.uid())
-- ---------------------------------------------------------------------------
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

-- Design ids this account unlocked (keychain picker); the free 24 are never in this list.
CREATE OR REPLACE FUNCTION public.get_my_unlocked_cosmetics()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  RETURN jsonb_build_object('success', true, 'design_ids', COALESCE((
    SELECT jsonb_agg(c.design_id ORDER BY c.sort) FROM public.reward_unlocks u JOIN public.reward_catalog c ON c.code = u.item_code
     WHERE u.user_id = v_uid), '[]'::jsonb));
END;
$$;

-- Transactional redemption. Serialised per user, idempotent per item, balance never trusted from the client.
CREATE OR REPLACE FUNCTION public.redeem_reward(p_item_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_item public.reward_catalog%ROWTYPE; v_bal int; v_lid uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  PERFORM public.rewards_lock_user(v_uid);
  SELECT * INTO v_item FROM public.reward_catalog WHERE code = p_item_code AND active;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_FOUND'); END IF;
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

-- Deliberate-action days. 'save' is verified against the favorites row itself (created by the
-- server clock, within the last 36 h); attendance days are written by the check-in trigger.
-- App opens, polls and searches never count. Counts once per local date; never touches coins.
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

-- ---------------------------------------------------------------------------
-- 12. Keychain: three reward designs, locked until redeemed. The 24 built-in designs stay free.
-- ---------------------------------------------------------------------------
ALTER TABLE public.profile_keychains DROP CONSTRAINT IF EXISTS profile_keychains_design_id_check;
ALTER TABLE public.profile_keychains ADD CONSTRAINT profile_keychains_design_id_check CHECK (design_id IN (
  'sky-star','sky-moon','sky-cloud','love-heart','love-ribbon','love-bow',
  'bloom-flower','bloom-tulip','bloom-strawberry','bloom-lemon','cafe-cup','cafe-note','cafe-vinyl',
  'pals-cat','pals-bear','pals-paw','trip-ticket','trip-plane','trip-compass','trip-suitcase',
  'banbe-b','banbe-stub','banbe-spark','banbe-wave',
  'rwd-comet','rwd-lantern','rwd-crown',
  'custom'));

-- Also enforced at the table (owner policies allow direct writes): a reward design needs an unlock.
CREATE OR REPLACE FUNCTION public.profile_keychains_require_unlock()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.reward_catalog c WHERE c.design_id = NEW.design_id)
     AND NOT EXISTS (SELECT 1 FROM public.reward_unlocks u JOIN public.reward_catalog c ON c.code = u.item_code
                      WHERE u.user_id = NEW.user_id AND c.design_id = NEW.design_id) THEN
    RAISE EXCEPTION 'DESIGN_LOCKED' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS profile_keychains_require_unlock ON public.profile_keychains;
CREATE TRIGGER profile_keychains_require_unlock BEFORE INSERT OR UPDATE OF design_id ON public.profile_keychains
  FOR EACH ROW EXECUTE FUNCTION public.profile_keychains_require_unlock();

-- save_my_keychain: unchanged except (a) it accepts the three reward ids and (b) returns DESIGN_LOCKED
-- for one the caller has not unlocked.
CREATE OR REPLACE FUNCTION public.save_my_keychain(p_config jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  cur public.profile_keychains%ROWTYPE;
  v_enabled boolean; v_design text; v_anchor text; v_size text; v_motion boolean; v_asset uuid;
  v_tmp text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_CONFIG');
  END IF;

  SELECT * INTO cur FROM public.profile_keychains WHERE user_id = v_uid;
  v_enabled := COALESCE(cur.enabled, false);
  v_design  := COALESCE(cur.design_id, 'sky-star');
  v_anchor  := COALESCE(cur.anchor, 'top_right');
  v_size    := COALESCE(cur.size, 'm');
  v_motion  := COALESCE(cur.motion_enabled, true);
  v_asset   := cur.custom_asset_id;

  IF p_config ? 'enabled' THEN
    IF jsonb_typeof(p_config->'enabled') <> 'boolean' THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_ENABLED'); END IF;
    v_enabled := (p_config->>'enabled')::boolean;
  END IF;
  IF p_config ? 'motionEnabled' THEN
    IF jsonb_typeof(p_config->'motionEnabled') <> 'boolean' THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_MOTION'); END IF;
    v_motion := (p_config->>'motionEnabled')::boolean;
  END IF;
  IF p_config ? 'designId' THEN
    IF jsonb_typeof(p_config->'designId') <> 'string' OR (p_config->>'designId') NOT IN (
      'sky-star','sky-moon','sky-cloud','love-heart','love-ribbon','love-bow',
      'bloom-flower','bloom-tulip','bloom-strawberry','bloom-lemon','cafe-cup','cafe-note','cafe-vinyl',
      'pals-cat','pals-bear','pals-paw','trip-ticket','trip-plane','trip-compass','trip-suitcase',
      'banbe-b','banbe-stub','banbe-spark','banbe-wave','rwd-comet','rwd-lantern','rwd-crown','custom') THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_DESIGN');
    END IF;
    v_design := p_config->>'designId';
  END IF;
  IF p_config ? 'anchor' THEN
    IF jsonb_typeof(p_config->'anchor') <> 'string' OR (p_config->>'anchor') NOT IN ('top_left','top_right','bottom_left','bottom_right') THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_ANCHOR');
    END IF;
    v_anchor := p_config->>'anchor';
  END IF;
  IF p_config ? 'size' THEN
    IF jsonb_typeof(p_config->'size') <> 'string' OR (p_config->>'size') NOT IN ('s','m','l') THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_SIZE');
    END IF;
    v_size := p_config->>'size';
  END IF;
  IF p_config ? 'customAssetId' THEN
    IF jsonb_typeof(p_config->'customAssetId') = 'null' THEN
      v_asset := NULL;
    ELSIF jsonb_typeof(p_config->'customAssetId') = 'string' THEN
      v_tmp := p_config->>'customAssetId';
      IF v_tmp !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_ASSET');
      END IF;
      v_asset := v_tmp::uuid;
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_ASSET');
    END IF;
  END IF;

  -- A reward design must have been redeemed by this account.
  IF EXISTS (SELECT 1 FROM public.reward_catalog c WHERE c.design_id = v_design)
     AND NOT EXISTS (SELECT 1 FROM public.reward_unlocks u JOIN public.reward_catalog c ON c.code = u.item_code
                      WHERE u.user_id = v_uid AND c.design_id = v_design) THEN
    RETURN jsonb_build_object('success', false, 'error', 'DESIGN_LOCKED');
  END IF;

  -- A referenced asset must be a READY asset owned by the caller.
  IF v_asset IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.keychain_assets WHERE id = v_asset AND owner_id = v_uid AND status = 'ready'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ASSET_NOT_READY');
  END IF;
  IF v_design = 'custom' AND v_asset IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'CUSTOM_ASSET_REQUIRED');
  END IF;

  INSERT INTO public.profile_keychains (user_id, enabled, design_id, anchor, size, motion_enabled, custom_asset_id, updated_at)
  VALUES (v_uid, v_enabled, v_design, v_anchor, v_size, v_motion, v_asset, now())
  ON CONFLICT (user_id) DO UPDATE
    SET enabled = EXCLUDED.enabled, design_id = EXCLUDED.design_id, anchor = EXCLUDED.anchor, size = EXCLUDED.size,
        motion_enabled = EXCLUDED.motion_enabled, custom_asset_id = EXCLUDED.custom_asset_id, updated_at = now();

  RETURN jsonb_build_object('success', true, 'keychain', public.keychain_config_json(v_uid, false));
END;
$$;

-- ---------------------------------------------------------------------------
-- 13. Privileges: internal helpers are server-only; the RPCs are authenticated-only.
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'rewards_rules()','rewards_tz()','rewards_local_date(timestamptz)','rewards_lock_user(uuid)','rewards_balance(uuid)',
    'rewards_add_entry(uuid,text,int,text,uuid,text,jsonb)','rewards_event_owner_ids(text)','rewards_attendee_eligible(uuid,text,uuid)',
    'rewards_badge_counts(uuid)','rewards_badge_progress_of(text,jsonb)','rewards_refresh_badges(uuid)',
    'rewards_award_attendance(uuid,text,int)','rewards_reverse_attendance(uuid,text)','rewards_validate_attendance(uuid,text,uuid)',
    'rewards_invalidate_if_orphan(uuid,text)','rewards_desired_sources(uuid)','rewards_sync_booking(uuid)','rewards_streak_of(uuid)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM anon, authenticated, PUBLIC', f);
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.get_my_reward_summary() FROM anon, PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_rewards() FROM anon, PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_unlocked_cosmetics() FROM anon, PUBLIC;
REVOKE ALL ON FUNCTION public.redeem_reward(text) FROM anon, PUBLIC;
REVOKE ALL ON FUNCTION public.record_active_day(text, text) FROM anon, PUBLIC;
REVOKE ALL ON FUNCTION public.save_my_keychain(jsonb) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_reward_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_rewards() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_unlocked_cosmetics() TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_reward(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_active_day(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_my_keychain(jsonb) TO authenticated;
