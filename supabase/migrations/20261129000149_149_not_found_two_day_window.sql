-- Migration: "can't find the transfer" now starts a 2-day negotiation window.
--
-- When the host reports a booking's transfer as not found, reject_payment()
-- already opens the temporary dispute chat (041/042). Until now that chat had
-- no deadline. It now has exactly two days, counted from the moment the host
-- reported it. If nothing is settled by then (host hasn't confirmed the
-- payment and nobody escalated to banbe), the ticket goes back to inventory
-- and the temporary chat closes automatically.
--
-- "Settled" needs no new code: confirming the payment moves payment_state to
-- 'confirmed', escalating moves it to 'disputed' — both leave the only states
-- the sweep below looks at ('pending_verification', 'holding').
--
-- The clock starts at the FIRST report and is never extended by repeated
-- reports or by the goer re-uploading proof.

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS not_found_at timestamptz;
ALTER TABLE public.dispute_threads
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

CREATE INDEX IF NOT EXISTS dispute_threads_expires_idx
  ON public.dispute_threads (expires_at)
  WHERE resolved_at IS NULL AND expires_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.reject_payment(
  p_booking uuid, p_reason text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_authorized boolean;
  v_thread_id uuid;
  v_first boolean;
  v_org_owner uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_b.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) INTO v_authorized;
  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_b.payment_state NOT IN ('pending_verification', 'holding') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_b.payment_state);
  END IF;

  v_first := v_b.not_found_at IS NULL;
  UPDATE bookings SET
    dispute_reason = left(trim(COALESCE(p_reason, '')), 400),
    not_found_at = COALESCE(not_found_at, now())
  WHERE id = p_booking
  RETURNING * INTO v_b;

  PERFORM log_payment_event(
    p_booking, 'T2_flagged_not_found', v_b.payment_state, v_b.payment_state,
    auth.uid(), 'organizer', NULL, NULL,
    jsonb_build_object('reason', v_b.dispute_reason, 'transaction_id', v_b.transaction_id,
                       'proof_path', v_b.proof_path, 'payment_ref', v_b.payment_ref,
                       'window_ends_at', v_b.not_found_at + interval '2 days')
  );

  INSERT INTO dispute_threads (booking_id, event_id, guest_id, organizer_id, expires_at)
  VALUES (v_b.id, v_b.event_id, v_b.user_id,
          (SELECT organizer_id FROM events WHERE id = v_b.event_id),
          v_b.not_found_at + interval '2 days')
  ON CONFLICT (booking_id) DO UPDATE SET
    guest_id = EXCLUDED.guest_id,
    organizer_id = EXCLUDED.organizer_id,
    expires_at = COALESCE(dispute_threads.expires_at, EXCLUDED.expires_at)
  WHERE dispute_threads.resolved_at IS NULL;

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Người tổ chức chưa tìm thấy khoản chuyển khoản này'
            || COALESCE(': ' || NULLIF(v_b.dispute_reason, ''), '')
            || '. Hai bên có 2 ngày để trao đổi và thống nhất; sau đó vé sẽ được trả lại kho nếu chưa xác nhận.'
            || ' / The host could not find this transfer. You have 2 days to sort it out in the chat;'
            || ' after that the ticket returns to inventory.',
            'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_b.user_id, 'payment_needs_info', 'Cần thêm thông tin chuyển khoản',
          'Người tổ chức chưa tìm thấy khoản chuyển khoản của bạn. Bạn có 2 ngày để trao đổi trong cuộc trò chuyện tạm thời, sau đó vé sẽ được trả lại.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                             'reason', v_b.dispute_reason,
                             'window_ends_at', v_b.not_found_at + interval '2 days'));

  -- The host gets a record too (first report only): the chat is theirs as well.
  IF v_first THEN
    SELECT COALESCE(o.owner_id, o.user_id) INTO v_org_owner
      FROM events e JOIN organizers o ON o.id = e.organizer_id
     WHERE e.id = v_b.event_id;
    IF v_org_owner IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (v_org_owner, 'payment_needs_info', 'Đã mở trò chuyện tạm thời với khách',
              'Bạn có 2 ngày để cùng khách thống nhất khoản chuyển khoản; sau đó vé sẽ được trả lại kho.',
              jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                                 'window_ends_at', v_b.not_found_at + interval '2 days'));
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'state', v_b.payment_state,
                            'window_ends_at', v_b.not_found_at + interval '2 days');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.reject_payment(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reject_payment(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- expire_not_found_bookings(): after 2 days with no confirmation and no
-- escalation, release the seat and close the temporary chat. Each row stands
-- on its own (same guarantee as expire_stale_holds()).
-- The chat gets the usual soft-delete: read-only now, purged by the existing
-- purge_resolved_dispute_threads() cron after 72h.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_not_found_bookings()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row record;
  v_from payment_state;
  v_thread_id uuid;
  v_org_owner uuid;
  v_count int := 0;
BEGIN
  FOR v_row IN
    SELECT b.id, b.user_id, b.event_id, b.payment_ref, b.payment_state, b.not_found_at
    FROM bookings b
    WHERE b.payment_state IN ('pending_verification', 'holding')
      AND b.not_found_at IS NOT NULL
      AND b.not_found_at + interval '2 days' < now()
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      v_from := v_row.payment_state;


      UPDATE dispute_threads SET
        resolved_at = now(),
        resolution_kind = 'cancelled',
        resolution_note = 'Auto-closed: no agreement within 2 days',
        purge_after = now() + interval '72 hours'
      WHERE booking_id = v_row.id AND resolved_at IS NULL;

      UPDATE bookings SET
        payment_state = 'expired', status = 'expired', verify_due_at = NULL
      WHERE id = v_row.id;

      PERFORM log_payment_event(v_row.id, 'not_found_window_expired', v_from, 'expired',
                                NULL, 'system', NULL, NULL,
                                jsonb_build_object('payment_ref', v_row.payment_ref,
                                                   'reported_at', v_row.not_found_at));

      SELECT id INTO v_thread_id FROM threads
       WHERE event_id = v_row.event_id AND guest_id = v_row.user_id;
      IF v_thread_id IS NOT NULL THEN
        INSERT INTO messages (thread_id, sender_id, body, kind)
        VALUES (v_thread_id, NULL,
                'Hết 2 ngày mà chưa thống nhất được. Vé đã được trả lại kho và cuộc trò chuyện tạm thời đã đóng.'
                || ' / No agreement within 2 days. The ticket has been returned to inventory and the temporary chat is closed.',
                'system');
      END IF;

      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (v_row.user_id, 'not_found_expired', 'Vé đã được trả lại',
              'Hết 2 ngày mà người tổ chức chưa xác nhận khoản chuyển khoản. Vé đã được trả lại kho.',
              jsonb_build_object('booking_id', v_row.id, 'event_id', v_row.event_id));

      SELECT COALESCE(o.owner_id, o.user_id) INTO v_org_owner
        FROM events e JOIN organizers o ON o.id = e.organizer_id
       WHERE e.id = v_row.event_id;
      IF v_org_owner IS NOT NULL THEN
        INSERT INTO notifications (recipient_id, kind, title, body, data)
        VALUES (v_org_owner, 'not_found_expired', 'Vé đã được trả lại kho',
                'Hết 2 ngày mà khoản chuyển khoản chưa được xác nhận. Vé đã được trả lại kho và cuộc trò chuyện tạm thời đã đóng.',
                jsonb_build_object('booking_id', v_row.id, 'event_id', v_row.event_id));
      END IF;

      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'expire_not_found_bookings: booking % failed: %', v_row.id, SQLERRM;
    END;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.expire_not_found_bookings() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('bb_expire_not_found_bookings', '*/5 * * * *',
                     $cmd$ SELECT public.expire_not_found_bookings(); $cmd$);

-- ---------------------------------------------------------------------------
-- get_my_dispute_chats(): two ADDITIVE columns so a client can tell a
-- "not found, 2-day window" chat (booking still pending_verification/holding)
-- from one escalated to banbe, and show the deadline. Body is otherwise
-- migration 138's, unchanged. DROP+CREATE because RETURNS TABLE can't change
-- under CREATE OR REPLACE (nothing depends on this function).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_my_dispute_chats();
CREATE FUNCTION public.get_my_dispute_chats()
RETURNS TABLE (
  thread_id uuid,
  kind text,
  booking_id uuid,
  refund_claim_id uuid,
  event_id text,
  event_key text,
  event_name text,
  other_name text,
  other_avatar_url text,
  amount_vnd int,
  claim_status refund_status,
  disputed_at timestamptz,
  resolved_at timestamptz,
  purge_after timestamptz,
  last_message_at timestamptz,
  last_message_body text,
  message_count int,
  viewer_role text,
  source_booking_id uuid,
  conversation_thread_id uuid,
  dispute_closed_at timestamptz,
  dispute_closed_by_role text,
  expires_at timestamptz,
  booking_payment_state text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  PERFORM public.goc_stamp_refund_dispute_chat_conclusions();

  RETURN QUERY
  SELECT
    t.id,
    t.kind,
    t.booking_id,
    t.refund_claim_id,
    t.event_id,
    e.key,
    e.name,
    CASE
      WHEN t.guest_id = auth.uid() THEN o.name
      WHEN t.guest_id IS NULL THEN o.name
      ELSE COALESCE(NULLIF(p.display_name, ''), 'banbe')
    END,
    CASE WHEN t.guest_id = auth.uid() THEN NULL ELSE p.avatar_url END,
    rc.amount_vnd,
    rc.status,
    rc.disputed_at,
    t.resolved_at,
    t.purge_after,
    last_msg.created_at,
    last_msg.body,
    COALESCE(msg_count.n, 0)::int,
    CASE WHEN t.guest_id = auth.uid() THEN 'guest' ELSE 'organizer' END,
    COALESCE(rc.booking_id, rc.reservation_id),
    conv.id,
    CASE WHEN t.resolved_at IS NOT NULL THEN COALESCE(t.closed_at, rc.dispute_closed_at, t.resolved_at) END,
    CASE WHEN t.resolved_at IS NOT NULL THEN COALESCE(t.closed_by_role, rc.dispute_closed_by_role) END,
    t.expires_at,
    pb.payment_state::text
  FROM dispute_threads t
  LEFT JOIN events e ON e.id = t.event_id
  LEFT JOIN organizers o ON o.id = t.organizer_id
  LEFT JOIN profiles p ON p.id = t.guest_id
  LEFT JOIN refund_claims rc ON rc.id = t.refund_claim_id
  LEFT JOIN bookings pb ON pb.id = t.booking_id
  LEFT JOIN threads conv ON conv.event_id = t.event_id AND conv.guest_id = t.guest_id
  LEFT JOIN LATERAL (
    SELECT dm.created_at, dm.body
    FROM dispute_messages dm
    WHERE dm.dispute_thread_id = t.id
    ORDER BY dm.created_at DESC
    LIMIT 1
  ) last_msg ON true
  LEFT JOIN LATERAL (
    SELECT count(*) AS n FROM dispute_messages dm WHERE dm.dispute_thread_id = t.id
  ) msg_count ON true
  WHERE NOT (t.guest_deleted_at IS NOT NULL AND t.guest_id = auth.uid())
    AND (t.resolved_at IS NULL
         OR (t.refund_claim_id IS NOT NULL AND t.purge_after IS NOT NULL AND t.purge_after > now()))
    AND (
      t.guest_id = auth.uid()
      OR EXISTS (SELECT 1 FROM organizers oo WHERE oo.id = t.organizer_id
                 AND (oo.owner_id = auth.uid() OR oo.user_id = auth.uid()))
      OR public.is_platform_admin()
    )
  ORDER BY (t.resolved_at IS NOT NULL), last_msg.created_at DESC NULLS LAST, t.created_at DESC;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_my_dispute_chats() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_dispute_chats() TO authenticated;

-- ---------------------------------------------------------------------------
-- A payment dispute chat must not outlive the thing it is about. Before this,
-- confirming the payment (or any other exit from the unsettled states) left
-- dispute_threads.resolved_at NULL forever, so the chat — and any "dispute in
-- progress" marker built on it — stayed up after nothing was left to dispute.
-- A booking leaving pending_verification/holding closes its open thread.
-- ('disputed' is excluded: resolve_dispute() closes its own, with the note.)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_payment_dispute_thread_on_settle()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE dispute_threads SET
    resolved_at = now(),
    resolution_kind = CASE WHEN NEW.payment_state::text = 'confirmed' THEN 'ticket_issued' ELSE 'cancelled' END,
    resolution_note = 'Auto-closed: booking settled',
    purge_after = now() + interval '72 hours'
  WHERE booking_id = NEW.id AND kind = 'payment' AND resolved_at IS NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bookings_close_payment_dispute_thread ON public.bookings;
CREATE TRIGGER bookings_close_payment_dispute_thread
AFTER UPDATE OF payment_state ON public.bookings
FOR EACH ROW
WHEN (OLD.payment_state::text IN ('pending_verification', 'holding')
      AND NEW.payment_state::text IN ('confirmed', 'expired', 'cancelled'))
EXECUTE FUNCTION public.close_payment_dispute_thread_on_settle();

-- Backfill: threads already stranded open by a settled booking.
UPDATE dispute_threads t SET
  resolved_at = now(),
  resolution_kind = CASE WHEN b.payment_state::text = 'confirmed' THEN 'ticket_issued' ELSE 'cancelled' END,
  resolution_note = 'Auto-closed: booking settled',
  purge_after = now() + interval '72 hours'
FROM bookings b
WHERE b.id = t.booking_id AND t.kind = 'payment' AND t.resolved_at IS NULL
  AND b.payment_state::text NOT IN ('pending_verification', 'holding', 'disputed');
