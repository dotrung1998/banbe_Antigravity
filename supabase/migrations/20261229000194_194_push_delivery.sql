-- 194 — APNs push delivery, pre-built so it works the moment a paid Apple Developer account + APNs Auth Key exist
-- (docs/apple-setup-checklist.md). Fully inert until then:
--   * switch `push_enabled` (seeded OFF): while off, nothing is queued and the drain claims nothing;
--   * no Vault secrets (push_drain_url / push_drain_secret) → push_kick() calls nothing;
--   * switch on but no APNS_* credentials on the server → the drain runs DRY: it logs counts only and marks rows
--     `skipped_no_credentials`.
--
--   notifications INSERT (title/body already localized by 142's BEFORE trigger)
--     → push_enqueue() row trigger: one push_outbox row when the switch is on, the recipient has a device token, has
--       not muted the kind (062 was client-only; enforced here too) and, for a PROMOTIONAL kind, opted in to
--       promotional pushes (notification_preferences.promo_push, default false)
--     → quiet hours 22:00–07:00 in the device's own zone: `not_before` = the next 07:00 there
--     → push_kick(): pg_net POST to /api/cron?job=push-drain (URL + bearer from Supabase Vault)
--     → Vercel drain: push_claim() → APNs (token-based .p8 JWT) → push_complete()
--   pg_cron every minute: push_drain_tick() wakes the drain for due rows (incl. 07:00 releases), expires, cleans up.
--
-- Also:
--   * app_feature_flag_defs: the list of known switches becomes a table (FK from app_feature_flags), so a new switch is
--     one INSERT instead of redefining the CHECK + admin_set_feature_flag every time (187 → 189 → 192 did that).
--   * device_push_tokens learns its APNs environment, app id and time zone; unregister_push_token() for sign-out.
--
-- Rollback: supabase/rollbacks/20261229000194_194_revert_push_delivery.sql (kept OUT of migrations/).

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ---------------------------------------------------------------- switches: table of known keys
CREATE TABLE IF NOT EXISTS public.app_feature_flag_defs (
  key text PRIMARY KEY CONSTRAINT app_feature_flag_defs_key_shape CHECK (key ~ '^[a-z][a-z0-9_]{1,40}$'),
  description text NOT NULL DEFAULT '',
  added_in text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_feature_flag_defs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_feature_flag_defs FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.app_feature_flag_defs TO service_role;

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('rewards', 'Rewards & badges everywhere (missing row = on)', '187'),
  ('admin_event_wipe', 'TESTING PHASE: admin hard wipe of any event (iOS)', '189'),
  ('rewards_v2', 'Rewards v2: week streak, tiers, goal', '192'),
  ('push_enabled', 'Real push notifications (APNs). Off = nothing queued or sent', '194')
ON CONFLICT (key) DO NOTHING;
-- Any key already stored keeps working, whatever migration added it.
INSERT INTO public.app_feature_flag_defs (key, added_in)
SELECT f.key, 'pre-194' FROM public.app_feature_flags f ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.app_feature_flags DROP CONSTRAINT IF EXISTS app_feature_flags_key_known;
ALTER TABLE public.app_feature_flags ADD CONSTRAINT app_feature_flags_key_known
  FOREIGN KEY (key) REFERENCES public.app_feature_flag_defs (key);

INSERT INTO public.app_feature_flags (key, enabled) VALUES ('push_enabled', false) ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_set_feature_flag(p_key text, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_enabled IS NULL OR p_key IS NULL OR NOT EXISTS (SELECT 1 FROM public.app_feature_flag_defs d WHERE d.key = p_key) THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  INSERT INTO public.app_feature_flags (key, enabled, updated_by, updated_at)
  VALUES (p_key, p_enabled, v_admin, now())
  ON CONFLICT (key) DO UPDATE SET enabled = excluded.enabled, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  INSERT INTO public.app_feature_flags_audit (admin_id, key, enabled) VALUES (v_admin, p_key, p_enabled);
  RETURN jsonb_build_object('success', true, 'key', p_key, 'enabled', p_enabled);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_set_feature_flag(text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_feature_flag(text, boolean) TO authenticated;

-- Server-side switch read for every feature from here on (same rule as the clients: missing row = p_default).
CREATE OR REPLACE FUNCTION public.app_flag(p_key text, p_default boolean)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE((SELECT f.enabled FROM public.app_feature_flags f WHERE f.key = p_key), p_default)
$$;
REVOKE ALL ON FUNCTION public.app_flag(text, boolean) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- device tokens
ALTER TABLE public.device_push_tokens
  ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production',
  ADD COLUMN IF NOT EXISTS app_id text,
  ADD COLUMN IF NOT EXISTS timezone text;
ALTER TABLE public.device_push_tokens DROP CONSTRAINT IF EXISTS device_push_tokens_environment_check;
ALTER TABLE public.device_push_tokens
  ADD CONSTRAINT device_push_tokens_environment_check CHECK (environment IN ('sandbox', 'production'));

-- Old builds call register_push_token(p_token, p_platform); the new defaults keep that call valid.
DROP FUNCTION IF EXISTS public.register_push_token(text, text);
CREATE OR REPLACE FUNCTION public.register_push_token(
  p_token text,
  p_platform text DEFAULT 'ios',
  p_environment text DEFAULT 'production',
  p_app_id text DEFAULT NULL,
  p_timezone text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_token text := lower(trim(coalesce(p_token, '')));
  v_tz text := nullif(trim(coalesce(p_timezone, '')), '');
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF v_token = '' OR length(v_token) > 512 THEN
    RETURN jsonb_build_object('success', false, 'error', 'VALID_TOKEN_REQUIRED');
  END IF;
  IF coalesce(p_platform, 'ios') NOT IN ('ios', 'android', 'web')
     OR coalesce(p_environment, 'production') NOT IN ('sandbox', 'production')
     OR length(coalesce(p_app_id, '')) > 200 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  IF v_tz IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = v_tz) THEN
    v_tz := NULL;   -- an unknown zone falls back to the default instead of failing registration
  END IF;

  INSERT INTO device_push_tokens (token, user_id, platform, environment, app_id, timezone, updated_at)
  VALUES (v_token, auth.uid(), coalesce(p_platform, 'ios'), coalesce(p_environment, 'production'),
          nullif(trim(coalesce(p_app_id, '')), ''), v_tz, now())
  ON CONFLICT (token) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    platform = EXCLUDED.platform,
    environment = EXCLUDED.environment,
    app_id = EXCLUDED.app_id,
    timezone = coalesce(EXCLUDED.timezone, device_push_tokens.timezone),
    updated_at = now();

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.register_push_token(text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_token(text, text, text, text, text) TO authenticated;

-- Sign-out: this device stops receiving the signed-out account's pushes.
CREATE OR REPLACE FUNCTION public.unregister_push_token(p_token text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_count int;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  DELETE FROM device_push_tokens WHERE token = lower(trim(coalesce(p_token, ''))) AND user_id = auth.uid();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'removed', v_count);
END;
$$;
REVOKE ALL ON FUNCTION public.unregister_push_token(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unregister_push_token(text) TO authenticated;

-- ---------------------------------------------------------------- what is promotional, who opted in
-- Promotional kinds are pushed only to people who opted in. Everything else is a service message (opt-out per kind).
CREATE TABLE IF NOT EXISTS public.notification_kind_policy (
  kind text PRIMARY KEY,
  promotional boolean NOT NULL DEFAULT false,
  note text NOT NULL DEFAULT ''
);
ALTER TABLE public.notification_kind_policy ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_kind_policy FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.notification_kind_policy TO service_role;
INSERT INTO public.notification_kind_policy (kind, promotional, note) VALUES
  ('weekly_digest', true, 'L5 "This weekend" digest (opt-in)')
ON CONFLICT (kind) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  promo_push boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_preferences FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_preferences TO service_role;

CREATE OR REPLACE FUNCTION public.get_my_notification_preferences()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  RETURN jsonb_build_object('success', true,
    'promo_push', coalesce((SELECT p.promo_push FROM notification_preferences p WHERE p.user_id = auth.uid()), false));
END;
$$;
REVOKE ALL ON FUNCTION public.get_my_notification_preferences() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_notification_preferences() TO authenticated;

CREATE OR REPLACE FUNCTION public.set_my_promo_push(p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF p_enabled IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE'); END IF;
  INSERT INTO notification_preferences (user_id, promo_push, updated_at) VALUES (auth.uid(), p_enabled, now())
  ON CONFLICT (user_id) DO UPDATE SET promo_push = EXCLUDED.promo_push, updated_at = now();
  RETURN jsonb_build_object('success', true, 'promo_push', p_enabled);
END;
$$;
REVOKE ALL ON FUNCTION public.set_my_promo_push(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_promo_push(boolean) TO authenticated;

-- ---------------------------------------------------------------- quiet hours
-- 22:00–07:00 in p_tz: returns the next 07:00 there, else p_now itself.
CREATE OR REPLACE FUNCTION public.push_quiet_until(p_tz text, p_now timestamptz DEFAULT now())
RETURNS timestamptz LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE
  v_tz text := coalesce(nullif(p_tz, ''), 'Asia/Ho_Chi_Minh');
  v_local timestamp;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = v_tz) THEN v_tz := 'Asia/Ho_Chi_Minh'; END IF;
  v_local := p_now AT TIME ZONE v_tz;
  IF extract(hour FROM v_local) >= 22 THEN
    RETURN ((v_local::date + 1) + time '07:00') AT TIME ZONE v_tz;
  ELSIF extract(hour FROM v_local) < 7 THEN
    RETURN (v_local::date + time '07:00') AT TIME ZONE v_tz;
  END IF;
  RETURN p_now;
END;
$$;
REVOKE ALL ON FUNCTION public.push_quiet_until(text, timestamptz) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- outbox
CREATE TABLE IF NOT EXISTS public.push_outbox (
  id bigserial PRIMARY KEY,
  notification_id uuid NOT NULL UNIQUE REFERENCES public.notifications(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sending', 'sent', 'failed', 'expired', 'skipped', 'skipped_no_credentials')),
  attempts int NOT NULL DEFAULT 0,
  not_before timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  claimed_at timestamptz,
  finished_at timestamptz,
  last_error text
);
CREATE INDEX IF NOT EXISTS push_outbox_open_idx ON public.push_outbox (not_before, id) WHERE status IN ('pending', 'sending');
CREATE INDEX IF NOT EXISTS push_outbox_created_idx ON public.push_outbox (created_at);
ALTER TABLE public.push_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_outbox FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.push_outbox TO service_role;
REVOKE ALL ON SEQUENCE public.push_outbox_id_seq FROM PUBLIC, anon, authenticated;

-- Wakes the Vercel drain. Inert until both Vault secrets exist (docs/apple-setup-checklist.md):
--   push_drain_url    = https://www.banbe.app/api/cron?job=push-drain
--   push_drain_secret = the same value as CRON_SECRET on Vercel
-- pg_net queues the request and sends it only after the calling transaction commits; one queued request is enough
-- (the drain empties the whole outbox), so a bulk insert kicks once.
CREATE OR REPLACE FUNCTION public.push_kick()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_url text;
  v_secret text;
BEGIN
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'push_drain_url' LIMIT 1;
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'push_drain_secret' LIMIT 1;
  IF coalesce(v_url, '') = '' OR coalesce(v_secret, '') = '' THEN
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM net.http_request_queue WHERE url = v_url) THEN
    RETURN;
  END IF;
  PERFORM net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    timeout_milliseconds := 10000
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'push_kick failed: %', SQLERRM;
END;
$$;
REVOKE ALL ON FUNCTION public.push_kick() FROM PUBLIC, anon, authenticated;

-- Never blocks or fails the notification insert itself.
CREATE OR REPLACE FUNCTION public.push_enqueue()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_tz text;
  v_not_before timestamptz;
BEGIN
  IF NOT public.app_flag('push_enabled', false) THEN
    RETURN NULL;
  END IF;
  -- The most recently used device decides the local clock for quiet hours.
  SELECT t.timezone INTO v_tz FROM device_push_tokens t
   WHERE t.user_id = NEW.recipient_id ORDER BY t.updated_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  IF EXISTS (SELECT 1 FROM profiles p WHERE p.id = NEW.recipient_id
               AND NEW.kind = ANY (coalesce(p.muted_notification_kinds, '{}'::text[]))) THEN
    RETURN NULL;
  END IF;
  IF EXISTS (SELECT 1 FROM notification_kind_policy k WHERE k.kind = NEW.kind AND k.promotional)
     AND NOT coalesce((SELECT np.promo_push FROM notification_preferences np WHERE np.user_id = NEW.recipient_id), false) THEN
    RETURN NULL;
  END IF;
  v_not_before := public.push_quiet_until(v_tz, now());
  INSERT INTO push_outbox (notification_id, recipient_id, not_before)
  VALUES (NEW.id, NEW.recipient_id, v_not_before)
  ON CONFLICT (notification_id) DO NOTHING;
  IF v_not_before <= now() THEN
    PERFORM push_kick();
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'push_enqueue failed: %', SQLERRM;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.push_enqueue() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS notifications_push_enqueue ON public.notifications;
CREATE TRIGGER notifications_push_enqueue
  AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.push_enqueue();

-- Drain side (service_role only). While `push_enabled` is off it claims nothing. Claims up to p_limit due rows
-- (not_before passed) still worth sending: due less than 15 minutes ago, fewer than 3 attempts, unread, kind not muted
-- since. Each item carries the already-localized title/body, the routing data, the unread badge and the tokens.
CREATE OR REPLACE FUNCTION public.push_claim(p_limit int DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_items jsonb;
BEGIN
  IF NOT public.app_flag('push_enabled', false) THEN
    RETURN '[]'::jsonb;
  END IF;
  UPDATE push_outbox o SET status = 'expired', finished_at = now(), last_error = coalesce(o.last_error, 'stale')
   WHERE o.status IN ('pending', 'sending') AND (o.not_before < now() - interval '15 minutes' OR o.attempts >= 3);
  UPDATE push_outbox o SET status = 'skipped', finished_at = now(), last_error = 'read_or_muted'
    FROM notifications n, profiles p
   WHERE o.status = 'pending' AND n.id = o.notification_id AND p.id = o.recipient_id
     AND (n.read_at IS NOT NULL OR n.kind = ANY (coalesce(p.muted_notification_kinds, '{}'::text[])));

  WITH c AS (
    SELECT o.id FROM push_outbox o
     WHERE (o.status = 'pending' AND o.not_before <= now())
        OR (o.status = 'sending' AND o.claimed_at < now() - interval '2 minutes')
     ORDER BY o.id
     LIMIT greatest(1, least(coalesce(p_limit, 100), 500))
     FOR UPDATE SKIP LOCKED
  ), u AS (
    UPDATE push_outbox o SET status = 'sending', claimed_at = now(), attempts = o.attempts + 1
      FROM c WHERE o.id = c.id
    RETURNING o.id, o.notification_id, o.recipient_id
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', u.id,
           'notification_id', n.id,
           'kind', n.kind,
           'title', n.title,
           'body', n.body,
           'data', n.data,
           'badge', (SELECT count(*) FROM notifications x WHERE x.recipient_id = u.recipient_id AND x.read_at IS NULL),
           'tokens', coalesce((SELECT jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment, 'app_id', t.app_id))
                                 FROM device_push_tokens t WHERE t.user_id = u.recipient_id AND t.platform = 'ios'), '[]'::jsonb)
         ) ORDER BY u.id), '[]'::jsonb)
    INTO v_items
    FROM u JOIN notifications n ON n.id = u.notification_id;

  RETURN v_items;
END;
$$;
REVOKE ALL ON FUNCTION public.push_claim(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.push_claim(int) TO service_role;

-- p_results: [{id, status: 'sent'|'failed'|'skipped_no_credentials', error?, gone_tokens?: [..],
--              moved_tokens?: [{token, environment}]}]
-- 'failed' rows go back to pending one minute later (attempt × 1 min backoff; push_claim expires them after 3).
CREATE OR REPLACE FUNCTION public.push_complete(p_results jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  r jsonb;
  v_done int := 0;
  v_status text;
BEGIN
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) LOOP
    v_status := CASE r->>'status' WHEN 'sent' THEN 'sent' WHEN 'skipped_no_credentials' THEN 'skipped_no_credentials' ELSE 'pending' END;
    UPDATE push_outbox SET
      status = v_status,
      finished_at = CASE WHEN v_status = 'pending' THEN NULL ELSE now() END,
      not_before = CASE WHEN v_status = 'pending' THEN now() + make_interval(mins => greatest(attempts, 1)) ELSE not_before END,
      last_error = left(r->>'error', 300)
     WHERE id = (r->>'id')::bigint AND status = 'sending';
    v_done := v_done + 1;

    DELETE FROM device_push_tokens
     WHERE token IN (SELECT jsonb_array_elements_text(coalesce(r->'gone_tokens', '[]'::jsonb)));

    UPDATE device_push_tokens t SET environment = m->>'environment', updated_at = now()
      FROM jsonb_array_elements(coalesce(r->'moved_tokens', '[]'::jsonb)) m
     WHERE t.token = m->>'token' AND m->>'environment' IN ('sandbox', 'production');
  END LOOP;
  RETURN jsonb_build_object('success', true, 'completed', v_done);
END;
$$;
REVOKE ALL ON FUNCTION public.push_complete(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.push_complete(jsonb) TO service_role;

-- Every minute: wake the drain for due rows (retries, and quiet-hour rows reaching 07:00), keep the outbox small.
CREATE OR REPLACE FUNCTION public.push_drain_tick()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  UPDATE push_outbox SET status = 'expired', finished_at = now(), last_error = coalesce(last_error, 'stale')
   WHERE status IN ('pending', 'sending') AND not_before < now() - interval '15 minutes';
  DELETE FROM push_outbox WHERE created_at < now() - interval '7 days';
  IF public.app_flag('push_enabled', false)
     AND EXISTS (SELECT 1 FROM push_outbox WHERE (status = 'pending' AND not_before <= now())
                    OR (status = 'sending' AND claimed_at < now() - interval '2 minutes')) THEN
    PERFORM push_kick();
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.push_drain_tick() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('bb_push_drain_tick', '* * * * *', $cmd$ SELECT public.push_drain_tick(); $cmd$);
