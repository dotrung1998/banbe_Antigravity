-- Reverts migration 183: restores the ACLs that were observed on STAGING before the patch (R4/R6/R7). They are the LESS SAFE
-- state: anon (through PUBLIC or explicit grants) could execute the four functions and read the four views.
-- The production ACLs before the manual patch were NOT read by this repo author; confirm them (SELECT on pg_proc.proacl /
-- pg_class.relacl) before relying on this file there. Do not run it casually.
-- Kept OUT of supabase/migrations/ so `db push` never runs it.
--   record_bank_transaction, verify_payment_from_bot : PUBLIC (+ postgres, service_role as before)
--   log_payment_event                                : PUBLIC, anon, authenticated
--   verify_phone_otp                                 : PUBLIC, authenticated
--   the four views                                   : ALL to anon, authenticated
DO $$
DECLARE
  v_fn regprocedure;
BEGIN
  v_fn := to_regprocedure('public.record_bank_transaction(text,text,bigint,text,jsonb,boolean)');
  IF v_fn IS NOT NULL THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC', v_fn); END IF;
  v_fn := to_regprocedure('public.verify_payment_from_bot(uuid,text,boolean,text,text)');
  IF v_fn IS NOT NULL THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC', v_fn); END IF;
  v_fn := to_regprocedure('public.log_payment_event(uuid,text,public.payment_state,public.payment_state,uuid,text,text,text,jsonb)');
  IF v_fn IS NOT NULL THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC, anon, authenticated', v_fn); END IF;
  v_fn := to_regprocedure('public.verify_phone_otp(uuid,text)');
  IF v_fn IS NOT NULL THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC, authenticated', v_fn); END IF;
END;
$$;

DO $$
DECLARE
  v_rel regclass;
  v_name text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY['public.reservations', 'public.checkins', 'public.v_host_ledger', 'public.v_event_availability'] LOOP
    v_rel := to_regclass(v_name);
    IF v_rel IS NOT NULL THEN
      EXECUTE format('GRANT ALL ON TABLE %s TO anon, authenticated', v_rel);
    END IF;
  END LOOP;
END;
$$;
