-- Migration 159: server-controlled phone-OTP exemption for named TEST accounts.
--
-- NOT APPLIED ANYWHERE. Review, then `supabase db push`. See
-- .claude/notes/32-phone-test-exemption.md. Reverse with
-- supabase/rollbacks/20261208000160_160_revert_phone_test_exemption.sql
-- (kept OUT of supabase/migrations/ on purpose so `db push` never runs it).
--
-- What this does
--   * account_phone_test_exempt: one row = "this user may continue without SMS
--     OTP". Written ONLY by the service role (the grant script) or a
--     migration. RLS is on with no policy and every client role is revoked, so
--     no signed-in or anonymous client can read or grant it.
--   * The phone requirement is waived for those users — and ONLY the phone
--     requirement. DOB enrollment, per-session DOB confirmation, the RLS gate
--     and every other rule are untouched. The phone stays UNVERIFIED:
--     phone_verified is still false, auth.users.phone_confirmed_at is never
--     set, and the gate reports a separate `phone_test_exempt` flag so both
--     apps can show "test exemption" distinctly from "verified".
--   * account_phone_grandfathered (the legacy cohort) is NOT touched. It was
--     not reused because it also waives DOB enrollment.
--
-- HOW THE FUNCTIONS ARE PATCHED (not re-created from a copy of migration 124):
--   account_gate_status() and set_date_of_birth() are read back from the live
--   catalog and edited with exact, single-occurrence string replacements. Any
--   later change to those functions is therefore preserved. If an expected
--   fragment is missing or ambiguous the migration ABORTS (nothing is half
--   applied: this file runs in one transaction).

-- ---------------------------------------------------------------------------
-- 1. Table (service-role only)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.account_phone_test_exempt (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  reason text NOT NULL DEFAULT 'test_account',
  granted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,  -- null = granted by the service-role script
  granted_at timestamptz NOT NULL DEFAULT now()
);

-- Who did what (never the DOB value). Service-role / SECURITY DEFINER only.
CREATE TABLE IF NOT EXISTS public.phone_test_exempt_audit (
  id bigserial PRIMARY KEY,
  admin_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  target_user_id uuid NOT NULL,
  action text NOT NULL,
  previous_phone text,
  new_phone text,
  dob_seeded boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.phone_test_exempt_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.phone_test_exempt_audit FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.phone_test_exempt_audit TO service_role;
ALTER TABLE public.account_phone_test_exempt ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_phone_test_exempt FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.account_phone_test_exempt TO service_role;

-- ---------------------------------------------------------------------------
-- 2. Patch the CURRENT function definitions in place
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.patch_once(src text, old text, new text, what text)
RETURNS text LANGUAGE plpgsql AS $f$
DECLARE n int;
BEGIN
  n := (length(src) - length(replace(src, old, ''))) / length(old);
  IF n <> 1 THEN
    RAISE EXCEPTION '159: expected exactly 1 occurrence of [%] in %, found % — aborting', what, old, n;
  END IF;
  RETURN replace(src, old, new);
END;
$f$;

DO $$
DECLARE
  v_def text;
  v_grand_assign constant text :=
    'v_grand := EXISTS (SELECT 1 FROM public.account_phone_grandfathered WHERE user_id = v_uid);';
  v_exempt_assign constant text :=
    'v_test_exempt := EXISTS (SELECT 1 FROM public.account_phone_test_exempt WHERE user_id = v_uid);';
BEGIN
  -- account_gate_status()
  v_def := pg_get_functiondef('public.account_gate_status()'::regprocedure);
  IF position('v_test_exempt' IN v_def) > 0 THEN
    RAISE NOTICE '159: account_gate_status() already patched — skipping';
  ELSE
    v_def := pg_temp.patch_once(v_def, E'  v_grand boolean;\n',
                                E'  v_grand boolean;\n  v_test_exempt boolean;\n', 'gate decl');
    v_def := pg_temp.patch_once(v_def, v_grand_assign,
                                v_grand_assign || E'\n  ' || v_exempt_assign, 'gate assign');
    v_def := pg_temp.patch_once(v_def, 'v_phone_required := NOT v_grand AND NOT v_phone_ok;',
                                'v_phone_required := NOT v_grand AND NOT v_test_exempt AND NOT v_phone_ok;', 'gate phone_required');
    v_def := pg_temp.patch_once(v_def, '''phone_verified'', v_phone_ok,',
                                '''phone_verified'', v_phone_ok,' || E'\n    ' ||
                                '''phone_test_exempt'', (v_test_exempt AND NOT v_phone_ok),', 'gate output');
    EXECUTE v_def;
  END IF;

  -- set_date_of_birth(date)
  v_def := pg_get_functiondef('public.set_date_of_birth(date)'::regprocedure);
  IF position('v_test_exempt' IN v_def) > 0 THEN
    RAISE NOTICE '159: set_date_of_birth() already patched — skipping';
  ELSE
    v_def := pg_temp.patch_once(v_def, E'  v_grand boolean;\n',
                                E'  v_grand boolean;\n  v_test_exempt boolean;\n', 'dob decl');
    v_def := pg_temp.patch_once(v_def, v_grand_assign,
                                v_grand_assign || E'\n  ' || v_exempt_assign, 'dob assign');
    v_def := pg_temp.patch_once(v_def, 'IF NOT v_grand AND NOT v_phone_ok THEN',
                                'IF NOT v_grand AND NOT v_test_exempt AND NOT v_phone_ok THEN', 'dob phone check');
    EXECUTE v_def;
  END IF;

  -- Read back: both live definitions must now carry the exemption.
  IF position('account_phone_test_exempt' IN pg_get_functiondef('public.account_gate_status()'::regprocedure)) = 0
     OR position('account_phone_test_exempt' IN pg_get_functiondef('public.set_date_of_birth(date)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '159: post-patch read-back failed — aborting';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Platform-admin tools (banbetestadmin@gmail.com today): look a user up by
--    email, then set the contact phone / test exemption / missing DOB.
--    Authorization is decided HERE from profiles.role = 'admin'
--    (is_platform_admin(); role writes are blocked for clients by
--    guard_profile_role, migration 016) — never from anything the client
--    sends. A user can never call these for themselves: target <> caller.
--    Rules: DOB is only ever INSERTED when absent (an existing DOB is never
--    changed); profiles.phone_verified / auth phone are never touched; the
--    legacy grandfathered cohort is never edited; no SMS is sent.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_phone_exempt_lookup(p_email text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_id uuid;
  v_email text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  SELECT id, email INTO v_id, v_email FROM auth.users
   WHERE lower(email) = lower(trim(coalesce(p_email, ''))) LIMIT 1;
  IF v_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_NOT_FOUND');
  END IF;
  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_id,
    'email', v_email,
    'display_name', (SELECT p.display_name FROM public.profiles p WHERE p.id = v_id),
    'role', (SELECT p.role FROM public.profiles p WHERE p.id = v_id),
    'profile_phone', coalesce((SELECT p.phone FROM public.profiles p WHERE p.id = v_id), ''),
    'phone_verified', EXISTS (SELECT 1 FROM auth.users u WHERE u.id = v_id AND coalesce(u.phone, '') <> '' AND u.phone_confirmed_at IS NOT NULL),
    'grandfathered', EXISTS (SELECT 1 FROM public.account_phone_grandfathered WHERE user_id = v_id),
    'test_exempt', EXISTS (SELECT 1 FROM public.account_phone_test_exempt WHERE user_id = v_id),
    'has_dob', EXISTS (SELECT 1 FROM public.user_private_dob WHERE user_id = v_id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_phone_exemption(
  p_user_id uuid, p_phone text, p_dob date, p_grant boolean)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
  v_prev_phone text;
  v_grand boolean;
  v_seeded boolean := false;
  v_existing date;
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_user_id IS NULL OR p_user_id = v_admin THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_TARGET');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id)
     OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_NOT_FOUND');
  END IF;

  -- Validate everything BEFORE writing anything.
  IF v_phone IS NOT NULL THEN
    IF v_phone !~ '^\+[1-9][0-9]{7,14}$'
       OR (v_phone ~ '^\+1' AND v_phone !~ '^\+1[2-9][0-9]{2}[2-9][0-9]{6}$')
       OR (v_phone ~ '^\+49' AND v_phone !~ '^\+49[1-9][0-9]{9,10}$') THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_PHONE');
    END IF;
    IF EXISTS (SELECT 1 FROM public.profiles
                WHERE id <> p_user_id AND phone IN (v_phone, substr(v_phone, 2))) THEN
      RETURN jsonb_build_object('success', false, 'error', 'PHONE_IN_USE');
    END IF;
  END IF;
  IF p_dob IS NOT NULL THEN
    IF p_dob < DATE '1900-01-01' OR p_dob > current_date THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_DOB');
    END IF;
    SELECT date_of_birth INTO v_existing FROM public.user_private_dob WHERE user_id = p_user_id;
    IF v_existing IS NOT NULL AND v_existing <> p_dob THEN
      RETURN jsonb_build_object('success', false, 'error', 'DOB_ALREADY_SET');
    END IF;
  END IF;
  v_grand := EXISTS (SELECT 1 FROM public.account_phone_grandfathered WHERE user_id = p_user_id);

  SELECT phone INTO v_prev_phone FROM public.profiles WHERE id = p_user_id;
  IF v_phone IS NOT NULL THEN
    UPDATE public.profiles SET phone = v_phone WHERE id = p_user_id;
  END IF;

  IF coalesce(p_grant, false) AND NOT v_grand THEN
    INSERT INTO public.account_phone_test_exempt (user_id, reason, granted_by)
    VALUES (p_user_id, 'test_account', v_admin)
    ON CONFLICT (user_id) DO NOTHING;
  ELSIF NOT coalesce(p_grant, false) THEN
    DELETE FROM public.account_phone_test_exempt WHERE user_id = p_user_id;
  END IF;

  IF p_dob IS NOT NULL AND v_existing IS NULL THEN
    INSERT INTO public.user_private_dob (user_id, date_of_birth, source)
    VALUES (p_user_id, p_dob, 'admin_test_seed')
    ON CONFLICT (user_id) DO NOTHING;
    v_seeded := true;
  END IF;

  INSERT INTO public.phone_test_exempt_audit (admin_id, target_user_id, action, previous_phone, new_phone, dob_seeded)
  VALUES (v_admin, p_user_id, CASE WHEN coalesce(p_grant, false) THEN 'grant' ELSE 'revoke' END,
          v_prev_phone, v_phone, v_seeded);

  RETURN jsonb_build_object('success', true, 'grandfathered', v_grand,
    'test_exempt', EXISTS (SELECT 1 FROM public.account_phone_test_exempt WHERE user_id = p_user_id),
    'dob_seeded', v_seeded);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_phone_exempt_lookup(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_phone_exemption(uuid, text, date, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_phone_exempt_lookup(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_phone_exemption(uuid, text, date, boolean) TO authenticated;
