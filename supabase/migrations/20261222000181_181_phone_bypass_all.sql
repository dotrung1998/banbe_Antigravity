-- Migration 181: platform-admin master switch "waive the SMS step for ALL users".
--
-- NOT APPLIED ANYWHERE. Review, then `supabase db push`. See
-- .claude/notes/32-phone-test-exemption.md. Reverse with
-- supabase/rollbacks/20261222000181_181_revert_phone_bypass_all.sql
-- (kept OUT of supabase/migrations/ so `db push` never runs it).
--
-- Builds on 159. The per-account exemption table is untouched; the same
-- v_test_exempt variable in account_gate_status() / set_date_of_birth() simply
-- also becomes true for everyone while the switch is on. Only the phone
-- requirement is waived: DOB enrollment/confirmation, the RLS gate and every
-- other rule are unchanged, phones are never marked verified, no SMS is sent.
-- Default is OFF. Only a platform admin (is_platform_admin(), decided here
-- server-side) can read or flip it; every flip is audited.

CREATE TABLE IF NOT EXISTS public.app_gate_settings (
  key text PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT false,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_gate_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_gate_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_gate_settings TO service_role;
INSERT INTO public.app_gate_settings (key, enabled) VALUES ('phone_bypass_all', false)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.app_gate_settings_audit (
  id bigserial PRIMARY KEY,
  admin_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  key text NOT NULL,
  enabled boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_gate_settings_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_gate_settings_audit FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.app_gate_settings_audit TO service_role;

-- Patch the CURRENT definitions (same single-occurrence approach as 159).
CREATE OR REPLACE FUNCTION pg_temp.patch_once(src text, old text, new text, what text)
RETURNS text LANGUAGE plpgsql AS $f$
DECLARE n int;
BEGIN
  n := (length(src) - length(replace(src, old, ''))) / length(old);
  IF n <> 1 THEN
    RAISE EXCEPTION '181: expected exactly 1 occurrence of [%] in %, found % — aborting', what, old, n;
  END IF;
  RETURN replace(src, old, new);
END;
$f$;

DO $$
DECLARE
  v_def text;
  v_old constant text :=
    'v_test_exempt := EXISTS (SELECT 1 FROM public.account_phone_test_exempt WHERE user_id = v_uid);';
  v_new constant text :=
    'v_test_exempt := EXISTS (SELECT 1 FROM public.account_phone_test_exempt WHERE user_id = v_uid)'
    || E'\n    OR coalesce((SELECT s.enabled FROM public.app_gate_settings s WHERE s.key = ''phone_bypass_all''), false);';
  v_sig text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY['public.account_gate_status()', 'public.set_date_of_birth(date)'] LOOP
    v_def := pg_get_functiondef(v_sig::regprocedure);
    IF position('app_gate_settings' IN v_def) > 0 THEN
      RAISE NOTICE '181: % already patched — skipping', v_sig;
    ELSE
      v_def := pg_temp.patch_once(v_def, v_old, v_new, v_sig);
      EXECUTE v_def;
    END IF;
    IF position('app_gate_settings' IN pg_get_functiondef(v_sig::regprocedure)) = 0 THEN
      RAISE EXCEPTION '181: post-patch read-back failed for % — aborting', v_sig;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_phone_bypass_all()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  RETURN jsonb_build_object('success', true,
    'enabled', coalesce((SELECT enabled FROM public.app_gate_settings WHERE key = 'phone_bypass_all'), false),
    'updated_at', (SELECT updated_at FROM public.app_gate_settings WHERE key = 'phone_bypass_all'));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_phone_bypass_all(p_enabled boolean)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_enabled IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  INSERT INTO public.app_gate_settings (key, enabled, updated_by, updated_at)
  VALUES ('phone_bypass_all', p_enabled, v_admin, now())
  ON CONFLICT (key) DO UPDATE SET enabled = excluded.enabled, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  INSERT INTO public.app_gate_settings_audit (admin_id, key, enabled) VALUES (v_admin, 'phone_bypass_all', p_enabled);
  RETURN jsonb_build_object('success', true, 'enabled', p_enabled);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_phone_bypass_all() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_phone_bypass_all(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_phone_bypass_all() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_phone_bypass_all(boolean) TO authenticated;
