-- Revert 213 — EMERGENCY ONLY. Restores verify_payment exactly as 026 defined it (WITH the webhook/system bypass that lets
-- any signed-in user confirm any payment), recreates the Telegram and bank-feed functions and the alert queue view, and
-- re-schedules the SLA sweep. Only meaningful together with restoring api/payment-webhook.js, api/telegram-webhook.js,
-- api/_lib/alerts.js and the escalate-verifications cron. Server-only ACLs follow 183.

CREATE OR REPLACE FUNCTION public.verify_payment(
  p_booking uuid,
  p_via text DEFAULT 'organizer',
  p_actor_kind text DEFAULT 'organizer',
  p_meta jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_from payment_state;
  v_authorized boolean;
  v_thread_id uuid;
  v_receipt payment_documents%ROWTYPE;
  v_receipt_number text;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  IF p_actor_kind IN ('webhook', 'system') THEN
    v_authorized := true;
  ELSE
    IF auth.uid() IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
    END IF;
    SELECT EXISTS(
      SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
      WHERE e.id = v_b.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    ) OR EXISTS (
      SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
    ) INTO v_authorized;
  END IF;

  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  v_from := v_b.payment_state;

  -- Idempotent by design: the webhook fires at least once, and an organizer
  -- can easily tap approve on a booking a webhook just settled.
  IF v_from = 'confirmed' THEN
    RETURN jsonb_build_object('success', true, 'state', 'confirmed', 'noop', true);
  END IF;
  IF v_from NOT IN ('holding', 'pending_verification', 'disputed', 'expired') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_from);
  END IF;

  UPDATE bookings SET
    payment_state = 'confirmed',
    status = CASE WHEN status IN ('attended', 'no_show') THEN status
                  ELSE 'confirmed'::booking_status END,
    verified_at = now(),
    verified_via = left(COALESCE(p_via, 'organizer'), 40),
    verified_by = CASE WHEN p_actor_kind IN ('webhook', 'system') THEN NULL ELSE auth.uid() END,
    -- The compatibility bridge: every existing ticket gate reads these.
    paid_marked_at = COALESCE(paid_marked_at, now()),
    paid_method = CASE WHEN COALESCE(paid_method, '') = ''
                       THEN left(COALESCE(p_via, 'bank'), 40) ELSE paid_method END,
    paid_marked_by = COALESCE(paid_marked_by,
                              CASE WHEN p_actor_kind IN ('webhook','system') THEN NULL ELSE auth.uid() END),
    confirmed_at = COALESCE(confirmed_at, now()),
    verify_due_at = NULL
  WHERE id = p_booking
  RETURNING * INTO v_b;

  BEGIN
    PERFORM ensure_payment_document(v_b.id, 'invoice');
    v_receipt := ensure_payment_document(v_b.id, 'receipt');
    v_receipt_number := v_receipt.number;
  EXCEPTION WHEN OTHERS THEN
    v_receipt_number := NULL;
  END;

  -- T3: verification, naming which route settled it.
  PERFORM log_payment_event(
    p_booking, 'T3_verified', v_from, 'confirmed',
    CASE WHEN p_actor_kind IN ('webhook','system') THEN NULL ELSE auth.uid() END,
    p_actor_kind, NULL, NULL,
    COALESCE(p_meta, '{}'::jsonb)
      || jsonb_build_object('via', p_via, 'receipt_number', v_receipt_number,
                            'amount_vnd', v_b.total_vnd, 'payment_ref', v_b.payment_ref)
  );

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id,
            CASE WHEN p_actor_kind IN ('webhook','system') THEN NULL ELSE auth.uid() END,
            'Đã xác nhận thanh toán ▪︎ '
            || CASE WHEN p_via = 'webhook' THEN 'tự động đối soát qua ngân hàng'
                    ELSE 'người tổ chức xác nhận' END
            || COALESCE('. Biên nhận ' || v_receipt_number, '') || '.',
            'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_b.user_id, 'payment_confirmed', 'Đã nhận thanh toán',
          'Thanh toán của bạn đã được xác nhận. Vé và biên nhận đã sẵn sàng.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                             'receipt_number', v_receipt_number, 'via', p_via));

  RETURN jsonb_build_object('success', true, 'state', 'confirmed',
                            'receipt_number', v_receipt_number, 'via', p_via);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.verify_payment(uuid, text, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.verify_payment(uuid, text, text, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_bank_transaction(
  p_provider text,
  p_external_id text,
  p_amount_vnd bigint,
  p_memo text,
  p_raw jsonb DEFAULT '{}'::jsonb,
  p_signature_ok boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_ref text;
  v_status text;
  v_result jsonb;
  v_webhook_id uuid;
BEGIN
  IF COALESCE(trim(p_external_id), '') = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'EXTERNAL_ID_REQUIRED');
  END IF;

  -- Idempotency gate. The unique index on (provider, external_id) is what
  -- actually enforces it; ON CONFLICT turns a retry into a no-op answer
  -- rather than an error the provider would then retry again.
  INSERT INTO payment_webhook_events (provider, external_id, signature_ok, amount_vnd, memo, raw)
  VALUES (p_provider, trim(p_external_id), p_signature_ok, p_amount_vnd,
          left(COALESCE(p_memo, ''), 500), COALESCE(p_raw, '{}'::jsonb))
  ON CONFLICT (provider, external_id) DO NOTHING
  RETURNING id INTO v_webhook_id;

  IF v_webhook_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'match_status', 'duplicate', 'noop', true);
  END IF;

  IF NOT p_signature_ok THEN
    UPDATE payment_webhook_events SET match_status = 'no_match' WHERE id = v_webhook_id;
    RETURN jsonb_build_object('success', false, 'error', 'BAD_SIGNATURE');
  END IF;

  -- Banks mangle the description: case changes, stripped punctuation, and
  -- the payer's own name and the bank's own boilerplate wrapped around it.
  -- So find our reference inside the noise rather than expecting equality.
  SELECT (regexp_match(upper(COALESCE(p_memo, '')), 'ART[0-9]{4,8}'))[1] INTO v_ref;

  IF v_ref IS NULL THEN
    UPDATE payment_webhook_events SET match_status = 'no_match' WHERE id = v_webhook_id;
    RETURN jsonb_build_object('success', true, 'match_status', 'no_match');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE payment_ref = v_ref FOR UPDATE;
  IF NOT FOUND THEN
    UPDATE payment_webhook_events SET match_status = 'no_match', memo = COALESCE(p_memo, '')
    WHERE id = v_webhook_id;
    RETURN jsonb_build_object('success', true, 'match_status', 'no_match', 'ref', v_ref);
  END IF;

  IF v_b.payment_state = 'confirmed' THEN
    UPDATE payment_webhook_events
       SET match_status = 'already_confirmed', matched_booking_id = v_b.id
     WHERE id = v_webhook_id;
    RETURN jsonb_build_object('success', true, 'match_status', 'already_confirmed',
                              'booking_id', v_b.id);
  END IF;

  -- Underpayment is never auto-confirmed. Overpayment is matched (the money
  -- did arrive) but the difference is recorded for the organizer to settle.
  IF p_amount_vnd IS NULL OR p_amount_vnd < v_b.total_vnd THEN
    UPDATE payment_webhook_events
       SET match_status = 'amount_mismatch', matched_booking_id = v_b.id
     WHERE id = v_webhook_id;
    PERFORM log_payment_event(v_b.id, 'webhook_amount_mismatch',
                              v_b.payment_state, v_b.payment_state, NULL, 'webhook', NULL, NULL,
                              jsonb_build_object('expected_vnd', v_b.total_vnd,
                                                 'received_vnd', p_amount_vnd,
                                                 'external_id', p_external_id, 'ref', v_ref));
    RETURN jsonb_build_object('success', true, 'match_status', 'amount_mismatch',
                              'booking_id', v_b.id, 'expected_vnd', v_b.total_vnd,
                              'received_vnd', p_amount_vnd);
  END IF;

  UPDATE payment_webhook_events
     SET match_status = 'matched', matched_booking_id = v_b.id
   WHERE id = v_webhook_id;

  -- Straight to CONFIRMED with no organizer involvement — the point of the
  -- whole reconciliation path.
  v_result := verify_payment(
    v_b.id, 'webhook', 'webhook',
    jsonb_build_object('provider', p_provider, 'external_id', p_external_id,
                       'received_vnd', p_amount_vnd, 'ref', v_ref,
                       'overpaid_vnd', GREATEST(p_amount_vnd - v_b.total_vnd, 0))
  );

  RETURN jsonb_build_object('success', true, 'match_status', 'matched',
                            'booking_id', v_b.id, 'verify', v_result);
END;
$$;

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
GRANT SELECT ON public.v_alert_queue TO authenticated;

-- 183's server-only ACLs.
REVOKE EXECUTE ON FUNCTION public.record_bank_transaction(text, text, bigint, text, jsonb, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_bank_transaction(text, text, bigint, text, jsonb, boolean) TO service_role;
REVOKE EXECUTE ON FUNCTION public.verify_payment_from_bot(uuid, text, boolean, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verify_payment_from_bot(uuid, text, boolean, text, text) TO service_role;

SELECT cron.schedule('bb_sweep_verification_slas', '* * * * *', $cmd$ SELECT public.sweep_verification_slas(); $cmd$);
