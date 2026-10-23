-- Rollback for 194 (push delivery + switch defs table). NOT a migration; run by hand only if 194 must be undone, and
-- only BEFORE any later migration that inserted its own row into app_feature_flag_defs (those switches would lose
-- their key; roll those back first). Leaves pg_net installed. Device tokens themselves are kept (only the three new
-- columns go), so nobody has to re-register.
SELECT cron.unschedule('bb_push_drain_tick') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bb_push_drain_tick');
DROP TRIGGER IF EXISTS notifications_push_enqueue ON public.notifications;
DROP FUNCTION IF EXISTS public.push_drain_tick();
DROP FUNCTION IF EXISTS public.push_complete(jsonb);
DROP FUNCTION IF EXISTS public.push_claim(int);
DROP FUNCTION IF EXISTS public.push_enqueue();
DROP FUNCTION IF EXISTS public.push_kick();
DROP FUNCTION IF EXISTS public.push_quiet_until(text, timestamptz);
DROP TABLE IF EXISTS public.push_outbox;
DROP FUNCTION IF EXISTS public.set_my_promo_push(boolean);
DROP FUNCTION IF EXISTS public.get_my_notification_preferences();
DROP TABLE IF EXISTS public.notification_preferences;
DROP TABLE IF EXISTS public.notification_kind_policy;
DROP FUNCTION IF EXISTS public.unregister_push_token(text);
DROP FUNCTION IF EXISTS public.register_push_token(text, text, text, text, text);

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
ALTER TABLE public.device_push_tokens DROP COLUMN IF EXISTS environment, DROP COLUMN IF EXISTS app_id, DROP COLUMN IF EXISTS timezone;

-- Switches back to the 192 shape.
DELETE FROM public.app_feature_flags WHERE key = 'push_enabled';
ALTER TABLE public.app_feature_flags DROP CONSTRAINT IF EXISTS app_feature_flags_key_known;
ALTER TABLE public.app_feature_flags ADD CONSTRAINT app_feature_flags_key_known
  CHECK (key IN ('rewards', 'admin_event_wipe', 'rewards_v2'));
CREATE OR REPLACE FUNCTION public.admin_set_feature_flag(p_key text, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_enabled IS NULL OR p_key IS NULL OR p_key NOT IN ('rewards', 'admin_event_wipe', 'rewards_v2') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  INSERT INTO public.app_feature_flags (key, enabled, updated_by, updated_at)
  VALUES (p_key, p_enabled, v_admin, now())
  ON CONFLICT (key) DO UPDATE SET enabled = excluded.enabled, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  INSERT INTO public.app_feature_flags_audit (admin_id, key, enabled) VALUES (v_admin, p_key, p_enabled);
  RETURN jsonb_build_object('success', true, 'key', p_key, 'enabled', p_enabled);
END;
$$;
DROP FUNCTION IF EXISTS public.app_flag(text, boolean);
DROP TABLE IF EXISTS public.app_feature_flag_defs;
