-- 213 — close the verify_payment hole and remove Telegram payment confirmation (owner decisions 2026-11-04; the
-- Casso/PayOS bank feed was first removed too, then restored the same day at the owner's request).
--
-- FOUND WHILE PLANNING 9b. verify_payment() (026) skipped its organizer check whenever p_actor_kind was 'webhook' or
-- 'system', and EXECUTE was granted to every signed-in user, so ANY account could mark ANY guest's payment confirmed
-- (ticket issued, receipt raised) without paying. Proven on the throwaway stack (note 76, phase 9b). Migration 183 locked
-- the bank matcher and the Telegram function to the service role but never covered verify_payment itself.
--
-- This migration:
--   * redefines verify_payment WITHOUT the open bypass (026's body otherwise): every caller must be an organizer account
--     of the event or an admin, EXCEPT the Casso/PayOS bank feed, which may skip the check only as p_actor_kind
--     'webhook' with the service-role key (auth.role() = 'service_role', from the verified JWT),
--   * keeps record_bank_transaction (bank feed, service-role only since 183) and api/payment-webhook.js,
--   * drops verify_payment_from_bot (Telegram buttons), save_organizer_alert_routing and the v_alert_queue view
--     (Telegram routing and the alert drain),
--   * unschedules bb_sweep_verification_slas, which only queued Telegram reminders/escalations into alert_outbox.
-- Kept on purpose (history, no behaviour): tables payment_webhook_events and alert_outbox, organizers.telegram_chat_id /
-- alert_phone columns, the sweep function itself. The Telegram app code (api/telegram-webhook.js, api/_lib/alerts.js,
-- the escalate-verifications cron) is removed; api/payment-webhook.js (Casso/PayOS) is kept.
--
-- Production: NOT applied by this pass. Rollback: supabase/rollbacks/20261231000213_213_revert_remove_auto_confirmation.sql
-- (restores 026's verify_payment WITH the hole; emergency only, and only together with the code).

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
  v_bank boolean := false;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  -- 213: p_actor_kind 'webhook'/'system' used to skip this check while EXECUTE was granted to every signed-in user, so
  -- anyone could confirm anyone's payment. Now the ONLY caller that skips it is the Casso/PayOS bank feed
  -- (api/payment-webhook.js -> record_bank_transaction), and only with the service-role key: auth.role() comes from the
  -- verified JWT, which no signed-in user can forge. Telegram ('system') is gone.
  v_bank := p_actor_kind = 'webhook' AND coalesce(auth.role(), '') = 'service_role';
  IF v_bank THEN
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

  -- Idempotent by design: two people (or two taps) may approve the same booking.
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
    verified_by = auth.uid(),
    -- The compatibility bridge: every existing ticket gate reads these.
    paid_marked_at = COALESCE(paid_marked_at, now()),
    paid_method = CASE WHEN COALESCE(paid_method, '') = ''
                       THEN left(COALESCE(p_via, 'bank'), 40) ELSE paid_method END,
    paid_marked_by = COALESCE(paid_marked_by,
                              auth.uid()),
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
    auth.uid(),
    CASE WHEN v_bank THEN 'webhook' WHEN p_actor_kind IN ('webhook', 'system') THEN 'organizer' ELSE p_actor_kind END, NULL, NULL,
    COALESCE(p_meta, '{}'::jsonb)
      || jsonb_build_object('via', p_via, 'receipt_number', v_receipt_number,
                            'amount_vnd', v_b.total_vnd, 'payment_ref', v_b.payment_ref)
  );

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id,
            auth.uid(),
            'Đã xác nhận thanh toán ▪︎ '
            || CASE WHEN v_bank THEN 'tự động đối soát qua ngân hàng' ELSE 'người tổ chức xác nhận' END
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

REVOKE EXECUTE ON FUNCTION public.verify_payment(uuid, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_payment(uuid, text, text, jsonb) TO authenticated;

DROP FUNCTION IF EXISTS public.verify_payment_from_bot(uuid, text, boolean, text, text);
-- record_bank_transaction (026, Casso/PayOS bank feed) is KEPT (owner, 2026-11-04): it stays service-role only (183) and
-- its verify_payment(.., 'webhook') call is the one allowed skip above.
DROP VIEW IF EXISTS public.v_alert_queue;
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'save_organizer_alert_routing'
  LOOP EXECUTE format('DROP FUNCTION IF EXISTS %s', r.sig); END LOOP;
END $$;
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'bb_sweep_verification_slas';
