-- 194 — Real APNs push delivery, pre-built so it works the moment a paid Apple Developer
-- account + APNs Auth Key exist (docs/push-setup.md). Until then every piece below is inert:
-- no vault secrets → push_kick() does nothing; no APNS_* env on Vercel → the drain skips;
-- pending rows expire after 15 minutes, so turning push on later never floods stale alerts.
--
--   notifications INSERT (already localized by 142's BEFORE trigger)
--     → push_enqueue() row trigger: one push_outbox row, only if the recipient has a device
--       token and has not muted that kind (062 was client-only; this enforces it server-side)
--     → push_kick(): pg_net POST to /api/cron?job=push-drain (URL + bearer from Supabase Vault)
--     → Vercel drain: push_claim() → APNs (token-based .p8 JWT) → push_complete()
--   pg_cron every minute: push_drain_tick() retries/expires/cleans up.
--
-- Also: device_push_tokens learns its APNs environment (sandbox vs production) and app id,
-- and unregister_push_token() lets sign-out stop pushes to the previous account.
--
-- Rollback: supabase/rollbacks/20261229000194_194_revert_push_delivery.sql (kept OUT of migrations/).

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ---------------------------------------------------------------- device tokens
ALTER TABLE public.device_push_tokens
  ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production',
  ADD COLUMN IF NOT EXISTS app_id text;
ALTER TABLE public.device_push_tokens DROP CONSTRAINT IF EXISTS device_push_tokens_environment_check;
ALTER TABLE public.device_push_tokens
  ADD CONSTRAINT device_push_tokens_environment_check CHECK (environment IN ('sandbox', 'production'));

-- Old builds call register_push_token(p_token, p_platform); the new defaults keep that call valid.
DROP FUNCTION IF EXISTS public.register_push_token(text, text);
CREATE OR REPLACE FUNCTION public.register_push_token(
  p_token text,
  p_platform text DEFAULT 'ios',
  p_environment text DEFAULT 'production',
  p_app_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_token text := lower(trim(coalesce(p_token, '')));
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

  INSERT INTO device_push_tokens (token, user_id, platform, environment, app_id, updated_at)
  VALUES (v_token, auth.uid(), coalesce(p_platform, 'ios'), coalesce(p_environment, 'production'),
          nullif(trim(coalesce(p_app_id, '')), ''), now())
  ON CONFLICT (token) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    platform = EXCLUDED.platform,
    environment = EXCLUDED.environment,
    app_id = EXCLUDED.app_id,
    updated_at = now();

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.register_push_token(text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_token(text, text, text, text) TO authenticated;

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

-- ---------------------------------------------------------------- outbox
CREATE TABLE IF NOT EXISTS public.push_outbox (
  id bigserial PRIMARY KEY,
  notification_id uuid NOT NULL UNIQUE REFERENCES public.notifications(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sending', 'sent', 'failed', 'expired', 'skipped')),
  attempts int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  claimed_at timestamptz,
  finished_at timestamptz,
  last_error text
);
CREATE INDEX IF NOT EXISTS push_outbox_open_idx ON public.push_outbox (id) WHERE status IN ('pending', 'sending');
CREATE INDEX IF NOT EXISTS push_outbox_created_idx ON public.push_outbox (created_at);
ALTER TABLE public.push_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_outbox FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.push_outbox TO service_role;
REVOKE ALL ON SEQUENCE public.push_outbox_id_seq FROM PUBLIC, anon, authenticated;

-- Wakes the Vercel drain. Inert until both Vault secrets exist (docs/push-setup.md):
--   push_drain_url    = https://www.banbe.app/api/cron?job=push-drain
--   push_drain_secret = the same value as CRON_SECRET on Vercel
-- pg_net queues the request and sends it only after the calling transaction commits; one queued
-- request is enough (the drain empties the whole outbox), so a bulk insert kicks once.
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
BEGIN
  IF EXISTS (SELECT 1 FROM device_push_tokens t WHERE t.user_id = NEW.recipient_id)
     AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = NEW.recipient_id
                       AND NEW.kind = ANY (coalesce(p.muted_notification_kinds, '{}'::text[]))) THEN
    INSERT INTO push_outbox (notification_id, recipient_id)
    VALUES (NEW.id, NEW.recipient_id)
    ON CONFLICT (notification_id) DO NOTHING;
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

-- Drain side (service_role only). Claims up to p_limit rows still worth sending:
-- younger than 15 minutes, fewer than 3 attempts, unread, kind not muted since. Each item carries
-- the already-localized title/body, the routing data, the unread badge and the recipient's tokens.
CREATE OR REPLACE FUNCTION public.push_claim(p_limit int DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_items jsonb;
BEGIN
  -- Not worth sending any more: stale, read already, or muted after it was queued.
  UPDATE push_outbox o SET status = 'expired', finished_at = now(), last_error = coalesce(o.last_error, 'stale')
   WHERE o.status IN ('pending', 'sending') AND (o.created_at < now() - interval '15 minutes' OR o.attempts >= 3);
  UPDATE push_outbox o SET status = 'skipped', finished_at = now(), last_error = 'read_or_muted'
    FROM notifications n, profiles p
   WHERE o.status = 'pending' AND n.id = o.notification_id AND p.id = o.recipient_id
     AND (n.read_at IS NOT NULL OR n.kind = ANY (coalesce(p.muted_notification_kinds, '{}'::text[])));

  WITH c AS (
    SELECT o.id FROM push_outbox o
     WHERE o.status = 'pending'
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

-- p_results: [{id, status: 'sent'|'failed', error?, gone_tokens?: [..], moved_tokens?: [{token, environment}]}]
-- 'failed' rows go back to pending for the next attempt (push_claim expires them after 3).
CREATE OR REPLACE FUNCTION public.push_complete(p_results jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  r jsonb;
  v_done int := 0;
BEGIN
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) LOOP
    UPDATE push_outbox SET
      status = CASE WHEN r->>'status' = 'sent' THEN 'sent' ELSE 'pending' END,
      finished_at = CASE WHEN r->>'status' = 'sent' THEN now() ELSE NULL END,
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

-- Every minute: retry what is still pending (e.g. Vercel was down), keep the outbox small.
CREATE OR REPLACE FUNCTION public.push_drain_tick()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  UPDATE push_outbox SET status = 'expired', finished_at = now(), last_error = coalesce(last_error, 'stale')
   WHERE status IN ('pending', 'sending') AND created_at < now() - interval '15 minutes';
  DELETE FROM push_outbox WHERE created_at < now() - interval '7 days';
  IF EXISTS (SELECT 1 FROM push_outbox WHERE status = 'pending'
                OR (status = 'sending' AND claimed_at < now() - interval '2 minutes')) THEN
    PERFORM push_kick();
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.push_drain_tick() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('bb_push_drain_tick', '* * * * *', $cmd$ SELECT public.push_drain_tick(); $cmd$);
