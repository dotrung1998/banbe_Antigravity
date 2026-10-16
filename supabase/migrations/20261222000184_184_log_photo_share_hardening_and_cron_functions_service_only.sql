-- 184: harden log_photo_share and make five maintenance functions server-only.
--
-- Apply status is NOT tracked in this file; check the catalog or ~/stg-evidence/r9/184_prod_verify.sql. Idempotent; safe to re-run. Rollback:
-- supabase/rollbacks/20261222000184_184_revert_log_photo_share_hardening_and_cron_functions_service_only.sql (restores the
-- LESS SAFE previous ACLs and the previous function body; do not run it casually).
--
-- 1. log_photo_share(uuid, text)  (083). Same signature and return type. Found in the R8 audit: anon could call it (PUBLIC held
--    EXECUTE; the old `REVOKE ... FROM anon` does nothing while PUBLIC has it), the body never checked who the caller was, and
--    nothing limited repeats, so one anonymous client could insert unlimited rows (observed on the harness: 500 calls = 500
--    rows with sharer_user_id NULL) and inflate the share count / Pulse ranking.
--      * EXECUTE: REVOKE FROM PUBLIC, anon; GRANT TO authenticated, service_role.
--      * Body: auth.uid() IS NULL -> RAISE 'AUTH_REQUIRED'.
--      * Channel is normalised into a FINITE set before it is stored: 'native', 'copy' and the default 'share' (exactly the
--        values the real clients send: web BanBeContext.jsx sharePhoto -> 'native' | 'copy'; iOS AppState+PhotoEngagement.swift
--        -> default 'native'; the RPC default is 'share'); NULL/empty -> 'share'; ANY other value is stored as 'other'. This
--        keeps free text out of the table and makes the de-duplication below effective (arbitrary channels can no longer
--        create arbitrary rows).
--      * De-duplication per (event_photo_id, sharer_user_id, normalised channel, UTC day): an in-function check first, plus a
--        partial unique index and ON CONFLICT DO NOTHING (the date expression ((created_at AT TIME ZONE 'UTC')::date) is
--        IMMUTABLE, checked on the harness). The index is created only if the existing rows allow it; otherwise the
--        migration skips it with a NOTICE and the in-function check still applies. No existing row is changed or deleted.
--      * The rewritten function sets search_path = public, pg_temp (previously: public). No other function's search_path
--        changes.
--      * Callers (web BanBeContext.jsx, iOS AppState+PhotoEngagement.swift) invoke it only after a completed share by a
--        signed-in user and ignore errors, so a repeated share on the same day is silently a no-op.
--
-- 2. cleanup_expired_stories, close_expired_surveys, expire_stale_admin_invites, expire_stale_holds, sweep_verification_slas.
--    Maintenance functions with no caller in src/, api/, apps/ios, supabase/functions, scripts or tests. pg_cron runs four of
--    them as the job owner (bb_expire_stale_holds, bb_sweep_verification_slas, expire-stale-admin-invites,
--    goc_close_expired_surveys); cleanup_expired_stories has no cron job and no caller at all (nothing in the repo uses it).
--    REVOKE EXECUTE FROM PUBLIC, anon, authenticated; GRANT TO service_role. The owner (postgres) keeps access, so cron is
--    unaffected. No function body changes.
--
-- Each block is skipped when its object does not exist (for example in a reduced local harness). Only privileges, one index
-- and the log_photo_share body change.

CREATE OR REPLACE FUNCTION public.log_photo_share(p_event_photo_id uuid, p_channel text DEFAULT 'share')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  -- Finite channel set: what the real clients send ('native', 'copy') plus the default 'share'; anything else is 'other'.
  v_channel text := CASE
    WHEN coalesce(nullif(trim(p_channel), ''), 'share') IN ('native', 'copy', 'share') THEN coalesce(nullif(trim(p_channel), ''), 'share')
    ELSE 'other'
  END;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM event_photos WHERE id = p_event_photo_id) THEN
    RAISE EXCEPTION 'PHOTO_NOT_FOUND';
  END IF;
  -- One row per (photo, user, channel, UTC day): a repeat on the same day is a silent no-op.
  IF EXISTS (
    SELECT 1 FROM photo_shares s
     WHERE s.event_photo_id = p_event_photo_id AND s.sharer_user_id = v_uid AND s.channel = v_channel
       AND (s.created_at AT TIME ZONE 'UTC')::date = (now() AT TIME ZONE 'UTC')::date
  ) THEN
    RETURN;
  END IF;
  INSERT INTO photo_shares (event_photo_id, sharer_user_id, channel)
  VALUES (p_event_photo_id, v_uid, v_channel)
  ON CONFLICT DO NOTHING;
END;
$$;

DO $$
BEGIN
  IF to_regclass('public.photo_shares') IS NOT NULL THEN
    BEGIN
      CREATE UNIQUE INDEX IF NOT EXISTS photo_shares_one_per_user_channel_day
        ON public.photo_shares (event_photo_id, sharer_user_id, channel, ((created_at AT TIME ZONE 'UTC')::date))
        WHERE sharer_user_id IS NOT NULL;
    EXCEPTION WHEN unique_violation THEN
      RAISE NOTICE '184: existing photo_shares rows contain same-day duplicates; unique index skipped (the in-function check still applies)';
    END;
  END IF;
END;
$$;

DO $$
DECLARE
  v_fn regprocedure;
BEGIN
  v_fn := to_regprocedure('public.log_photo_share(uuid,text)');
  IF v_fn IS NOT NULL THEN
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', v_fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', v_fn);
  END IF;
END;
$$;

DO $$
DECLARE
  v_fn regprocedure;
  v_sig text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.cleanup_expired_stories()',
    'public.close_expired_surveys()',
    'public.expire_stale_admin_invites()',
    'public.expire_stale_holds()',
    'public.sweep_verification_slas()'
  ] LOOP
    v_fn := to_regprocedure(v_sig);
    IF v_fn IS NOT NULL THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', v_fn);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_fn);
    END IF;
  END LOOP;
END;
$$;
