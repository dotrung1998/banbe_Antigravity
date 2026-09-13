-- Migration: where an organizer's payment alerts are actually delivered.
--
-- Kept apart from 026 (the state machine) on purpose: 026 decides WHEN an
-- alert is owed and writes it to alert_outbox; this decides WHERE it goes.
-- The two change for entirely different reasons — one when the payment rules
-- change, the other when an organizer swaps phone or moves their team to a
-- different group chat.

ALTER TABLE public.organizers
  -- The management group chat. Telegram chat ids for groups are negative,
  -- so this is text rather than bigint to avoid anyone "helpfully" fixing
  -- the sign later.
  ADD COLUMN IF NOT EXISTS telegram_chat_id text NOT NULL DEFAULT '',
  -- For the T+30 urgent escalation.
  ADD COLUMN IF NOT EXISTS alert_phone text NOT NULL DEFAULT '',
  -- Organizers running a slow door can widen their own SLA; the escalation
  -- sweep in 026 uses this when deciding how long "unanswered" means.
  ADD COLUMN IF NOT EXISTS verify_sla_minutes int NOT NULL DEFAULT 15;

-- ---------------------------------------------------------------------------
-- Everything the alert dispatcher needs for one queued alert, in one row, so
-- api/cron/escalate-verifications.js does not have to fan out four joins per
-- item and then decide what to say.
--
-- SECURITY INVOKER, like the other payment views: it reads bookings, and a
-- definer view over bookings hands every row to any caller regardless of RLS.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_alert_queue
WITH (security_invoker = true) AS
SELECT
  a.id AS alert_id, a.kind, a.channel, a.attempts, a.created_at,
  b.id AS booking_id, b.payment_ref, b.total_vnd, b.qty,
  b.transaction_id, b.proof_path, b.proof_submitted_at, b.verify_due_at,
  b.payment_state,
  e.id AS event_id, e.name AS event_name,
  o.id AS organizer_id, o.name AS organizer_name,
  o.telegram_chat_id, o.alert_phone,
  p.display_name AS guest_name
FROM public.alert_outbox a
JOIN public.bookings b ON b.id = a.booking_id
JOIN public.events e ON e.id = b.event_id
LEFT JOIN public.organizers o ON o.id = e.organizer_id
LEFT JOIN public.profiles p ON p.id = b.user_id
WHERE a.sent_at IS NULL;

-- ---------------------------------------------------------------------------
-- save_organizer_alert_routing() — an organizer configuring their own chat.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_organizer_alert_routing(
  p_organizer text,
  p_telegram_chat_id text DEFAULT '',
  p_alert_phone text DEFAULT '',
  p_sla_minutes int DEFAULT 15
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM organizers o
    WHERE o.id = p_organizer AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  UPDATE organizers SET
    telegram_chat_id = left(trim(COALESCE(p_telegram_chat_id, '')), 40),
    alert_phone = left(trim(COALESCE(p_alert_phone, '')), 40),
    -- Clamped: a 0-minute SLA would fire a reminder and an escalation on the
    -- same sweep, and a 24h one is not an SLA.
    verify_sla_minutes = LEAST(GREATEST(COALESCE(p_sla_minutes, 15), 5), 120)
  WHERE id = p_organizer;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.save_organizer_alert_routing(text, text, text, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_organizer_alert_routing(text, text, text, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- verify_payment_from_bot() — the [Approve] / [Reject] inline buttons.
--
-- A Telegram chat id is NOT an authenticated banbe user, so this cannot go
-- through auth.uid() at all. Authorisation is instead: the chat this callback
-- came from must be the chat that organizer registered above. That check
-- lives here, in the database, next to the state change it guards — not in
-- the webhook handler, where it would be one forgotten early-return away
-- from letting any chat approve any booking.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verify_payment_from_bot(
  p_booking uuid, p_chat_id text, p_approve boolean, p_reason text DEFAULT '',
  p_actor_label text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_chat text;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT o.telegram_chat_id INTO v_chat
  FROM events e JOIN organizers o ON o.id = e.organizer_id
  WHERE e.id = v_b.event_id;

  IF COALESCE(v_chat, '') = '' OR v_chat IS DISTINCT FROM trim(COALESCE(p_chat_id, '')) THEN
    RETURN jsonb_build_object('success', false, 'error', 'CHAT_NOT_AUTHORIZED');
  END IF;

  IF p_approve THEN
    RETURN verify_payment(p_booking, 'telegram', 'system',
                          jsonb_build_object('chat_id', p_chat_id, 'operator', p_actor_label));
  END IF;

  -- Rejection mirrors reject_payment(), but that one authorises via
  -- auth.uid() which a bot callback does not have. Same destination state,
  -- same audit shape, same guarantee that the seat stays locked.
  IF v_b.payment_state NOT IN ('pending_verification', 'holding') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE',
                              'state', v_b.payment_state);
  END IF;

  UPDATE bookings SET
    payment_state = 'disputed', disputed_at = now(),
    dispute_reason = left(trim(COALESCE(p_reason, 'Rejected from Telegram')), 400),
    verify_due_at = NULL
  WHERE id = p_booking;

  PERFORM log_payment_event(p_booking, 'T3_rejected', v_b.payment_state, 'disputed',
                            NULL, 'organizer', NULL, NULL,
                            jsonb_build_object('via', 'telegram', 'chat_id', p_chat_id,
                                               'operator', p_actor_label, 'reason', p_reason));

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_b.user_id, 'payment_disputed', 'Thanh toán đang được xem xét',
          'Người tổ chức chưa xác nhận được khoản chuyển khoản của bạn. Chỗ vẫn được giữ trong lúc banbe xem xét.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id));

  RETURN jsonb_build_object('success', true, 'state', 'disputed');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.verify_payment_from_bot(uuid, text, boolean, text, text)
  FROM anon, authenticated;

GRANT SELECT ON public.v_alert_queue TO authenticated;
