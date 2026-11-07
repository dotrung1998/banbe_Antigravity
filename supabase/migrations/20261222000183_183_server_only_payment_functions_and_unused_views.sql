-- 183: server-only EXECUTE on four payment/phone functions, and no client access to four unused definer views.
--
-- NUMBERING NOTE. The R3/R5 staging write-ups call the patch set "migration 181". The real numbers are 182
-- (email_registrations) and 183 (this file): 181 was already taken by 181_phone_bypass_all.
--
-- ALREADY APPLIED BY HAND ON PRODUCTION. The statements below were run manually on production (patch round 1). This file
-- exists so local, staging and new projects get the same state. It is idempotent, so on production it is a NO-OP:
-- REVOKE of privileges that are already gone and GRANT of ones already present change nothing.
--
-- WHY (observed on staging, R4/R6/R7). Earlier migrations only did `REVOKE ... FROM anon`, which does nothing while PUBLIC
-- still holds EXECUTE (the default for functions), so anon could still call these. The views run with their owner's
-- rights (BYPASSRLS) and had the Supabase default grants for anon/authenticated.
--   * record_bank_transaction(...)   bank webhook; trusts the caller's p_signature_ok. Only api/payment-webhook.js (service role).
--   * verify_payment_from_bot(...)   Telegram approve/reject. Only api/telegram-webhook.js (service role).
--   * log_payment_event(...)         audit-log writer; only called from SECURITY DEFINER SQL functions (owner postgres).
--   * verify_phone_otp(uuid, text)   marks any profile's phone verified; no caller anywhere in the repo.
--   * views reservations, checkins, v_host_ledger, v_event_availability: no caller in src/api/apps/functions/tests.
-- No object is created, altered or dropped; ONLY privileges change, and only for what is listed here.
--
-- Each block is skipped when the object does not exist (for example in a reduced local harness).
--
-- ROLLBACK: supabase/rollbacks/20261222000183_183_revert_server_only_payment_functions_and_unused_views.sql restores the
-- previous, LESS SAFE ACLs. Do not run it casually.

DO $$
DECLARE
  v_fn regprocedure;
  v_sig text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.record_bank_transaction(text,text,bigint,text,jsonb,boolean)',
    'public.verify_payment_from_bot(uuid,text,boolean,text,text)',
    'public.log_payment_event(uuid,text,public.payment_state,public.payment_state,uuid,text,text,text,jsonb)',
    'public.verify_phone_otp(uuid,text)'
  ] LOOP
    v_fn := to_regprocedure(v_sig);
    IF v_fn IS NOT NULL THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', v_fn);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_fn);
    END IF;
  END LOOP;
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
      EXECUTE format('REVOKE ALL ON TABLE %s FROM anon, authenticated', v_rel);
    END IF;
  END LOOP;
END;
$$;
