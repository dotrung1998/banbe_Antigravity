-- 197 — F3: minimum age 16 at the date-of-birth step (owner decision 2026-10-23; policy A1 already says 16+).
-- Same function as 123 (body copied, one check added); same signature, same return shape, one new error code
-- AGE_TOO_YOUNG. Existing accounts are not re-checked and nobody is locked out; only a NEW date of birth under 16 is
-- refused. Clients show why (web src/lib/accountGate.js, iOS AuthViewModel+Gate.swift).
--
-- Rollback: supabase/rollbacks/20261230000197_197_revert_age_minimum.sql (re-runs 123's definition).

CREATE OR REPLACE FUNCTION public.set_date_of_birth(p_dob date)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sid uuid := public.current_session_id();
  v_grand boolean;
  v_phone_ok boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF p_dob IS NULL OR p_dob < DATE '1900-01-01' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_DOB');
  END IF;
  IF p_dob > current_date THEN
    RETURN jsonb_build_object('success', false, 'error', 'DOB_IN_FUTURE');
  END IF;
  -- 197: banbe is for people aged 16 and over (policy A1; under 16 needs parental consent under the PDPL, which banbe
  -- does not collect). Judged on the latest calendar date anywhere on Earth, so nobody whose 16th birthday is today
  -- in their own time zone is refused. Existing accounts are not re-checked.
  IF p_dob > ((now() AT TIME ZONE 'Pacific/Kiritimati')::date - interval '16 years')::date THEN
    RETURN jsonb_build_object('success', false, 'error', 'AGE_TOO_YOUNG', 'min_age', 16);
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_private_dob WHERE user_id = v_uid) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_SET');
  END IF;

  v_grand := EXISTS (SELECT 1 FROM public.account_phone_grandfathered WHERE user_id = v_uid);
  v_phone_ok := EXISTS (
    SELECT 1 FROM auth.users u
    WHERE u.id = v_uid AND coalesce(u.phone, '') <> '' AND u.phone_confirmed_at IS NOT NULL
  );
  IF NOT v_grand AND NOT v_phone_ok THEN
    RETURN jsonb_build_object('success', false, 'error', 'PHONE_NOT_VERIFIED');
  END IF;

  INSERT INTO public.user_private_dob (user_id, date_of_birth, source)
  VALUES (v_uid, p_dob, 'signup')
  ON CONFLICT (user_id) DO NOTHING;

  IF v_sid IS NOT NULL THEN
    INSERT INTO public.dob_session_confirmations (session_id, user_id)
    VALUES (v_sid, v_uid)
    ON CONFLICT (session_id) DO NOTHING;
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.set_date_of_birth(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_date_of_birth(date) TO authenticated;
