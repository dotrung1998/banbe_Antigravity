-- Follow-up to migration 050's admin_purge_test_dispute_thread(): the
-- first version also deleted the parent dispute_threads row, which meant
-- send_dispute_message() would then return NOT_DISPUTED on the same
-- booking until reject_payment()/escalate_payment_dispute() was called
-- again to recreate it — an extra step the task this was built for
-- ("confirm a fresh send_dispute_message() call on that same booking
-- produces new messages") didn't ask for. Only dispute_messages is purged
-- now; the thread row (still resolved_at IS NULL, still linked to the same
-- guest/organizer) stays, so a fresh message can be sent immediately.
CREATE OR REPLACE FUNCTION public.admin_purge_test_dispute_thread(p_booking uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t dispute_threads%ROWTYPE;
  v_deleted_messages int;
BEGIN
  IF NOT public.is_platform_admin() THEN
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
REVOKE EXECUTE ON FUNCTION public.admin_purge_test_dispute_thread(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_purge_test_dispute_thread(uuid) FROM authenticated;
-- Still deliberately no GRANT to `authenticated` — see migration 050's own
-- note: only reachable via a service-role/psql session, never through any
-- client-side supabase.rpc() call this app's own code makes.
