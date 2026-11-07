-- Fixes two real bugs in admin_purge_test_dispute_thread() found by
-- actually testing it end-to-end (not just reading the SQL) before handing
-- the command to the user:
--
-- 1. `REVOKE ... FROM authenticated` alone does NOT block a signed-in
--    admin's own browser session from calling this — Postgres grants
--    EXECUTE on a new function to PUBLIC by default, and `authenticated`
--    is implicitly a member of PUBLIC, so the broader PUBLIC grant was
--    still in effect underneath the narrower revoke. Confirmed by actually
--    calling it via an authenticated admin JWT: it succeeded when it
--    should have been refused outright at the privilege level. Fixed by
--    also revoking from PUBLIC.
-- 2. is_platform_admin() checks `auth.uid() = ... AND role = 'admin'` —
--    called via the service-role key (the ONLY way this function is
--    reachable at all, now that #1 is fixed), there is no JWT and so no
--    `auth.uid()`, meaning is_platform_admin() always returned false and
--    the function refused EVERY service-role call with ADMIN_ONLY,
--    including the legitimate ones. Fixed: only require is_platform_admin()
--    when there IS a JWT identity to check (auth.uid() IS NOT NULL) — a
--    null auth.uid() only ever happens via the service role or a direct
--    superuser/psql session, both of which already can't reach this
--    function unless deliberately connected with elevated credentials.
CREATE OR REPLACE FUNCTION public.admin_purge_test_dispute_thread(p_booking uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t dispute_threads%ROWTYPE;
  v_deleted_messages int;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_platform_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADMIN_ONLY');
  END IF;

  SELECT * INTO v_t FROM dispute_threads WHERE booking_id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_DISPUTED');
  END IF;
  IF v_t.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_RESOLVED_REFUSING_TO_PURGE');
  END IF;

  DELETE FROM dispute_messages WHERE dispute_thread_id = v_t.id;
  GET DIAGNOSTICS v_deleted_messages = ROW_COUNT;

  RETURN jsonb_build_object('success', true, 'deleted_messages', v_deleted_messages, 'thread_kept', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_purge_test_dispute_thread(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_purge_test_dispute_thread(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_purge_test_dispute_thread(uuid) FROM authenticated;
-- Still no GRANT to `authenticated` — only reachable via a service-role
-- connection (SUPABASE_SERVICE_ROLE_KEY, or the Supabase Dashboard's SQL
-- Editor / a direct psql session, both of which run as a privileged
-- Postgres role that these REVOKEs don't apply to), never through any
-- client-side supabase.rpc() call this app's own code makes.
