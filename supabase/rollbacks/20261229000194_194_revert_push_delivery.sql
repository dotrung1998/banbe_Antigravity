-- Rollback for 194 (push delivery). NOT a migration; run by hand only if 194 must be undone.
-- Leaves pg_net installed (other projects/extensions may use it) and keeps the two new
-- device_push_tokens columns' data out of the way by dropping them.
SELECT cron.unschedule('bb_push_drain_tick') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bb_push_drain_tick');
DROP TRIGGER IF EXISTS notifications_push_enqueue ON public.notifications;
DROP FUNCTION IF EXISTS public.push_drain_tick();
DROP FUNCTION IF EXISTS public.push_complete(jsonb);
DROP FUNCTION IF EXISTS public.push_claim(int);
DROP FUNCTION IF EXISTS public.push_enqueue();
DROP FUNCTION IF EXISTS public.push_kick();
DROP TABLE IF EXISTS public.push_outbox;
DROP FUNCTION IF EXISTS public.unregister_push_token(text);
DROP FUNCTION IF EXISTS public.register_push_token(text, text, text, text);

CREATE OR REPLACE FUNCTION public.register_push_token(p_token text, p_platform text DEFAULT 'ios')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'VALID_TOKEN_REQUIRED');
  END IF;
  INSERT INTO device_push_tokens (token, user_id, platform, updated_at)
  VALUES (trim(p_token), auth.uid(), COALESCE(p_platform, 'ios'), now())
  ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, updated_at = now();
  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.register_push_token(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.register_push_token(text, text) TO authenticated;

ALTER TABLE public.device_push_tokens DROP CONSTRAINT IF EXISTS device_push_tokens_environment_check;
ALTER TABLE public.device_push_tokens DROP COLUMN IF EXISTS environment, DROP COLUMN IF EXISTS app_id;
