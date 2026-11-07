-- Step 3 of .claude/notes/07-notifications.md: storage for a real push
-- token, wired up ahead of actually being able to send anything with it —
-- see that note and this session's final report for the exact APNs
-- credential still needed before any send can happen.
--
-- One row per physical device, not per user: `token` is the primary key
-- (an APNs/FCM token identifies a device+app install, not an account) so a
-- device that signs out and a different account signs into on the same
-- hardware correctly reassigns to the new user_id via upsert, rather than
-- silently keeping the old owner subscribed to that device's pushes.
CREATE TABLE IF NOT EXISTS public.device_push_tokens (
  token text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  platform text NOT NULL DEFAULT 'ios' CHECK (platform IN ('ios', 'android', 'web')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS device_push_tokens_user_idx ON public.device_push_tokens (user_id);

ALTER TABLE public.device_push_tokens ENABLE ROW LEVEL SECURITY;

-- A signed-in device registers/updates only its own token; the future
-- send-side job reads across all users with the service role, which
-- bypasses RLS entirely, so no broader SELECT policy is needed here.
DROP POLICY IF EXISTS "device_push_tokens_own_upsert" ON public.device_push_tokens;
CREATE POLICY "device_push_tokens_own_upsert" ON public.device_push_tokens
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "device_push_tokens_own_update" ON public.device_push_tokens;
CREATE POLICY "device_push_tokens_own_update" ON public.device_push_tokens
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "device_push_tokens_own_select" ON public.device_push_tokens;
CREATE POLICY "device_push_tokens_own_select" ON public.device_push_tokens
  FOR SELECT TO authenticated USING (user_id = auth.uid());

DROP POLICY IF EXISTS "device_push_tokens_own_delete" ON public.device_push_tokens;
CREATE POLICY "device_push_tokens_own_delete" ON public.device_push_tokens
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- Idempotent registration: the same device re-registering (app relaunch,
-- token refresh) updates in place rather than erroring on the existing
-- primary key.
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
  ON CONFLICT (token) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    platform = EXCLUDED.platform,
    updated_at = now();

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.register_push_token(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.register_push_token(text, text) TO authenticated;
