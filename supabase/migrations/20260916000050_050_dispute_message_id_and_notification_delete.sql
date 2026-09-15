-- .claude/notes/07-notifications.md, follow-up to migration 048.
--
-- Task 1: send_dispute_message() didn't capture the new dispute_messages
-- row's own id, so the notification it wrote had no way to point a client
-- back at the specific message — only the thread. Additive only: same
-- role checks, same error returns, same recipient logic.
CREATE OR REPLACE FUNCTION public.send_dispute_message(p_booking uuid, p_body text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t dispute_threads%ROWTYPE;
  v_body text := left(trim(COALESCE(p_body, '')), 2000);
  v_role text;
  v_msg_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF v_body = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMPTY_MESSAGE');
  END IF;

  SELECT * INTO v_t FROM dispute_threads WHERE booking_id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_DISPUTED');
  END IF;
  IF v_t.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'DISPUTE_RESOLVED');
  END IF;

  IF v_t.guest_id = auth.uid() THEN
    v_role := 'guest';
  ELSIF EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_t.organizer_id
                AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    v_role := 'organizer';
  ELSIF public.is_platform_admin() THEN
    v_role := 'admin';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  INSERT INTO dispute_messages (dispute_thread_id, sender_id, sender_role, body)
  VALUES (v_t.id, auth.uid(), v_role, v_body)
  RETURNING id INTO v_msg_id;

  -- Notify whoever didn't just send it — the guest and both accounts an
  -- organizer row can resolve to (owner_id/user_id), minus the sender and
  -- any NULLs. Not the admin: there's no fixed "the admin" recipient the
  -- way there is for the other two parties, and no established pattern
  -- elsewhere in this schema for broadcasting to admins generally.
  INSERT INTO notifications (recipient_id, kind, title, body, data)
  SELECT recipient, 'dispute_message', 'Tin nhắn mới về tranh chấp',
         v_body, jsonb_build_object('booking_id', p_booking, 'dispute_thread_id', v_t.id, 'message_id', v_msg_id)
  FROM (
    SELECT v_t.guest_id AS recipient
    UNION
    SELECT o.owner_id FROM organizers o WHERE o.id = v_t.organizer_id
    UNION
    SELECT o.user_id FROM organizers o WHERE o.id = v_t.organizer_id
  ) recipients
  WHERE recipient IS NOT NULL AND recipient <> auth.uid();

  RETURN jsonb_build_object('success', true, 'message_id', v_msg_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.send_dispute_message(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_dispute_message(uuid, text) TO authenticated;

-- No other notification `kind` gets the same treatment: booking_requested,
-- payment_confirmed, payment_disputed, payment_needs_info, dispute_resolved,
-- hold_expired, verification_reminder/escalation, booking_cancelled,
-- referral_joined are all status notifications whose own title/body already
-- says everything — none of them exist to point at a specific chat message
-- the way dispute_message does, even though a few (reject_payment,
-- escalate_payment_dispute, resolve_dispute) also drop an unrelated system
-- note into the permanent `messages` table as a side effect. Wiring a
-- message_id onto those would have no consuming UI (Task 2 only wires up
-- the dispute chat panel's highlight, not the ordinary Chat.jsx screen) —
-- dead data, not consistency.

-- Task 4: let a user delete their own notifications. Not audit-sensitive
-- (unlike dispute_messages — see Task 5 below and 05-notify-retention.md's
-- 72h retention requirement, which this does NOT touch), so a real,
-- permanent DELETE is fine; no RPC needed since RLS alone already scopes it
-- correctly to the caller's own rows, the same way notifications_select_own/
-- notifications_update_own (migration 019) already do.
DROP POLICY IF EXISTS "notifications_delete_own" ON public.notifications;
CREATE POLICY "notifications_delete_own" ON public.notifications
  FOR DELETE TO authenticated USING (auth.uid() = recipient_id);

-- Task 5: a narrowly-scoped, admin-only cleanup path for resetting a
-- SPECIFIC test booking's dispute chat — NOT reachable from the regular
-- participant/organizer UI (no client code calls this; it's a manual
-- command, see the session's final report for the exact invocation).
-- Deliberately refuses anything already resolved: dispute_messages is the
-- audit trail 05-notify-retention.md requires kept for 72h after
-- resolution, and this must never be usable to defeat that retention on a
-- real case, only to reset a still-open test one.
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
  DELETE FROM dispute_threads WHERE id = v_t.id;

  RETURN jsonb_build_object('success', true, 'deleted_messages', v_deleted_messages, 'deleted_thread', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_purge_test_dispute_thread(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_purge_test_dispute_thread(uuid) FROM authenticated;
-- Deliberately no GRANT to `authenticated` at all — even a signed-in admin
-- can only reach this via a service-role/psql session (see the report),
-- not through any client-side supabase.rpc() call this app's own code
-- ever makes. is_platform_admin() is still checked as a second, redundant
-- gate in case that ever changes.
