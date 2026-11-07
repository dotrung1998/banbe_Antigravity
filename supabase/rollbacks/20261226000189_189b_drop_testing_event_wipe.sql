-- BEFORE PUBLIC RELEASE (note 54): removes the TESTING-PHASE admin event wipe and its feature switch.
-- Turn it into a real migration (copy into supabase/migrations/ with the next number) when the owner says the app is
-- ready for public release. Pair it with deleting the iOS code marked TESTING-PHASE:
--   apps/ios/BanbeApp/State/AppState+AdminManageEvents.swift   AdminEventAction.wipeTesting
--   apps/ios/BanbeApp/Views/AdminManageEventsView.swift        confirmWipe / wipe button / wipeEnabled
--   apps/ios/BanbeApp/Views/AdminFeaturesView.swift            the "admin_event_wipe" row
--   apps/ios/BanbeApp/Lib/FeatureFlags.swift                   "admin_event_wipe" in keys / offUnlessSet
--   apps/ios/BanbeApp/App/UITestFixtures.swift + BanbeAppUITests/AdminManageEventsUITests.swift (wipe test)
-- The public remove / restore / purge features stay.

DROP FUNCTION IF EXISTS public.admin_wipe_events_testing(text[]);
DELETE FROM public.app_feature_flags WHERE key = 'admin_event_wipe';
ALTER TABLE public.app_feature_flags DROP CONSTRAINT IF EXISTS app_feature_flags_key_known;
ALTER TABLE public.app_feature_flags ADD CONSTRAINT app_feature_flags_key_known CHECK (key IN ('rewards'));

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
REVOKE ALL ON FUNCTION public.admin_set_feature_flag(text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_feature_flag(text, boolean) TO authenticated;
