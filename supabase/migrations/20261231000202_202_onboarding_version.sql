-- 202 — Onboarding Version 3 + one atomic version setter (note 64).
--
-- Versions:
--   1 = still Welcome screen + the 4 text pages of "How banbe works" (onboarding_v2 off, onboarding_v3 off)
--   2 = animated Welcome + swipeable demo screens (note 63)          (onboarding_v2 on)
--   3 = Version 2 + a guided tour over the real app after the first sign-in (onboarding_v3 on)
--
-- Clients resolve v3 > v2 > v1, so a stray pair can never mean two versions at once. Admin UIs set the version through
-- admin_set_onboarding_version(), which writes BOTH booleans in one transaction and audits each. Older clients that only
-- know onboarding_v2 keep showing Version 1/2 (picking 3 turns onboarding_v2 off, so they fall back to Version 1).
-- Client-only switches: no server function checks them. Seeded OFF, so nothing changes until an admin picks Version 3.
--
-- Rollback: supabase/rollbacks/20261231000202_202_revert_onboarding_version.sql (kept OUT of migrations/).

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('onboarding_v3', 'Onboarding Version 3: Version 2 + guided tour over the real app (set via admin_set_onboarding_version)', '202')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('onboarding_v3', false)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_set_onboarding_version(p_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
  v_v2 boolean;
  v_v3 boolean;
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_version IS NULL OR p_version NOT IN (1, 2, 3) THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  v_v2 := p_version = 2;
  v_v3 := p_version = 3;
  INSERT INTO public.app_feature_flags (key, enabled, updated_by, updated_at) VALUES
    ('onboarding_v2', v_v2, v_admin, now()),
    ('onboarding_v3', v_v3, v_admin, now())
  ON CONFLICT (key) DO UPDATE SET enabled = excluded.enabled, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  INSERT INTO public.app_feature_flags_audit (admin_id, key, enabled) VALUES
    (v_admin, 'onboarding_v2', v_v2),
    (v_admin, 'onboarding_v3', v_v3);
  RETURN jsonb_build_object('success', true, 'version', p_version);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_set_onboarding_version(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_onboarding_version(integer) TO authenticated;
