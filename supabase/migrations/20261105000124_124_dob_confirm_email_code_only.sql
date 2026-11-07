-- Migration 124: Confirm date of birth only for EMAIL-CODE sessions.
--
-- 123 required the DOB confirmation for every session of an account that has a
-- DOB. Password, Google and Facebook sign-ins must not be asked: they are
-- exempt when the session's signed JWT `amr` claim lists a `password` or
-- `oauth` method. Email-code (OTP) sessions are still gated; so is a token
-- with no amr claim. First-time enrollment (verified phone + DOB for a NEW
-- registration) is unchanged.
--
-- Only account_gate_status() changes (everything that reads the gate —
-- account_gate_ok(), the RLS policies — calls it).

CREATE OR REPLACE FUNCTION public.account_gate_status()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sid uuid := public.current_session_id();
  v_grand boolean;
  v_phone_ok boolean;
  v_has_dob boolean;
  v_confirmed boolean;
  v_locked timestamptz;
  v_phone_required boolean;
  v_dob_enroll boolean;
  v_dob_confirm boolean;
  v_exempt boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ready', false, 'error', 'AUTH_REQUIRED');
  END IF;

  v_grand := EXISTS (SELECT 1 FROM public.account_phone_grandfathered WHERE user_id = v_uid);
  v_phone_ok := EXISTS (
    SELECT 1 FROM auth.users u
    WHERE u.id = v_uid AND coalesce(u.phone, '') <> '' AND u.phone_confirmed_at IS NOT NULL
  );
  v_has_dob := EXISTS (SELECT 1 FROM public.user_private_dob WHERE user_id = v_uid);
  v_confirmed := v_sid IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.dob_session_confirmations WHERE session_id = v_sid AND user_id = v_uid
  );
  SELECT locked_until INTO v_locked FROM public.dob_attempts
   WHERE user_id = v_uid AND locked_until > now();

  -- New registrations need a verified phone and a DOB. The grandfathered
  -- legacy cohort needs neither (their current login is unchanged).
  v_phone_required := NOT v_grand AND NOT v_phone_ok;
  v_dob_enroll := NOT v_grand AND NOT v_has_dob;
  -- Confirm date of birth applies to sessions that signed in with an EMAIL
  -- CODE only. A session whose JWT `amr` shows a password or OAuth
  -- (Google / Facebook / Apple) sign-in is already strongly authenticated and
  -- is exempt. The method comes from the signed token, never from the client.
  -- A token with no amr claim is NOT exempt (fails closed).
  v_exempt := EXISTS (
    SELECT 1
      FROM jsonb_array_elements(
             CASE WHEN jsonb_typeof(auth.jwt() -> 'amr') = 'array' THEN auth.jwt() -> 'amr' ELSE '[]'::jsonb END
           ) AS a
     WHERE coalesce(a ->> 'method', a #>> '{}') IN ('password', 'oauth')
  );
  -- Anyone who HAS a DOB must confirm it once per session — unless exempt.
  v_dob_confirm := v_has_dob AND NOT v_confirmed AND NOT v_exempt;

  RETURN jsonb_build_object(
    'ready', NOT (v_phone_required OR v_dob_enroll OR v_dob_confirm),
    'phone_required', v_phone_required,
    'phone_verified', v_phone_ok,
    'dob_enrollment_required', v_dob_enroll,
    'dob_confirmation_required', v_dob_confirm,
    'locked_until', v_locked
  );
END;
$$;
