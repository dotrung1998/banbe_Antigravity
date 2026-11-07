-- Migration 137: goer confirms receipt from inside a dispute, and a dispute
-- closes by itself after 7 days with a reminder on day 6.
--
-- Additive on 129 to 136.
--   1. confirm_refund_received() now also accepts a 'disputed' claim. The host
--      already marked it sent before the dispute, so nobody has to mark it sent
--      again: the goer confirms receipt, and that is what unlocks "Close dispute"
--      (migration 135).
--   2. refund_claims.dispute_autoclose_reminded_at: set once, when the day 6
--      reminder has been sent, so it is never sent twice.
--   3. goc_stamp_refund_dispute_chat_conclusions() (cron, every 15 minutes, and
--      lazily from get_my_dispute_chats) additionally:
--        * sends the reminder to the goer and the organizer once a still open
--          dispute reaches 6 days (and is not yet 7);
--        * auto-closes a dispute 7 days after it was opened if nobody acted:
--          the chat becomes read only with the usual 7 day retention,
--          dispute_closed_by_role = 'auto', a system line is added to the
--          transcript and both sides are notified.
--      Auto-close NEVER touches refund_claims.status or the amount: it ends the
--      chat, it does not decide the money.

ALTER TABLE public.refund_claims
  ADD COLUMN IF NOT EXISTS dispute_autoclose_reminded_at timestamptz;

CREATE OR REPLACE FUNCTION public.confirm_refund_received(p_claim_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_recipient uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  IF NOT FOUND OR v_booking.user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_claim.status = 'guest_confirmed' THEN
    RETURN jsonb_build_object('success', true, 'status', v_claim.status, 'already', true);
  END IF;
  -- 137: a goer whose dispute is still open can say the money DID arrive
  -- ("disputed" -> "guest_confirmed"), which is what unlocks closing the dispute.
  IF v_claim.status NOT IN ('host_marked_sent', 'disputed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;

  UPDATE refund_claims
  SET status = 'guest_confirmed',
      guest_confirmed_at = now()
  WHERE id = p_claim_id;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;
  SELECT * INTO v_org FROM organizers WHERE id = v_event.organizer_id;
  v_recipient := COALESCE(v_org.owner_id, v_org.user_id);

  IF v_recipient IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_recipient, 'refund_confirmed',
      'Khách đã xác nhận nhận được hoàn tiền',
      'Khách xác nhận đã nhận ' || replace(to_char(v_claim.amount_vnd, 'FM999G999G999'), ',', '.')
        || '₫ cho ' || COALESCE(v_event.name, 'sự kiện') || '.',
      jsonb_build_object('claim_id', v_claim.id, 'booking_id', v_booking.id, 'event_id', v_event.id, 'amount_vnd', v_claim.amount_vnd)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'guest_confirmed');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.confirm_refund_received(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.confirm_refund_received(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.goc_stamp_refund_dispute_chat_conclusions()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int := 0;
  v_n int;
  r record;
BEGIN
  -- A. Day 6 reminder (once).
  FOR r IN
    SELECT rc.id AS claim_id, rc.amount_vnd, rc.disputed_at, t.id AS thread_id, t.guest_id, t.organizer_id,
           b.id AS booking_id, e.id AS event_id, e.name AS event_name
    FROM refund_claims rc
    JOIN dispute_threads t ON t.refund_claim_id = rc.id AND t.resolved_at IS NULL
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    WHERE rc.status::text = 'disputed'
      AND rc.dispute_closed_at IS NULL
      AND rc.dispute_autoclose_reminded_at IS NULL
      AND rc.disputed_at <= now() - interval '6 days'
      AND rc.disputed_at > now() - interval '7 days'
    FOR UPDATE OF rc
  LOOP
    UPDATE refund_claims SET dispute_autoclose_reminded_at = now() WHERE id = r.claim_id;
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    SELECT x.recipient, 'refund_dispute_autoclose_soon',
           'Tranh chấp hoàn tiền sắp tự đóng',
           'Tranh chấp khoản hoàn cho ' || COALESCE(r.event_name, 'sự kiện')
             || ' sẽ tự đóng sau 24 giờ nếu không có phản hồi. Khoản hoàn không thay đổi.',
           jsonb_build_object('claim_id', r.claim_id, 'booking_id', r.booking_id, 'event_id', r.event_id,
                              'dispute_thread_id', r.thread_id)
    FROM (
      SELECT r.guest_id AS recipient
      UNION SELECT o.owner_id FROM organizers o WHERE o.id = r.organizer_id
      UNION SELECT o.user_id FROM organizers o WHERE o.id = r.organizer_id
    ) x WHERE x.recipient IS NOT NULL;
  END LOOP;

  -- B. Auto-close after 7 days without action.
  FOR r IN
    SELECT rc.id AS claim_id, rc.amount_vnd, t.id AS thread_id, t.guest_id, t.organizer_id,
           b.id AS booking_id, e.id AS event_id, e.name AS event_name
    FROM refund_claims rc
    JOIN dispute_threads t ON t.refund_claim_id = rc.id AND t.resolved_at IS NULL
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    WHERE rc.status::text = 'disputed'
      AND rc.dispute_closed_at IS NULL
      AND rc.disputed_at <= now() - interval '7 days'
    FOR UPDATE OF rc
  LOOP
    UPDATE dispute_threads
    SET resolved_at = now(), purge_after = now() + interval '7 days',
        resolution_kind = 'refund_auto_closed'
    WHERE id = r.thread_id;
    UPDATE refund_claims SET dispute_closed_at = now(), dispute_closed_by_role = 'auto' WHERE id = r.claim_id;
    INSERT INTO dispute_messages (dispute_thread_id, sender_role, body)
    VALUES (r.thread_id, 'system', 'Dispute closed automatically after 7 days without action.');
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    SELECT x.recipient, 'refund_dispute_closed',
           'Tranh chấp hoàn tiền đã tự đóng',
           'Tranh chấp khoản hoàn cho ' || COALESCE(r.event_name, 'sự kiện')
             || ' đã tự đóng sau 7 ngày. Bản ghi vẫn đọc được trong 7 ngày.',
           jsonb_build_object('claim_id', r.claim_id, 'booking_id', r.booking_id, 'event_id', r.event_id,
                              'amount_vnd', r.amount_vnd, 'dispute_thread_id', r.thread_id)
    FROM (
      SELECT r.guest_id AS recipient
      UNION SELECT o.owner_id FROM organizers o WHERE o.id = r.organizer_id
      UNION SELECT o.user_id FROM organizers o WHERE o.id = r.organizer_id
    ) x WHERE x.recipient IS NOT NULL;
    v_count := v_count + 1;
  END LOOP;

  -- C. Conclusions (migration 135 rules, unchanged).
  WITH closed AS (
    UPDATE dispute_threads t
    SET resolved_at = COALESCE(t.resolved_at, now()),
        purge_after = COALESCE(t.purge_after, now() + interval '7 days'),
        resolution_kind = COALESCE(t.resolution_kind, 'refund_settled')
    WHERE t.refund_claim_id IS NOT NULL
      AND t.resolved_at IS NULL
      AND EXISTS (
        SELECT 1 FROM refund_claims rc
        WHERE rc.id = t.refund_claim_id
          AND (
            rc.dispute_closed_at IS NOT NULL
            OR rc.status::text = 'waived'
            OR (rc.status::text = 'guest_confirmed'
                AND COALESCE(rc.guest_confirmed_at, rc.created_at) < now() - interval '7 days')
          )
      )
    RETURNING t.id
  )
  SELECT count(*) INTO v_n FROM closed;
  RETURN v_count + v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.goc_stamp_refund_dispute_chat_conclusions() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.goc_stamp_refund_dispute_chat_conclusions() FROM anon;
REVOKE EXECUTE ON FUNCTION public.goc_stamp_refund_dispute_chat_conclusions() FROM authenticated;

-- 4. The host refund queue also reports dispute_closed_at, so a closed dispute
--    drops out of the host's "Things to do" instead of lingering. Same body as
--    the previous definition plus that one key.
CREATE OR REPLACE FUNCTION public.get_host_refund_claims(p_event_id text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin boolean;
  v_is_host boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT EXISTS(SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin') INTO v_is_admin;

  IF p_event_id IS NOT NULL AND NOT v_is_admin THEN
    SELECT EXISTS (
      SELECT 1 FROM events e
      JOIN organizers o ON o.id = e.organizer_id
      WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    ) INTO v_is_host;
    IF NOT v_is_host THEN
      RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
    END IF;
  END IF;

  -- A caller with no organizer at all (and not admin) gets an empty queue,
  -- not an error — mirrors the old client's own "no orgs -> empty" gate,
  -- just enforced here instead of trusted from the client.
  IF p_event_id IS NULL AND NOT v_is_admin
     AND NOT EXISTS (SELECT 1 FROM organizers o WHERE o.owner_id = auth.uid() OR o.user_id = auth.uid()) THEN
    RETURN jsonb_build_object('success', true, 'claims', '[]'::jsonb);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'claims', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', rc.id,
        'booking_id', b.id,
        'amount_vnd', rc.amount_vnd,
        'reason', rc.reason,
        'status', rc.status,
        'host_marked_at', rc.host_marked_at,
        'guest_confirmed_at', rc.guest_confirmed_at,
        'disputed_at', rc.disputed_at,
        'host_response_due_at', rc.host_response_due_at,
        'refund_due_at', rc.refund_due_at,
        'transfer_reference', rc.transfer_reference,
        'selected_destination_id', rc.selected_destination_id,
        'recipient_snapshot', rc.recipient_snapshot,
        'note', rc.note,
        'created_at', rc.created_at,
        'guest_user_id', b.user_id,
        'guest_name', coalesce(p.display_name, ''),
        'event_id', e.id,
        'event_name', e.name,
        'dispute_closed_at', rc.dispute_closed_at
      ) ORDER BY rc.created_at ASC), '[]'::jsonb)
      -- INNER JOINs only: a row can only ever come back if claim -> booking
      -- -> event -> an organizer the caller owns (or admin) all resolve.
      -- Self-booking (guest == host, same auth.uid() on both sides) is
      -- NOT excluded here, by design — ownership is checked on the
      -- ORGANIZER, never on whether the claim's own guest_user_id differs
      -- from the caller; a host who booked and cancelled their own event
      -- still owes themselves the same real refund.
      FROM refund_claims rc
      JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
      JOIN events e ON e.id = b.event_id
      JOIN organizers o ON o.id = e.organizer_id
      LEFT JOIN profiles p ON p.id = b.user_id
      WHERE (p_event_id IS NULL OR e.id = p_event_id)
        AND (v_is_admin OR o.owner_id = auth.uid() OR o.user_id = auth.uid())
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_host_refund_claims(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_host_refund_claims(text) TO authenticated;
