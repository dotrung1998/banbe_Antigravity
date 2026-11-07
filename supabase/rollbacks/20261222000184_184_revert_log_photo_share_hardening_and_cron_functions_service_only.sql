-- Reverts migration 184. THIS RESTORES A LESS SAFE STATE; do not run it casually.
-- The grants restored below are the ones OBSERVED on production before 184 (production audit query A, full result, 2026-10-15):
--   log_photo_share                                                      PUBLIC (anon and authenticated gain EXECUTE through it)
--   cleanup_expired_stories                                              anon + authenticated (explicit grants, no PUBLIC entry)
--   close_expired_surveys, expire_stale_admin_invites, expire_stale_holds, sweep_verification_slas   PUBLIC
-- The previous log_photo_share body (083: no auth check, no channel normalisation, no de-duplication; search_path = public, as
-- observed on production) is restored and the de-duplication index is dropped (no row is touched; rows written after 184 keep
-- their normalised channel values). Keep this file OUT of supabase/migrations/ so `db push` never runs it.

DROP INDEX IF EXISTS public.photo_shares_one_per_user_channel_day;

CREATE OR REPLACE FUNCTION public.log_photo_share(p_event_photo_id uuid, p_channel text DEFAULT 'share')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM event_photos WHERE id = p_event_photo_id) THEN
    RAISE EXCEPTION 'PHOTO_NOT_FOUND';
  END IF;
  INSERT INTO photo_shares (event_photo_id, sharer_user_id, channel)
  VALUES (p_event_photo_id, auth.uid(), left(coalesce(nullif(trim(p_channel), ''), 'share'), 40));
END;
$$;

DO $$
DECLARE
  v_fn regprocedure;
BEGIN
  v_fn := to_regprocedure('public.log_photo_share(uuid,text)');
  IF v_fn IS NOT NULL THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC, authenticated', v_fn); END IF;
  v_fn := to_regprocedure('public.cleanup_expired_stories()');
  IF v_fn IS NOT NULL THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated', v_fn); END IF;
  v_fn := to_regprocedure('public.close_expired_surveys()');
  IF v_fn IS NOT NULL THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC', v_fn); END IF;
  v_fn := to_regprocedure('public.expire_stale_admin_invites()');
  IF v_fn IS NOT NULL THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC', v_fn); END IF;
  v_fn := to_regprocedure('public.expire_stale_holds()');
  IF v_fn IS NOT NULL THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC', v_fn); END IF;
  v_fn := to_regprocedure('public.sweep_verification_slas()');
  IF v_fn IS NOT NULL THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO PUBLIC', v_fn); END IF;
END;
$$;
