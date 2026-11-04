-- 214 — Event Project Hub: delegated payment confirmation (note 76, phase 9b). Behind switch project_delegate_payments
-- (seeded OFF). Needs 212 (event_money_audit, project_delegate_ok) and 213 (verify_payment without the bypass).
--
-- Who: an ACTIVE project member who is Finance & door or has cap_money, while event_project_hub and
-- project_delegate_payments are on, the grant is live and the project is not read-only (project_delegate_ok(.., 'money')).
-- The organizer accounts and admins keep exactly what they have: verify_payment (213) and confirm_payment (060) keep every
-- original line; a delegate is only tried when that check fails, and only for a booking in pending_verification (a guest
-- said they paid). Each delegated confirmation writes ONE event_money_audit row ('confirm_payment').
--
-- NOT delegated (M3): reject_payment ("Can't find it", 149) and reject_pending_guest (059) stay with the organizer
-- accounts; so do refunds (215), cancelling and the payout account.
--
-- What a delegate may see:
--   * get_event_money_view(event): amounts, payment references and states of the event's bookings, the confirmed total,
--     and whether a transfer proof exists. No proof path, no invoice/receipt (payment-documents is never touched: M2).
--   * open_payment_proof(booking): ONLY for a booking awaiting a check (pending_verification). It writes a 'proof_open'
--     audit row and returns the object path; the new storage policy pay_proof_read_delegate lets that delegate read that
--     booking's pay-proof object for 5 minutes (proofOpenMinutes) after the audit row, so EVERY open is logged before the
--     file can be read. pay_proof_read (040) is untouched. "View only, no download" is a UI rule only (a screenshot is
--     always possible); the server parts are the per-booking scope, the checks and the audit.
--
-- LOCAL HARNESS ONLY until the owner says otherwise. Rollback: supabase/rollbacks/20261231000214_214_revert_delegated_payments.sql
-- (puts 213's verify_payment and 060's confirm_payment back verbatim).

-- ================================================================== the money view (no proofs, no documents)
CREATE OR REPLACE FUNCTION public.get_event_money_view(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.can_event_capability(p_event_id, 'money') THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  RETURN jsonb_build_object('success', true,
    'confirmed_amount', coalesce((SELECT sum(b.total_vnd) FROM bookings b WHERE b.event_id = p_event_id AND b.status IN ('confirmed', 'attended')), 0),
    'confirmed_seats', coalesce((SELECT sum(b.qty) FROM bookings b WHERE b.event_id = p_event_id AND b.status IN ('confirmed', 'attended')), 0),
    'awaiting', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'booking_id', b.id, 'name', coalesce(nullif(b.recipient_name, ''), nullif(pr.display_name, ''), '—'), 'qty', b.qty,
        'amount', b.total_vnd, 'payment_ref', b.payment_ref, 'paid_marked_at', b.paid_marked_at, 'has_proof', coalesce(b.proof_path, '') <> '')
        ORDER BY b.paid_marked_at NULLS LAST, b.created_at)
      FROM bookings b LEFT JOIN profiles pr ON pr.id = b.user_id
      WHERE b.event_id = p_event_id AND b.payment_state = 'pending_verification'), '[]'::jsonb));
END;
$$;

-- ================================================================== transfer proof, one booking at a time
CREATE OR REPLACE FUNCTION public.open_payment_proof(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_b bookings%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF v_b.id IS NULL OR NOT public.project_delegate_ok(v_b.event_id, 'money') THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF v_b.payment_state <> 'pending_verification' THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AWAITING'); END IF;
  IF coalesce(v_b.proof_path, '') = '' THEN RETURN jsonb_build_object('success', false, 'error', 'NO_PROOF'); END IF;
  PERFORM public.event_money_audit_add(v_b.event_id, v_b.id, NULL, 'proof_open', NULL);
  RETURN jsonb_build_object('success', true, 'bucket', 'pay-proof', 'path', v_b.proof_path,
                            'expires_in_minutes', public.project_limit('proofOpenMinutes'));
END;
$$;

-- The storage policy's question, answered with the definer's rights (the delegate cannot read event_money_audit).
CREATE OR REPLACE FUNCTION public.pay_proof_delegate_ok(p_object_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM bookings b JOIN event_money_audit a ON a.booking_id = b.id
     WHERE b.id::text = split_part(p_object_name, '/', 1)
       AND b.payment_state = 'pending_verification'
       AND a.action = 'proof_open' AND a.actor_id = auth.uid()
       AND a.at > now() - make_interval(mins => public.project_limit('proofOpenMinutes')))
  AND public.project_delegate_ok((SELECT b.event_id FROM bookings b WHERE b.id::text = split_part(p_object_name, '/', 1)), 'money');
$$;

DROP POLICY IF EXISTS "pay_proof_read_delegate" ON storage.objects;
CREATE POLICY "pay_proof_read_delegate" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'pay-proof' AND public.pay_proof_delegate_ok(name));

-- proofOpenMinutes joins the limits (= src/data/projectLimits.json).
CREATE OR REPLACE FUNCTION public.project_limits()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'lanesMax', 10, 'laneNameMax', 24, 'changeWhyMax', 140, 'reasonMin', 3, 'reasonMax', 140,
    'taskTitleMin', 3, 'taskTitleMax', 60, 'postTitleMin', 3, 'postTitleMax', 80, 'postBodyMax', 280,
    'replyMax', 140, 'repliesMax', 10, 'proposalOptionsMin', 2, 'proposalOptionsMax', 4, 'proposalOptionMax', 40,
    'rosTitleMin', 2, 'rosTitleMax', 40, 'rosMinMinutes', 10, 'rosWindowBeforeStartHours', 12, 'rosWindowAfterStartHours', 24,
    'trashMax', 30, 'trashDays', 7, 'channelsMax', 5, 'channelLabelMax', 30, 'channelUrlMax', 300,
    'inviteHours', 48, 'inviteMaxUses', 20, 'grantDays', 7, 'readOnlyDays', 30, 'purgeDays', 90, 'digestHour', 18,
    'proofOpenMinutes', 5);
$$;

-- ================================================================== verify_payment (213 + delegation)
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
  v_delegate boolean := false;
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

  -- 214 (note 76): a project member with money access, behind switch project_delegate_payments, on TOP of the unchanged
  -- check above, and only for a guest who says they paid and waits for a check (pending_verification).
  IF NOT v_authorized THEN
    v_delegate := v_b.payment_state = 'pending_verification' AND public.project_delegate_ok(v_b.event_id, 'money');
    v_authorized := v_delegate;
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

  IF v_delegate THEN PERFORM public.event_money_audit_add(v_b.event_id, v_b.id, NULL, 'confirm_payment', NULL); END IF;

  RETURN jsonb_build_object('success', true, 'state', 'confirmed',
                            'receipt_number', v_receipt_number, 'via', p_via);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.verify_payment(uuid, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_payment(uuid, text, text, jsonb) TO authenticated;

-- ================================================================== confirm_payment (060 + delegation)
CREATE OR REPLACE FUNCTION public.confirm_payment(p_booking uuid, p_method text DEFAULT 'momo')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_is_authorized boolean;
  v_thread_id uuid;
  v_receipt payment_documents%ROWTYPE;
  v_receipt_number text := NULL;
  v_delegate boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT b.* INTO v_booking FROM bookings b WHERE b.id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_booking.event_id
      AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) INTO v_is_authorized;

  -- 214 (note 76): a project member with money access, behind switch project_delegate_payments, on TOP of the unchanged
  -- check above, and only for a guest who says they paid and waits for a check (pending_verification).
  IF NOT v_is_authorized THEN
    v_delegate := v_booking.payment_state = 'pending_verification' AND public.project_delegate_ok(v_booking.event_id, 'money');
    v_is_authorized := v_delegate;
  END IF;
  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_booking.status <> 'pending' AND v_booking.status <> 'confirmed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_PENDING');
  END IF;

  UPDATE bookings
  SET status = 'confirmed',
      payment_state = 'confirmed',
      hold_expires_at = NULL,
      verify_due_at = NULL,
      paid_marked_at = now(),
      paid_method = p_method,
      paid_marked_by = auth.uid(),
      confirmed_at = now()
  WHERE id = p_booking;

  -- Documents. The invoice is issued first so a paid booking is never left
  -- holding a receipt for an invoice that was never raised.
  BEGIN
    PERFORM ensure_payment_document(p_booking, 'invoice');
    v_receipt := ensure_payment_document(p_booking, 'receipt');
    v_receipt_number := v_receipt.number;
  EXCEPTION WHEN OTHERS THEN
    v_receipt_number := NULL;
  END;

  SELECT id INTO v_thread_id
  FROM threads
  WHERE event_id = v_booking.event_id AND guest_id = v_booking.user_id;

  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Host marked payment received via ' || COALESCE(p_method, 'direct transfer') || '.'
            || COALESCE(' Biên nhận ▪︎ Receipt ' || v_receipt_number, ''), 'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_booking.user_id, 'payment_confirmed',
          'Đã nhận thanh toán',
          'Người tổ chức xác nhận đã nhận thanh toán của bạn. Biên nhận đã sẵn sàng trong Tài khoản.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_booking.event_id,
                             'receipt_number', v_receipt_number));

  IF v_delegate THEN PERFORM public.event_money_audit_add(v_booking.event_id, p_booking, NULL, 'confirm_payment', NULL); END IF;

  RETURN jsonb_build_object('success', true, 'booking_id', p_booking,
                            'receipt_number', v_receipt_number, 'payment_state', 'confirmed');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.confirm_payment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_payment(uuid, text) TO authenticated;

-- ================================================================== switch + who may call what
UPDATE public.app_feature_flag_defs SET description = 'Event Project Hub: team members with money access may confirm payments (214)'
 WHERE key = 'project_delegate_payments';
REVOKE ALL ON FUNCTION public.project_limits() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_event_money_view(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.open_payment_proof(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pay_proof_delegate_ok(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_event_money_view(text), public.open_payment_proof(uuid) TO authenticated;
-- The storage policy evaluates as the caller, so the yes/no helper must be callable; it returns a boolean only.
GRANT EXECUTE ON FUNCTION public.pay_proof_delegate_ok(text) TO authenticated;
