-- Migration 123: phone verification + date-of-birth enrollment, per-session
-- "Confirm date of birth" gate, and host promotional-message consent.
--
-- NOT APPLIED ANYWHERE by whoever authored it. Review, then `supabase db push`.
-- Nothing in here reads or exposes a stored date of birth to any client.
--
-- What this adds
--   1. user_private_dob            — the DOB, unreadable by any client role.
--   2. account_phone_grandfathered — the ONE-TIME legacy cohort that is exempt
--      from the NEW phone-verification requirement (and from needing a DOB).
--      Phones are NOT marked verified for them.
--   3. dob_session_confirmations   — "this auth SESSION passed Confirm date of
--      birth". Bound to auth.sessions, so a new login (new session) must
--      confirm again, a refresh keeps the same session, and signing out /
--      revoking the session deletes the confirmation.
--   4. dob_attempts                — server-side rate limit / lockout.
--   5. account_gate_ok()           — one predicate, used by RESTRICTIVE RLS
--      policies on user-private tables, so a signed-in but un-enrolled /
--      un-confirmed session reads and writes nothing there.
--   6. host promo consent + one-recipient-at-a-time compose RPCs.
--
-- KNOWN LIMIT: the gate is enforced through RLS on the tables listed in
-- section 7. SECURITY DEFINER RPCs (hold_seats, etc.) run as their owner and
-- are not individually gated by this migration.

-- ---------------------------------------------------------------------------
-- 0. One-time marker (makes the cohort + seed run exactly once)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.account_gate_migrations (
  name text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.account_gate_migrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_gate_migrations FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Tables (no client policies; client roles have no table privileges)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_private_dob (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  date_of_birth date NOT NULL CHECK (date_of_birth >= DATE '1900-01-01'),
  source text NOT NULL DEFAULT 'user',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.user_private_dob_not_future()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.date_of_birth > current_date THEN
    RAISE EXCEPTION 'DOB_IN_FUTURE';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_user_private_dob_not_future ON public.user_private_dob;
CREATE TRIGGER trg_user_private_dob_not_future
  BEFORE INSERT OR UPDATE ON public.user_private_dob
  FOR EACH ROW EXECUTE FUNCTION public.user_private_dob_not_future();

CREATE TABLE IF NOT EXISTS public.account_phone_grandfathered (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  cohort text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.dob_session_confirmations (
  session_id uuid PRIMARY KEY REFERENCES auth.sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  confirmed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.dob_attempts (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  failures int NOT NULL DEFAULT 0,
  window_started_at timestamptz NOT NULL DEFAULT now(),
  locked_until timestamptz
);

ALTER TABLE public.user_private_dob ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_phone_grandfathered ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dob_session_confirmations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dob_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_private_dob, public.account_phone_grandfathered,
  public.dob_session_confirmations, public.dob_attempts FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Helpers
-- ---------------------------------------------------------------------------
-- The caller's auth session id from the JWT (null if absent/malformed).
CREATE OR REPLACE FUNCTION public.current_session_id()
RETURNS uuid LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN nullif(auth.jwt() ->> 'session_id', '')::uuid;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

-- Full gate status for the caller. Booleans only — never the DOB itself.
CREATE OR REPLACE FUNCTION public.account_gate_status()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sid uuid := public.current_session_id();
  v_grand boolean;
  v_phone_ok boolean;
  v_has_dob boolean;
  v_confirmed boolean;
  v_locked timestamptz;
  v_phone_required boolean;
  v_dob_enroll boolean;
  v_dob_confirm boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ready', false, 'error', 'AUTH_REQUIRED');
  END IF;

  v_grand := EXISTS (SELECT 1 FROM public.account_phone_grandfathered WHERE user_id = v_uid);
  v_phone_ok := EXISTS (
    SELECT 1 FROM auth.users u
    WHERE u.id = v_uid AND coalesce(u.phone, '') <> '' AND u.phone_confirmed_at IS NOT NULL
  );
  v_has_dob := EXISTS (SELECT 1 FROM public.user_private_dob WHERE user_id = v_uid);
  v_confirmed := v_sid IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.dob_session_confirmations WHERE session_id = v_sid AND user_id = v_uid
  );
  SELECT locked_until INTO v_locked FROM public.dob_attempts
   WHERE user_id = v_uid AND locked_until > now();

  -- New registrations need a verified phone and a DOB. The grandfathered
  -- legacy cohort needs neither (their current login is unchanged).
  v_phone_required := NOT v_grand AND NOT v_phone_ok;
  v_dob_enroll := NOT v_grand AND NOT v_has_dob;
  -- Anyone who HAS a DOB must confirm it once per session.
  v_dob_confirm := v_has_dob AND NOT v_confirmed;

  RETURN jsonb_build_object(
    'ready', NOT (v_phone_required OR v_dob_enroll OR v_dob_confirm),
    'phone_required', v_phone_required,
    'phone_verified', v_phone_ok,
    'dob_enrollment_required', v_dob_enroll,
    'dob_confirmation_required', v_dob_confirm,
    'locked_until', v_locked
  );
END;
$$;

-- The predicate RLS uses. Wrapped in (SELECT ...) in policies so it runs once
-- per statement.
CREATE OR REPLACE FUNCTION public.account_gate_ok()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT coalesce((public.account_gate_status() ->> 'ready')::boolean, false);
$$;

-- ---------------------------------------------------------------------------
-- 3. Client RPCs
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.current_session_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.account_gate_status() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.account_gate_ok() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.account_gate_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.account_gate_ok() TO authenticated;

-- Enrollment: store the DOB ONCE for a new registration. Never overwrites,
-- never callable before the phone is verified (for non-grandfathered users),
-- so the order phone -> DOB is enforced here, not just in the UI. The user
-- just typed it, so this session counts as confirmed.
CREATE OR REPLACE FUNCTION public.set_date_of_birth(p_dob date)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sid uuid := public.current_session_id();
  v_grand boolean;
  v_phone_ok boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF p_dob IS NULL OR p_dob < DATE '1900-01-01' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_DOB');
  END IF;
  IF p_dob > current_date THEN
    RETURN jsonb_build_object('success', false, 'error', 'DOB_IN_FUTURE');
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_private_dob WHERE user_id = v_uid) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_SET');
  END IF;

  v_grand := EXISTS (SELECT 1 FROM public.account_phone_grandfathered WHERE user_id = v_uid);
  v_phone_ok := EXISTS (
    SELECT 1 FROM auth.users u
    WHERE u.id = v_uid AND coalesce(u.phone, '') <> '' AND u.phone_confirmed_at IS NOT NULL
  );
  IF NOT v_grand AND NOT v_phone_ok THEN
    RETURN jsonb_build_object('success', false, 'error', 'PHONE_NOT_VERIFIED');
  END IF;

  INSERT INTO public.user_private_dob (user_id, date_of_birth, source)
  VALUES (v_uid, p_dob, 'signup')
  ON CONFLICT (user_id) DO NOTHING;

  IF v_sid IS NOT NULL THEN
    INSERT INTO public.dob_session_confirmations (session_id, user_id)
    VALUES (v_sid, v_uid)
    ON CONFLICT (session_id) DO NOTHING;
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.set_date_of_birth(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_date_of_birth(date) TO authenticated;

-- Confirm date of birth (NOT a second factor): session-bound, rate limited.
-- 5 wrong answers inside 15 minutes lock the account's confirmations for 15
-- minutes. The stored value is only ever COMPARED here, never returned, and is
-- never put in an error message.
CREATE OR REPLACE FUNCTION public.confirm_date_of_birth(p_dob date)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sid uuid := public.current_session_id();
  v_stored date;
  v_att public.dob_attempts%ROWTYPE;
  v_max constant int := 5;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF v_sid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'SESSION_REQUIRED');
  END IF;

  SELECT date_of_birth INTO v_stored FROM public.user_private_dob WHERE user_id = v_uid;
  IF v_stored IS NULL THEN
    RETURN jsonb_build_object('success', true, 'not_required', true);
  END IF;

  INSERT INTO public.dob_attempts (user_id) VALUES (v_uid) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v_att FROM public.dob_attempts WHERE user_id = v_uid FOR UPDATE;

  IF v_att.locked_until IS NOT NULL AND v_att.locked_until > now() THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'LOCKED',
      'retry_after_seconds', ceil(extract(epoch FROM (v_att.locked_until - now())))::int
    );
  END IF;

  -- Fresh window after the previous one lapsed or a lock expired.
  IF v_att.window_started_at < now() - interval '15 minutes' OR v_att.locked_until IS NOT NULL THEN
    UPDATE public.dob_attempts
       SET failures = 0, window_started_at = now(), locked_until = NULL
     WHERE user_id = v_uid;
    v_att.failures := 0;
  END IF;

  IF p_dob IS NOT NULL AND p_dob = v_stored THEN
    DELETE FROM public.dob_attempts WHERE user_id = v_uid;
    INSERT INTO public.dob_session_confirmations (session_id, user_id)
    VALUES (v_sid, v_uid)
    ON CONFLICT (session_id) DO NOTHING;
    RETURN jsonb_build_object('success', true);
  END IF;

  UPDATE public.dob_attempts
     SET failures = failures + 1,
         locked_until = CASE WHEN failures + 1 >= v_max THEN now() + interval '15 minutes' ELSE NULL END
   WHERE user_id = v_uid
   RETURNING * INTO v_att;

  IF v_att.locked_until IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'LOCKED', 'retry_after_seconds', 900);
  END IF;
  RETURN jsonb_build_object('success', false, 'error', 'INCORRECT', 'attempts_left', v_max - v_att.failures);
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_date_of_birth(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_date_of_birth(date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. One-time grandfather cohort + the three approved DOB seeds
--    Runs once (marker table), resolves users by email at migration time, never
--    creates a user, never overwrites a different DOB, never marks a phone
--    verified. The emails are used ONLY here — never at runtime.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  rec record;
  v_user uuid;
  v_existing date;
BEGIN
  IF EXISTS (SELECT 1 FROM public.account_gate_migrations WHERE name = '123_cohort_and_seed') THEN
    RAISE NOTICE '123: cohort/seed already applied — skipping';
    RETURN;
  END IF;

  INSERT INTO public.account_phone_grandfathered (user_id, cohort)
  SELECT id, 'migration_123' FROM auth.users
  ON CONFLICT (user_id) DO NOTHING;

  FOR rec IN
    SELECT * FROM (VALUES
      ('dotrung1998@gmail.com',    DATE '1998-06-15'),
      ('doqanh0609@gmail.com',     DATE '2006-09-16'),
      ('banbetestadmin@gmail.com', DATE '1998-06-15')
    ) AS t(email, dob)
  LOOP
    SELECT id INTO v_user FROM auth.users WHERE lower(email) = lower(rec.email);
    IF v_user IS NULL THEN
      RAISE WARNING '123 seed: no auth user for %, skipped (nothing created)', rec.email;
      CONTINUE;
    END IF;
    SELECT date_of_birth INTO v_existing FROM public.user_private_dob WHERE user_id = v_user;
    IF v_existing IS NULL THEN
      INSERT INTO public.user_private_dob (user_id, date_of_birth, source) VALUES (v_user, rec.dob, 'seed_123');
      RAISE NOTICE '123 seed: stored DOB for % (user %)', rec.email, v_user;
    ELSIF v_existing = rec.dob THEN
      RAISE NOTICE '123 seed: % already has the same DOB — unchanged', rec.email;
    ELSE
      RAISE WARNING '123 seed CONFLICT: % already has a DIFFERENT DOB — NOT overwritten', rec.email;
    END IF;
  END LOOP;

  INSERT INTO public.account_gate_migrations (name) VALUES ('123_cohort_and_seed');
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Host promotional-message consent (separate from auth; default OFF)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.host_promo_consent (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  consented boolean NOT NULL DEFAULT false,
  consent_version text NOT NULL DEFAULT 'v1',
  consented_at timestamptz,
  withdrawn_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.host_promo_consent ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.host_promo_consent FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_host_promo_consent()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_on boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED');
  END IF;
  SELECT consented INTO v_on FROM public.host_promo_consent WHERE user_id = auth.uid();
  RETURN jsonb_build_object('success', true, 'consented', coalesce(v_on, false));
END;
$$;

CREATE OR REPLACE FUNCTION public.set_host_promo_consent(p_enabled boolean)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED');
  END IF;
  IF p_enabled IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_INPUT');
  END IF;
  INSERT INTO public.host_promo_consent (user_id, consented, consented_at, withdrawn_at, updated_at)
  VALUES (auth.uid(), p_enabled, CASE WHEN p_enabled THEN now() END, CASE WHEN p_enabled THEN NULL ELSE now() END, now())
  ON CONFLICT (user_id) DO UPDATE
    SET consented = EXCLUDED.consented,
        consented_at = CASE WHEN EXCLUDED.consented THEN now() ELSE public.host_promo_consent.consented_at END,
        withdrawn_at = CASE WHEN EXCLUDED.consented THEN NULL ELSE now() END,
        updated_at = now();
  RETURN jsonb_build_object('success', true, 'consented', p_enabled);
END;
$$;

REVOKE ALL ON FUNCTION public.get_host_promo_consent() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_host_promo_consent(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_host_promo_consent() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_host_promo_consent(boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. Host promo compose: ONE recipient at a time, consent rechecked at
--    compose time, no list endpoint, no phone until begin_promo_compose().
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.host_promo_compose_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  organizer_id text NOT NULL,
  event_id text NOT NULL,
  recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  result text NOT NULL DEFAULT 'presented'
    CHECK (result IN ('presented', 'sent', 'cancelled', 'failed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_id, recipient_id)
);
CREATE INDEX IF NOT EXISTS idx_promo_log_host_day ON public.host_promo_compose_log (host_id, created_at);
ALTER TABLE public.host_promo_compose_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.host_promo_compose_log FROM anon, authenticated;

-- Owner, user_id, or an ACCEPTED team member of the organizer.
CREATE OR REPLACE FUNCTION public.is_promo_host(p_org text, p_uid uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT p_uid IS NOT NULL AND p_org IS NOT NULL AND (
    EXISTS (SELECT 1 FROM public.organizers o
             WHERE o.id = p_org AND (o.owner_id = p_uid OR o.user_id = p_uid))
    OR EXISTS (SELECT 1 FROM public.organizer_members m
                WHERE m.organizer_id = p_org AND m.user_id = p_uid AND m.status = 'accepted')
  );
$$;

-- Permitted audience: consenting + verified phone + an existing relationship
-- with THIS organizer (booked one of its events, follows it, or saved one).
CREATE OR REPLACE FUNCTION public.promo_audience_ok(p_org text, p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT p_user IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.host_promo_consent c WHERE c.user_id = p_user AND c.consented)
    AND EXISTS (SELECT 1 FROM auth.users u
                 WHERE u.id = p_user AND coalesce(u.phone, '') <> '' AND u.phone_confirmed_at IS NOT NULL)
    AND (
      EXISTS (SELECT 1 FROM public.follows f WHERE f.user_id = p_user AND f.organizer_id = p_org)
      OR EXISTS (SELECT 1 FROM public.bookings b JOIN public.events e ON e.id = b.event_id
                  WHERE b.user_id = p_user AND e.organizer_id = p_org
                    AND b.status IN ('pending', 'confirmed', 'attended'))
      OR EXISTS (SELECT 1 FROM public.favorites v JOIN public.events e ON e.id = v.event_id
                  WHERE v.user_id = p_user AND e.organizer_id = p_org)
    );
$$;
REVOKE ALL ON FUNCTION public.is_promo_host(text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.promo_audience_ok(text, uuid) FROM PUBLIC, anon, authenticated;

-- Next eligible recipient for an event the caller hosts. Returns NO phone.
CREATE OR REPLACE FUNCTION public.next_promo_recipient(p_event_id text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org text;
  v_rec uuid;
  v_name text;
  v_locale text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  SELECT organizer_id INTO v_org FROM public.events WHERE id = p_event_id;
  IF v_org IS NULL OR NOT public.is_promo_host(v_org, v_uid) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF (SELECT count(*) FROM public.host_promo_compose_log
       WHERE host_id = v_uid AND created_at > now() - interval '24 hours') >= 30 THEN
    RETURN jsonb_build_object('success', false, 'error', 'RATE_LIMITED');
  END IF;

  SELECT u.id INTO v_rec
    FROM auth.users u
   WHERE u.id <> v_uid
     AND public.promo_audience_ok(v_org, u.id)
     AND NOT EXISTS (SELECT 1 FROM public.host_promo_compose_log l
                      WHERE l.event_id = p_event_id AND l.recipient_id = u.id)
   ORDER BY u.id
   LIMIT 1;

  IF v_rec IS NULL THEN
    RETURN jsonb_build_object('success', true, 'recipient', NULL);
  END IF;
  SELECT coalesce(nullif(p.display_name, ''), 'banbe'), p.locale::text INTO v_name, v_locale
    FROM public.profiles p WHERE p.id = v_rec;
  RETURN jsonb_build_object('success', true,
    'recipient', jsonb_build_object('id', v_rec, 'display_name', coalesce(v_name, 'banbe'), 'locale', coalesce(v_locale, 'vi')));
END;
$$;

-- Everything is RE-CHECKED here (host permission, consent, audience, cap,
-- not-already-prompted). Only on success does the phone leave the server —
-- for this one recipient.
CREATE OR REPLACE FUNCTION public.begin_promo_compose(p_event_id text, p_recipient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org text;
  v_event_name text;
  v_org_name text;
  v_phone text;
  v_name text;
  v_locale text;
  v_log uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  SELECT e.organizer_id, e.name INTO v_org, v_event_name FROM public.events e WHERE e.id = p_event_id;
  IF v_org IS NULL OR NOT public.is_promo_host(v_org, v_uid) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_recipient_id IS NULL OR p_recipient_id = v_uid OR NOT public.promo_audience_ok(v_org, p_recipient_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_ELIGIBLE');
  END IF;
  IF (SELECT count(*) FROM public.host_promo_compose_log
       WHERE host_id = v_uid AND created_at > now() - interval '24 hours') >= 30 THEN
    RETURN jsonb_build_object('success', false, 'error', 'RATE_LIMITED');
  END IF;

  INSERT INTO public.host_promo_compose_log (host_id, organizer_id, event_id, recipient_id)
  VALUES (v_uid, v_org, p_event_id, p_recipient_id)
  ON CONFLICT (event_id, recipient_id) DO NOTHING
  RETURNING id INTO v_log;
  IF v_log IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_PROMPTED');
  END IF;

  SELECT u.phone INTO v_phone FROM auth.users u WHERE u.id = p_recipient_id;
  SELECT coalesce(nullif(p.display_name, ''), 'banbe'), p.locale::text INTO v_name, v_locale
    FROM public.profiles p WHERE p.id = p_recipient_id;
  SELECT o.name INTO v_org_name FROM public.organizers o WHERE o.id = v_org;

  RETURN jsonb_build_object('success', true,
    'log_id', v_log,
    'phone', CASE WHEN left(v_phone, 1) = '+' THEN v_phone ELSE '+' || v_phone END,
    'display_name', coalesce(v_name, 'banbe'),
    'locale', coalesce(v_locale, 'vi'),
    'event_name', v_event_name,
    'organizer_id', v_org,
    'organizer_name', coalesce(v_org_name, ''));
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_promo_compose(p_log_id uuid, p_result text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF p_result NOT IN ('sent', 'cancelled', 'failed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_INPUT');
  END IF;
  UPDATE public.host_promo_compose_log SET result = p_result
   WHERE id = p_log_id AND host_id = auth.uid();
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.next_promo_recipient(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.begin_promo_compose(text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.finish_promo_compose(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.next_promo_recipient(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.begin_promo_compose(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finish_promo_compose(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 7. RLS gating: a RESTRICTIVE policy on user-private tables. Applies only to
--    the `authenticated` role (public catalogue reads by anon are untouched).
--    A signed-in session that has not finished enrollment / has not confirmed
--    its DOB this session reads and writes nothing from these tables.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'profiles', 'bookings', 'threads', 'messages', 'thread_preferences',
    'notifications', 'favorites', 'follows', 'refund_destinations',
    'refund_claims', 'refund_batches', 'refund_batch_items',
    'payment_documents', 'device_push_tokens', 'dispute_threads',
    'dispute_messages', 'survey_responses', 'check_ins', 'event_credits',
    'organizer_members', 'event_invites', 'app_feedback'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('DROP POLICY IF EXISTS "account_gate_required" ON public.%I', t);
      EXECUTE format(
        'CREATE POLICY "account_gate_required" ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING ((SELECT public.account_gate_ok())) WITH CHECK ((SELECT public.account_gate_ok()))',
        t);
    ELSE
      RAISE NOTICE '123 gate: table public.% not found, skipped', t;
    END IF;
  END LOOP;
END;
$$;
