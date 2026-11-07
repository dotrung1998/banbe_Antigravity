-- Reverts migration 181 (global phone bypass). Restores the 159 per-account
-- exemption line in both gate functions, then drops the RPCs/tables.
DO $$
DECLARE
  v_def text; v_sig text;
  v_new constant text := E'v_test_exempt := EXISTS (SELECT 1 FROM public.account_phone_test_exempt WHERE user_id = v_uid)\n    OR coalesce((SELECT s.enabled FROM public.app_gate_settings s WHERE s.key = ''phone_bypass_all''), false);';
  v_old constant text := 'v_test_exempt := EXISTS (SELECT 1 FROM public.account_phone_test_exempt WHERE user_id = v_uid);';
BEGIN
  FOREACH v_sig IN ARRAY ARRAY['public.account_gate_status()', 'public.set_date_of_birth(date)'] LOOP
    v_def := pg_get_functiondef(v_sig::regprocedure);
    IF position(v_new IN v_def) > 0 THEN
      EXECUTE replace(v_def, v_new, v_old);
    END IF;
  END LOOP;
END;
$$;
DROP FUNCTION IF EXISTS public.admin_set_phone_bypass_all(boolean);
DROP FUNCTION IF EXISTS public.admin_get_phone_bypass_all();
DROP TABLE IF EXISTS public.app_gate_settings_audit;
DROP TABLE IF EXISTS public.app_gate_settings;
