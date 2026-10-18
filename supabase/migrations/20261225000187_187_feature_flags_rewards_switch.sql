-- Migration 187: platform feature flags, first flag = "rewards" (Rewards & badges).
--
-- Why: Rewards & badges (migration 165) needs more development, so a platform admin must be able to hide it
-- everywhere (web + iOS) without a release, and turn it back on the same way.
--
-- Shape (same safety pattern as 181's master switch):
--   app_feature_flags        one row per flag, RLS on, no client grants.
--   get_feature_flags()      public (anon + authenticated): { "rewards": false, ... }. Flags are not secrets, and
--                            signed-out visitors must also stop seeing a hidden feature.
--   admin_set_feature_flag() only a platform admin (is_platform_admin(), checked server-side, plus the account
--                            gate). Unknown keys are refused. Every flip is audited.
-- A key that is MISSING from get_feature_flags() means "on" for the client, so a flag added later never hides a
-- feature by accident, and a client that cannot reach the server keeps showing its last-known value.
--
-- SEED: rewards = OFF. Applying this migration hides Rewards & badges (Home streak/coins, Account row, search
-- entry, keychain reward designs, the Rewards screen) for everyone until an admin turns it on in
-- Account > Admin > Feature switches. Only the UI is hidden and no data is deleted. While it is hidden the apps stop
-- calling the reward endpoints, so client-driven streak days (saving an event) are not recorded; coins and badges
-- that the server awards on its own (host-confirmed attendance) keep accruing and show up when it is turned back on.
--
-- Rollback: supabase/rollbacks/20261225000187_187_revert_feature_flags.sql (kept OUT of migrations/).

CREATE TABLE IF NOT EXISTS public.app_feature_flags (
  key text PRIMARY KEY CONSTRAINT app_feature_flags_key_known CHECK (key IN ('rewards')),
  enabled boolean NOT NULL,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_feature_flags ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_feature_flags FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_feature_flags TO service_role;

INSERT INTO public.app_feature_flags (key, enabled) VALUES ('rewards', false)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.app_feature_flags_audit (
  id bigserial PRIMARY KEY,
  admin_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  key text NOT NULL,
  enabled boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_feature_flags_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_feature_flags_audit FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.app_feature_flags_audit TO service_role;

CREATE OR REPLACE FUNCTION public.get_feature_flags()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT coalesce(jsonb_object_agg(key, enabled), '{}'::jsonb) FROM public.app_feature_flags;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_feature_flag(p_key text, p_enabled boolean)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_enabled IS NULL OR p_key IS NULL OR p_key NOT IN ('rewards') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  INSERT INTO public.app_feature_flags (key, enabled, updated_by, updated_at)
  VALUES (p_key, p_enabled, v_admin, now())
  ON CONFLICT (key) DO UPDATE SET enabled = excluded.enabled, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  INSERT INTO public.app_feature_flags_audit (admin_id, key, enabled) VALUES (v_admin, p_key, p_enabled);
  RETURN jsonb_build_object('success', true, 'key', p_key, 'enabled', p_enabled);
END;
$$;

REVOKE ALL ON FUNCTION public.get_feature_flags() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_feature_flag(text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_feature_flags() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_feature_flag(text, boolean) TO authenticated;
