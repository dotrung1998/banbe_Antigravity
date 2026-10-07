-- Rollback for migration 159 ONLY: removes the phone test exemption and nothing
-- else. Forward migration (not a restore of 124): it reverses 159's exact
-- string edits on the CURRENT live function definitions, so every other later
-- change to account_gate_status()/set_date_of_birth() is preserved.
--
-- Kept in supabase/rollbacks/ so `supabase db push` does NOT run it. To use it,
-- review, then either copy it into supabase/migrations/ as version 160 and
-- `db push`, or run it once in the SQL editor.
--
-- After it runs, exempt users are gated by the phone requirement again (they
-- keep their DOB, roles, bookings and profiles.phone contact number). Drop
-- of the table also removes the exemption rows — note them first if you want
-- to re-grant later (the grant script's dry-run prints them).

CREATE OR REPLACE FUNCTION pg_temp.unpatch_once(src text, old text, new text, what text)
RETURNS text LANGUAGE plpgsql AS $f$
DECLARE n int;
BEGIN
  n := (length(src) - length(replace(src, old, ''))) / length(old);
  IF n <> 1 THEN
    RAISE EXCEPTION '160: expected exactly 1 occurrence of [%] in %, found % — aborting', what, old, n;
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
  IF to_regclass('public.account_phone_test_exempt') IS NOT NULL THEN
    RAISE NOTICE '160: removing % exemption row(s)', (SELECT count(*) FROM public.account_phone_test_exempt);
  END IF;

  v_def := pg_get_functiondef('public.account_gate_status()'::regprocedure);
  IF position('v_test_exempt' IN v_def) = 0 THEN
    RAISE NOTICE '160: account_gate_status() not patched — skipping';
  ELSE
    v_def := pg_temp.unpatch_once(v_def, E'  v_grand boolean;\n  v_test_exempt boolean;\n', E'  v_grand boolean;\n', 'gate decl');
    v_def := pg_temp.unpatch_once(v_def, v_grand_assign || E'\n  ' || v_exempt_assign, v_grand_assign, 'gate assign');
    v_def := pg_temp.unpatch_once(v_def, 'v_phone_required := NOT v_grand AND NOT v_test_exempt AND NOT v_phone_ok;',
                                  'v_phone_required := NOT v_grand AND NOT v_phone_ok;', 'gate phone_required');
    v_def := pg_temp.unpatch_once(v_def, '''phone_verified'', v_phone_ok,' || E'\n    ' ||
                                  '''phone_test_exempt'', (v_test_exempt AND NOT v_phone_ok),',
                                  '''phone_verified'', v_phone_ok,', 'gate output');
    EXECUTE v_def;
  END IF;

  v_def := pg_get_functiondef('public.set_date_of_birth(date)'::regprocedure);
  IF position('v_test_exempt' IN v_def) = 0 THEN
    RAISE NOTICE '160: set_date_of_birth() not patched — skipping';
  ELSE
    v_def := pg_temp.unpatch_once(v_def, E'  v_grand boolean;\n  v_test_exempt boolean;\n', E'  v_grand boolean;\n', 'dob decl');
    v_def := pg_temp.unpatch_once(v_def, v_grand_assign || E'\n  ' || v_exempt_assign, v_grand_assign, 'dob assign');
    v_def := pg_temp.unpatch_once(v_def, 'IF NOT v_grand AND NOT v_test_exempt AND NOT v_phone_ok THEN',
                                  'IF NOT v_grand AND NOT v_phone_ok THEN', 'dob phone check');
    EXECUTE v_def;
  END IF;

  IF position('account_phone_test_exempt' IN pg_get_functiondef('public.account_gate_status()'::regprocedure)) > 0
     OR position('account_phone_test_exempt' IN pg_get_functiondef('public.set_date_of_birth(date)'::regprocedure)) > 0 THEN
    RAISE EXCEPTION '160: functions still reference the exemption table — aborting';
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_phone_exempt_lookup(text);
DROP FUNCTION IF EXISTS public.admin_set_phone_exemption(uuid, text, date, boolean);
DROP TABLE IF EXISTS public.account_phone_test_exempt;
DROP TABLE IF EXISTS public.phone_test_exempt_audit;
