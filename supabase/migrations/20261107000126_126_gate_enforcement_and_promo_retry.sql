-- Migration 126: close the account-gate bypasses + fix promo retry semantics.
--
-- WHY. 123 gated user-private TABLES with RLS, but authenticated SECURITY
-- DEFINER RPCs (hold_seats, confirm_payment, ...) run as their owner and skip
-- RLS entirely, so a signed-in session that had not finished enrollment /
-- not confirmed its date of birth could still call them. Patching ~130 function
-- bodies one by one is fragile, so the gate is enforced ONCE, in front of the
-- whole API:
--
--   1. public.gate_pre_request() is installed as PostgREST's `db_pre_request`
--      hook. It runs before EVERY API request (table or RPC). For an
--      `authenticated` caller whose session has not passed the gate it raises
--      HTTP 403 before any function or table is touched. Exempt: the four gate
--      RPCs themselves. `anon` (public browsing) and `service_role` are
--      untouched.
--   2. A RESTRICTIVE policy on storage.objects does the same for the Storage
--      API (which talks to Postgres directly, not through PostgREST).
--   3. The 123 table policies stay as defense in depth.
--
-- Kill switch (if the hook ever misbehaves, from the SQL editor):
--   UPDATE public.account_gate_config SET enabled = false WHERE key = 'api_enforcement';
--
-- Also here: a cancelled / failed promo compose no longer burns the recipient.

-- ---------------------------------------------------------------------------
-- 1. Central API gate
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.account_gate_config (
  key text PRIMARY KEY,
  enabled boolean NOT NULL
);
INSERT INTO public.account_gate_config (key, enabled) VALUES ('api_enforcement', true)
ON CONFLICT (key) DO NOTHING;
ALTER TABLE public.account_gate_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_gate_config FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.gate_pre_request()
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_claims jsonb;
  v_role text;
  v_path text := coalesce(current_setting('request.path', true), '');
  v_name text;
BEGIN
  BEGIN
    v_claims := coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
  EXCEPTION WHEN OTHERS THEN
    v_claims := '{}'::jsonb;
  END;
  v_role := coalesce(v_claims ->> 'role', '');

  -- Only signed-in users are gated. Anonymous browsing and server-side
  -- (service_role) calls are never affected.
  IF v_role <> 'authenticated' THEN
    RETURN;
  END IF;

  IF NOT coalesce((SELECT enabled FROM public.account_gate_config WHERE key = 'api_enforcement'), true) THEN
    RETURN;
  END IF;

  -- The only API calls a gated session needs: read its own gate status and
  -- submit the DOB steps.
  IF v_path LIKE '/rpc/%' THEN
    v_name := substring(v_path FROM 6);
    IF v_name IN ('account_gate_status', 'account_gate_ok', 'set_date_of_birth', 'confirm_date_of_birth') THEN
      RETURN;
    END IF;
  END IF;

  IF NOT public.account_gate_ok() THEN
    RAISE EXCEPTION 'ACCOUNT_GATE_REQUIRED'
      USING ERRCODE = 'PT403',
            DETAIL = 'Finish account enrollment / confirm your date of birth to continue.';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.gate_pre_request() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gate_pre_request() TO anon, authenticated, service_role, authenticator;

ALTER ROLE authenticator SET pgrst.db_pre_request = 'public.gate_pre_request';
NOTIFY pgrst, 'reload config';

-- ---------------------------------------------------------------------------
-- 2. Storage API
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "account_gate_required" ON storage.objects;
CREATE POLICY "account_gate_required" ON storage.objects
  AS RESTRICTIVE FOR ALL TO authenticated
  USING ((SELECT public.account_gate_ok()))
  WITH CHECK ((SELECT public.account_gate_ok()));

-- ---------------------------------------------------------------------------
-- 3. Promo retry semantics
--    * `sent`                     -> that recipient is done for this event.
--    * `presented` (in progress)  -> blocked for 15 minutes, then it is treated
--      as failed (app killed, composer never reported back).
--    * `cancelled` / `failed`     -> NOT consumed: the host may retry, at most 3
--      attempts per recipient per event, and such recipients are offered after
--      everyone who hasn't been tried yet.
--    * Only a `presented` row can be finished, so a recorded `sent` can never
--      be flipped back to re-enable another send.
-- ---------------------------------------------------------------------------
DO $$
DECLARE c text;
BEGIN
  FOR c IN
    SELECT con.conname
      FROM pg_constraint con
      JOIN pg_class rel ON rel.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = rel.relnamespace
     WHERE n.nspname = 'public' AND rel.relname = 'host_promo_compose_log' AND con.contype = 'u'
  LOOP
    EXECUTE format('ALTER TABLE public.host_promo_compose_log DROP CONSTRAINT %I', c);
  END LOOP;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_promo_log_active
  ON public.host_promo_compose_log (event_id, recipient_id)
  WHERE result IN ('presented', 'sent');

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
       WHERE host_id = v_uid AND result IN ('presented', 'sent')
         AND created_at > now() - interval '24 hours') >= 30 THEN
    RETURN jsonb_build_object('success', false, 'error', 'RATE_LIMITED');
  END IF;

  SELECT u.id INTO v_rec
    FROM auth.users u
    LEFT JOIN LATERAL (
      SELECT max(l.created_at) AS last_try, count(*) AS tries,
             bool_or(l.result = 'sent') AS was_sent,
             bool_or(l.result = 'presented' AND l.created_at > now() - interval '15 minutes') AS in_progress
        FROM public.host_promo_compose_log l
       WHERE l.event_id = p_event_id AND l.recipient_id = u.id
    ) h ON true
   WHERE u.id <> v_uid
     AND public.promo_audience_ok(v_org, u.id)
     AND coalesce(h.was_sent, false) = false
     AND coalesce(h.in_progress, false) = false
     AND coalesce(h.tries, 0) < 3
   ORDER BY h.last_try ASC NULLS FIRST, u.id
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
  -- Consent, audience and phone are rechecked HERE, at compose time.
  IF p_recipient_id IS NULL OR p_recipient_id = v_uid OR NOT public.promo_audience_ok(v_org, p_recipient_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_ELIGIBLE');
  END IF;
  IF (SELECT count(*) FROM public.host_promo_compose_log
       WHERE host_id = v_uid AND result IN ('presented', 'sent')
         AND created_at > now() - interval '24 hours') >= 30 THEN
    RETURN jsonb_build_object('success', false, 'error', 'RATE_LIMITED');
  END IF;

  -- An abandoned attempt (composer never reported back) stops blocking after 15 min.
  UPDATE public.host_promo_compose_log
     SET result = 'failed'
   WHERE event_id = p_event_id AND recipient_id = p_recipient_id
     AND result = 'presented' AND created_at < now() - interval '15 minutes';

  IF EXISTS (SELECT 1 FROM public.host_promo_compose_log
              WHERE event_id = p_event_id AND recipient_id = p_recipient_id AND result = 'sent') THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_PROMPTED');
  END IF;
  IF (SELECT count(*) FROM public.host_promo_compose_log
       WHERE event_id = p_event_id AND recipient_id = p_recipient_id) >= 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_ELIGIBLE');
  END IF;

  INSERT INTO public.host_promo_compose_log (host_id, organizer_id, event_id, recipient_id)
  VALUES (v_uid, v_org, p_event_id, p_recipient_id)
  ON CONFLICT (event_id, recipient_id) WHERE result IN ('presented', 'sent') DO NOTHING
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
  -- Only an in-progress attempt can be finished; a recorded result is final.
  UPDATE public.host_promo_compose_log SET result = p_result
   WHERE id = p_log_id AND host_id = auth.uid() AND result = 'presented';
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.next_promo_recipient(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.begin_promo_compose(text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.finish_promo_compose(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.next_promo_recipient(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.begin_promo_compose(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finish_promo_compose(uuid, text) TO authenticated;
