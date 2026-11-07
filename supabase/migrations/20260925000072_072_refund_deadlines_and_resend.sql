-- Migration: refund deadlines (due date, dispute response window) + host
-- "resend transfer info" / "send again" actions.
--
-- New refund_claims columns only — existing statuses/behavior are extended,
-- never replaced. cancel_booking()/dispute_refund()/mark_refund_sent() are
-- redefined here (CREATE OR REPLACE, same signatures) to populate them;
-- migrations 069/070 stay as committed.

ALTER TABLE refund_claims
  ADD COLUMN IF NOT EXISTS refund_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS disputed_at timestamptz,
  ADD COLUMN IF NOT EXISTS host_response_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS dispute_flagged_at timestamptz,
  ADD COLUMN IF NOT EXISTS transfer_reference text,
  ADD COLUMN IF NOT EXISTS resend_reference text,
  ADD COLUMN IF NOT EXISTS resend_bank_name text,
  ADD COLUMN IF NOT EXISTS resend_transferred_at timestamptz,
  ADD COLUMN IF NOT EXISTS resend_note text;

CREATE UNIQUE INDEX IF NOT EXISTS idx_refund_claims_transfer_reference
  ON refund_claims(transfer_reference) WHERE transfer_reference IS NOT NULL;

-- ---------------------------------------------------------------------------
-- goc_add_business_days() — Mon-Fri only, skips Sat/Sun. Used for the "3
-- business days" refund deadline (product rule 1).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION goc_add_business_days(p_start timestamptz, p_days int)
RETURNS timestamptz
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_result timestamptz := p_start;
  v_added int := 0;
BEGIN
  WHILE v_added < p_days LOOP
    v_result := v_result + interval '1 day';
    IF EXTRACT(ISODOW FROM v_result) < 6 THEN -- 1=Mon .. 5=Fri
      v_added := v_added + 1;
    END IF;
  END LOOP;
  RETURN v_result;
END;
$$;

-- ---------------------------------------------------------------------------
-- cancel_booking() — same as migration 070, now also sets refund_due_at
-- (cancellation time + 3 business days) and a unique transfer_reference
-- (`BANBE-<8 hex chars of the claim id>`) on the refund claim it creates.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cancel_booking(p_booking uuid, p_reason text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_authorized boolean;
  v_thread_id uuid;
  v_had_payment boolean;
  v_clean_reason text := trim(p_reason);
  v_host_initiated boolean;
  v_claim_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT b.* INTO v_booking FROM bookings b WHERE b.id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  v_is_authorized := (v_booking.user_id = auth.uid()) OR EXISTS(
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_booking.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  );

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_booking.status IN ('cancelled', 'expired', 'attended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_CANNOT_BE_CANCELLED');
  END IF;

  v_had_payment := v_booking.status = 'confirmed' OR v_booking.paid_marked_at IS NOT NULL;
  v_host_initiated := v_booking.user_id IS DISTINCT FROM auth.uid();

  UPDATE bookings
  SET status = 'cancelled',
      cancelled_at = now(),
      cancelled_by = auth.uid(),
      cancel_reason = COALESCE(p_reason, '')
  WHERE id = p_booking;

  IF v_had_payment THEN
    INSERT INTO refund_claims (booking_id, reservation_id, amount_vnd, reason, status, refund_due_at)
    VALUES (
      v_booking.id, v_booking.id, v_booking.total_vnd,
      CASE WHEN v_host_initiated THEN 'host_cancelled'::refund_reason ELSE 'guest_cancelled'::refund_reason END,
      'owed',
      goc_add_business_days(now(), 3)
    )
    RETURNING id INTO v_claim_id;

    UPDATE refund_claims
    SET transfer_reference = 'BANBE-' || upper(substr(replace(v_claim_id::text, '-', ''), 1, 8))
    WHERE id = v_claim_id;
  END IF;

  SELECT id INTO v_thread_id
  FROM threads
  WHERE event_id = v_booking.event_id AND guest_id = v_booking.user_id;

  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(), 'Booking cancelled. Reason: ' || COALESCE(NULLIF(p_reason, ''), 'No reason provided') || '.', 'system');
  END IF;

  IF v_booking.user_id IS NOT NULL AND v_booking.user_id <> auth.uid() THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_booking.user_id,
      'booking_cancelled',
      'Vé của bạn đã bị huỷ',
      COALESCE(v_event.name, 'Sự kiện') || ' đã huỷ vé của bạn.'
        || (CASE WHEN v_had_payment THEN ' Khoản bạn đã thanh toán sẽ được hoàn lại.' ELSE '' END)
        || (CASE WHEN v_clean_reason <> '' THEN ' Lý do: ' || v_clean_reason ELSE '' END),
      jsonb_build_object('event_id', v_booking.event_id, 'booking_id', v_booking.id, 'reason', v_clean_reason, 'had_payment', v_had_payment)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'booking_id', p_booking);
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_booking(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION cancel_booking(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- dispute_refund() — same as migration 069, now also stamps disputed_at and
-- a 48h host_response_due_at (product rule 1/5). Also resets
-- dispute_flagged_at, so a claim disputed a SECOND time (after an earlier
-- resend/re-send round) becomes eligible for the 48h overdue flag again
-- instead of being silently skipped by goc_flag_overdue_refunds() forever.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dispute_refund(p_claim_id uuid, p_reason text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_recipient uuid;
  v_reason text := trim(p_reason);
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

  IF v_claim.status = 'disputed' THEN
    RETURN jsonb_build_object('success', true, 'status', v_claim.status, 'already', true);
  END IF;
  IF v_claim.status NOT IN ('owed', 'host_marked_sent') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;
  SELECT * INTO v_org FROM organizers WHERE id = v_event.organizer_id;
  v_recipient := COALESCE(v_org.owner_id, v_org.user_id);

  UPDATE refund_claims
  SET status = 'disputed',
      disputed_at = now(),
      host_response_due_at = now() + interval '48 hours',
      dispute_flagged_at = NULL,
      note = CASE WHEN v_reason <> ''
                  THEN COALESCE(note || E'\n', '') || 'Guest dispute: ' || v_reason
                  ELSE note END
  WHERE id = p_claim_id;

  IF v_recipient IS NOT NULL AND v_claim.last_flagged_at IS NULL THEN
    UPDATE organizers SET disputes_open = COALESCE(disputes_open, 0) + 1 WHERE id = v_org.id;
    UPDATE refund_claims SET last_flagged_at = now() WHERE id = p_claim_id;
  END IF;

  IF v_recipient IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_recipient, 'refund_disputed',
      'Khách báo chưa nhận được hoàn tiền',
      'Khách báo chưa nhận được ' || replace(to_char(v_claim.amount_vnd, 'FM999G999G999'), ',', '.')
        || '₫ cho ' || COALESCE(v_event.name, 'sự kiện') || '.'
        || (CASE WHEN v_reason <> '' THEN ' Lý do: ' || v_reason ELSE '' END),
      jsonb_build_object('claim_id', v_claim.id, 'booking_id', v_booking.id, 'event_id', v_event.id, 'amount_vnd', v_claim.amount_vnd, 'reason', v_reason)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'disputed');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.dispute_refund(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.dispute_refund(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- mark_refund_sent() — same as migration 069, now also accepts a claim
-- currently 'disputed' (not just 'owed') as a valid source state. This is
-- product rule 5B, "Hoàn lại lần nữa" ("send again"): the host re-sends the
-- SAME claim, never a new refund_claims row, and it goes back to
-- host_marked_sent so the guest can confirm again.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_refund_sent(p_claim_id uuid, p_note text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_host boolean;
  v_note text := trim(p_note);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  SELECT EXISTS(
    SELECT 1 FROM organizers o
    WHERE o.id = v_event.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) INTO v_is_host;
  IF NOT v_is_host THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_claim.status = 'host_marked_sent' THEN
    RETURN jsonb_build_object('success', true, 'status', v_claim.status, 'already', true);
  END IF;
  IF v_claim.status NOT IN ('owed', 'disputed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;

  UPDATE refund_claims
  SET status = 'host_marked_sent',
      host_marked_at = now(),
      note = CASE WHEN v_note <> ''
                  THEN COALESCE(note || E'\n', '') || 'Host note: ' || v_note
                  ELSE note END
  WHERE id = p_claim_id;

  IF v_booking.user_id IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_booking.user_id, 'refund_marked_sent',
      'Người tổ chức đã báo hoàn tiền',
      COALESCE(v_event.name, 'Sự kiện') || ' báo đã hoàn '
        || replace(to_char(v_claim.amount_vnd, 'FM999G999G999'), ',', '.') || '₫ cho bạn.',
      jsonb_build_object('claim_id', v_claim.id, 'booking_id', v_booking.id, 'event_id', v_event.id, 'amount_vnd', v_claim.amount_vnd)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'host_marked_sent');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_refund_sent(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_refund_sent(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- resend_refund_transfer_info() — product rule 5A, "Gửi lại thông tin
-- chuyển khoản": the host re-sends the PROOF of an already-claimed transfer
-- (reference/bank/transferred_at/note) without changing the claim's status
-- — it's still 'disputed', still waiting on the guest's own confirmation or
-- a real "Hoàn lại lần nữa" (mark_refund_sent, above). Reuses the existing
-- 'refund_marked_sent' notification kind — openNotification() on both
-- platforms already routes it straight to the guest's PaymentDetails
-- screen, so no new notification-kind handling is needed client-side.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resend_refund_transfer_info(
  p_claim_id uuid,
  p_reference text DEFAULT '',
  p_bank_name text DEFAULT '',
  p_transferred_at timestamptz DEFAULT NULL,
  p_note text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_host boolean;
  v_note text := trim(p_note);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  SELECT EXISTS(
    SELECT 1 FROM organizers o
    WHERE o.id = v_event.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) INTO v_is_host;
  IF NOT v_is_host THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_claim.status <> 'disputed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;

  UPDATE refund_claims
  SET resend_reference = NULLIF(trim(p_reference), ''),
      resend_bank_name = NULLIF(trim(p_bank_name), ''),
      resend_transferred_at = p_transferred_at,
      resend_note = NULLIF(v_note, ''),
      note = CASE WHEN v_note <> ''
                  THEN COALESCE(note || E'\n', '') || 'Host resend info: ' || v_note
                  ELSE note END
  WHERE id = p_claim_id;

  IF v_booking.user_id IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_booking.user_id, 'refund_marked_sent',
      'Người tổ chức đã gửi lại thông tin chuyển khoản',
      COALESCE(v_event.name, 'Sự kiện') || ' đã gửi lại thông tin chuyển khoản cho khoản hoàn tiền của bạn.',
      jsonb_build_object('claim_id', v_claim.id, 'booking_id', v_booking.id, 'event_id', v_event.id, 'amount_vnd', v_claim.amount_vnd)
    );
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.resend_refund_transfer_info(uuid, text, text, timestamptz, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.resend_refund_transfer_info(uuid, text, text, timestamptz, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- goc_flag_overdue_refunds() — same shape as migration 069, now flags TWO
-- distinct overdue conditions (product rule 1): an `owed` claim past its
-- real refund_due_at (was: a fixed 72h-since-created heuristic — now driven
-- by the actual 3-business-day deadline cancel_booking() sets), and a
-- `disputed` claim whose host_response_due_at (48h since disputed_at) has
-- passed with no host response. Never auto-closes/refunds/deletes anything
-- — flagging + notifying only, same as before.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION goc_flag_overdue_refunds()
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  v_count int := 0;
  v_row record;
  v_recipient uuid;
BEGIN
  FOR v_row IN
    SELECT rc.id AS claim_id, rc.booking_id, rc.amount_vnd,
           e.id AS event_id, e.name AS event_name, e.organizer_id,
           o.owner_id, o.user_id AS org_user_id
    FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    JOIN organizers o ON o.id = e.organizer_id
    WHERE rc.status = 'owed'
      AND rc.last_flagged_at IS NULL
      AND rc.refund_due_at IS NOT NULL
      AND rc.refund_due_at < now()
      AND e.organizer_id IS NOT NULL
  LOOP
    UPDATE organizers
       SET disputes_open = COALESCE(disputes_open, 0) + 1
     WHERE id = v_row.organizer_id;

    UPDATE refund_claims
       SET last_flagged_at = now()
     WHERE id = v_row.claim_id;

    v_recipient := COALESCE(v_row.owner_id, v_row.org_user_id);
    IF v_recipient IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_recipient, 'refund_overdue',
        'Quá hạn hoàn tiền',
        'Khoản hoàn ' || replace(to_char(v_row.amount_vnd, 'FM999G999G999'), ',', '.')
          || '₫ cho ' || COALESCE(v_row.event_name, 'sự kiện') || ' đã quá hạn.',
        jsonb_build_object('claim_id', v_row.claim_id, 'booking_id', v_row.booking_id, 'event_id', v_row.event_id, 'amount_vnd', v_row.amount_vnd)
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;

  FOR v_row IN
    SELECT rc.id AS claim_id, rc.booking_id, rc.amount_vnd,
           e.id AS event_id, e.name AS event_name, e.organizer_id,
           o.owner_id, o.user_id AS org_user_id
    FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    JOIN organizers o ON o.id = e.organizer_id
    WHERE rc.status = 'disputed'
      AND rc.dispute_flagged_at IS NULL
      AND rc.host_response_due_at IS NOT NULL
      AND rc.host_response_due_at < now()
      AND e.organizer_id IS NOT NULL
  LOOP
    UPDATE organizers
       SET disputes_open = COALESCE(disputes_open, 0) + 1
     WHERE id = v_row.organizer_id;

    UPDATE refund_claims
       SET dispute_flagged_at = now()
     WHERE id = v_row.claim_id;

    v_recipient := COALESCE(v_row.owner_id, v_row.org_user_id);
    IF v_recipient IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_recipient, 'refund_overdue',
        'Khiếu nại hoàn tiền quá hạn phản hồi',
        'Khiếu nại hoàn tiền cho ' || COALESCE(v_row.event_name, 'sự kiện') || ' đã quá 48 giờ chưa được phản hồi.',
        jsonb_build_object('claim_id', v_row.claim_id, 'booking_id', v_row.booking_id, 'event_id', v_row.event_id, 'amount_vnd', v_row.amount_vnd)
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION goc_flag_overdue_refunds() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION goc_flag_overdue_refunds() FROM anon;
GRANT EXECUTE ON FUNCTION goc_flag_overdue_refunds() TO authenticated;
