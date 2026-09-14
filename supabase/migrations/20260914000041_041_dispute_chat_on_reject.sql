-- Migration: fix the dispute chat not opening (or updating live) after a
-- plain "Can't find it" rejection.
--
-- ---------------------------------------------------------------------------
-- ROOT CAUSE 1 — session/linkage: reject_payment() never opened a
-- dispute_threads row
-- ---------------------------------------------------------------------------
-- Only escalate_payment_dispute() (migration 033) ever INSERTs into
-- dispute_threads. reject_payment() (migration 032) records the reason on
-- bookings.dispute_reason and messages the guest's ORDINARY thread, but
-- creates no dispute_threads row at all. DisputeChatPanel.jsx/.swift's
-- loadDisputeChat looks a thread up by booking_id and, finding none, just
-- resolves to an empty chat — which reads exactly like "messages aren't
-- delivering" when the real problem is there was never a session to link
-- to in the first place. The client-side symptom was compounded by
-- PaymentDetails.jsx/Verifications.jsx only ever rendering
-- <DisputeChatPanel> when payment_state = 'disputed' (escalated) — so for a
-- plain reject the panel didn't even mount (fixed alongside this
-- migration, client-side, using dispute_reason as the signal instead).
--
-- Fixed here: reject_payment() now opens the same dispute_threads row
-- escalate_payment_dispute() does (ON CONFLICT DO NOTHING, so escalating
-- afterward is still safe) — WITHOUT touching payment_state/disputed_at,
-- preserving migration 032's entire point that a plain reject never
-- disputes or brings banbe in.
CREATE OR REPLACE FUNCTION public.reject_payment(
  p_booking uuid, p_reason text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_authorized boolean;
  v_thread_id uuid;
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

  UPDATE bookings SET dispute_reason = left(trim(COALESCE(p_reason, '')), 400) WHERE id = p_booking
  RETURNING * INTO v_b;

  PERFORM log_payment_event(
    p_booking, 'T2_flagged_not_found', v_b.payment_state, v_b.payment_state,
    auth.uid(), 'organizer', NULL, NULL,
    jsonb_build_object('reason', v_b.dispute_reason, 'transaction_id', v_b.transaction_id,
                       'proof_path', v_b.proof_path, 'payment_ref', v_b.payment_ref)
  );

  -- The temporary chat itself — same table escalate_payment_dispute() uses,
  -- opened here too so "Can't find it" alone is enough for the guest and
  -- organizer to actually talk, not just receive one system message each.
  INSERT INTO dispute_threads (booking_id, event_id, guest_id, organizer_id)
  VALUES (v_b.id, v_b.event_id, v_b.user_id, (SELECT organizer_id FROM events WHERE id = v_b.event_id))
  ON CONFLICT (booking_id) DO NOTHING;

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Người tổ chức chưa tìm thấy khoản chuyển khoản này'
            || COALESCE(': ' || NULLIF(v_b.dispute_reason, ''), '')
            || '. Vui lòng kiểm tra lại thông tin chuyển khoản hoặc gửi thêm bằng chứng — chỗ của bạn vẫn được giữ.',
            'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_b.user_id, 'payment_needs_info', 'Cần thêm thông tin chuyển khoản',
          'Người tổ chức chưa tìm thấy khoản chuyển khoản của bạn. Chỗ vẫn được giữ — kiểm tra tin nhắn để biết chi tiết.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                             'reason', v_b.dispute_reason));

  RETURN jsonb_build_object('success', true, 'state', v_b.payment_state);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.reject_payment(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reject_payment(uuid, text) TO authenticated;

-- v_pending_verifications never exposed dispute_reason, so
-- Verifications.jsx/VerificationsView.swift had no way to know a row had
-- already been flagged (and therefore had a chat open) without escalating.
CREATE OR REPLACE VIEW public.v_pending_verifications
WITH (security_invoker = true) AS
SELECT
  b.id AS booking_id, b.event_id, e.name AS event_name, e.organizer_id,
  b.user_id, p.display_name AS guest_name,
  b.qty, b.total_vnd, b.payment_ref, b.transaction_id, b.proof_path,
  b.proof_submitted_at, b.verify_due_at,
  b.verify_reminded_at IS NOT NULL AS reminded,
  b.verify_escalated_at IS NOT NULL AS escalated,
  b.verify_due_at < now() AS overdue,
  b.dispute_reason
FROM bookings b
JOIN events e ON e.id = b.event_id
LEFT JOIN profiles p ON p.id = b.user_id
WHERE b.payment_state = 'pending_verification';

-- ---------------------------------------------------------------------------
-- ROOT CAUSE 2 — no realtime delivery: fixed client-side (DisputeChatPanel.jsx
-- /.swift now poll every 4s), not here. This app has no Supabase Realtime
-- usage anywhere (grep for .channel(/postgres_changes across src/,
-- apps/ios/BanbeApp/, supabase/migrations/ returns nothing) and
-- dispute_messages/dispute_threads were never added to the
-- supabase_realtime publication — polling matches the pattern
-- PaymentDetails.jsx's own 6s payment-status poll already uses elsewhere in
-- this codebase, rather than introducing a new delivery mechanism nothing
-- else here uses.
-- ---------------------------------------------------------------------------
