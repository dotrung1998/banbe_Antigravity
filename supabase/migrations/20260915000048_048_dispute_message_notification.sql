-- .claude/notes/07-notifications.md: send_dispute_message() was the one
-- event type in the whole dispute flow with no `notifications` row at all
-- — every sibling RPC (reject_payment, escalate_payment_dispute,
-- resolve_dispute, verify_payment...) already writes one. A message sent
-- into the temporary dispute chat previously had no signal for the other
-- party beyond reopening that exact panel (DisputeChatPanel.jsx's own 4s
-- poll, only useful while it's already open).
CREATE OR REPLACE FUNCTION public.send_dispute_message(p_booking uuid, p_body text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t dispute_threads%ROWTYPE;
  v_body text := left(trim(COALESCE(p_body, '')), 2000);
  v_role text;
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
  VALUES (v_t.id, auth.uid(), v_role, v_body);

  -- Notify whoever didn't just send it — the guest and both accounts an
  -- organizer row can resolve to (owner_id/user_id), minus the sender and
  -- any NULLs. Not the admin: there's no fixed "the admin" recipient the
  -- way there is for the other two parties, and no established pattern
  -- elsewhere in this schema for broadcasting to admins generally.
  INSERT INTO notifications (recipient_id, kind, title, body, data)
  SELECT recipient, 'dispute_message', 'Tin nhắn mới về tranh chấp',
         v_body, jsonb_build_object('booking_id', p_booking, 'dispute_thread_id', v_t.id)
  FROM (
    SELECT v_t.guest_id AS recipient
    UNION
    SELECT o.owner_id FROM organizers o WHERE o.id = v_t.organizer_id
    UNION
    SELECT o.user_id FROM organizers o WHERE o.id = v_t.organizer_id
  ) recipients
  WHERE recipient IS NOT NULL AND recipient <> auth.uid();

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.send_dispute_message(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_dispute_message(uuid, text) TO authenticated;
