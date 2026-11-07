-- Migration: close payment dispute chats that outlived their booking, and keep them from doing it again.
--
-- Why this exists (found 2026-10-22, note 54 follow-up):
-- The auto-close trigger and the backfill at the bottom of migration 149 were added to that file in commit b14d5ad,
-- AFTER 149 had already been applied to the remote project. `supabase db push` never re-runs an applied version,
-- so the remote never got them:
--   * bookings_close_payment_dispute_thread / close_payment_dispute_thread_on_settle() — missing;
--   * the backfill — never ran;
--   * expire_not_found_bookings() — still the older body (closes the chat AFTER expiring the booking).
-- Two payment chats were stranded open on the remote (resolved_at NULL, booking long since confirmed):
-- Test v2.2 (test-v2-2-85895a) and Test sự kiện (test-s-ki-n-8444c8). Migration 189 counts every open dispute
-- thread as a removal blocker, so Manage events refused to remove Test v2.2 even though its refund was settled.
--
-- This migration re-states those three pieces (idempotent: CREATE OR REPLACE / DROP TRIGGER IF EXISTS / a backfill
-- that only touches still-open rows) and closes one more gap 149 never covered:
--   cancel_event() moves the event's bookings to status 'cancelled' but leaves payment_state alone, so a
--   "transfer not found" chat on a booking that was still pending_verification when the host cancelled never
--   met the payment_state trigger. Once the booking is cancelled or expired there is no ticket left to argue
--   about (any money goes through refund_claims, which has its own dispute flow), so the chat closes too.
--   An ESCALATED dispute (payment_state 'disputed') is left alone in both paths: only banbe's decision in
--   resolve_dispute() closes it, with its own note and email.

-- ---------------------------------------------------------------------------------------------------------------
-- 1. expire_not_found_bookings(): body = migration 149 as committed (closes the chat BEFORE expiring the booking,
--    so the chat keeps the "no agreement within 2 days" note instead of the trigger's generic one).
-- ---------------------------------------------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------------------------------------------
-- 2. The auto-close trigger: payment_state leaving the unsettled states (as in 149), or the booking itself being
--    cancelled/expired while not escalated (new).
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_payment_dispute_thread_on_settle()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.payment_state::text = 'disputed' THEN
    RETURN NEW;  -- escalated to banbe: resolve_dispute() closes it
  END IF;
  UPDATE dispute_threads SET
    resolved_at = now(),
    resolution_kind = CASE WHEN NEW.payment_state::text = 'confirmed' AND NEW.status::text NOT IN ('cancelled', 'expired')
                           THEN 'ticket_issued' ELSE 'cancelled' END,
    resolution_note = CASE WHEN NEW.status::text IN ('cancelled', 'expired') AND OLD.status IS DISTINCT FROM NEW.status
                           THEN 'Auto-closed: booking cancelled' ELSE 'Auto-closed: booking settled' END,
    purge_after = now() + interval '72 hours'
  WHERE booking_id = NEW.id AND kind = 'payment' AND resolved_at IS NULL;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.close_payment_dispute_thread_on_settle() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS bookings_close_payment_dispute_thread ON public.bookings;
CREATE TRIGGER bookings_close_payment_dispute_thread
AFTER UPDATE OF payment_state ON public.bookings
FOR EACH ROW
WHEN (OLD.payment_state::text IN ('pending_verification', 'holding')
      AND NEW.payment_state::text IN ('confirmed', 'expired', 'cancelled'))
EXECUTE FUNCTION public.close_payment_dispute_thread_on_settle();

DROP TRIGGER IF EXISTS bookings_close_payment_dispute_thread_on_cancel ON public.bookings;
CREATE TRIGGER bookings_close_payment_dispute_thread_on_cancel
AFTER UPDATE OF status ON public.bookings
FOR EACH ROW
WHEN (OLD.status::text NOT IN ('cancelled', 'expired')
      AND NEW.status::text IN ('cancelled', 'expired'))
EXECUTE FUNCTION public.close_payment_dispute_thread_on_settle();

-- ---------------------------------------------------------------------------------------------------------------
-- 3. Backfill: every payment chat still open on a booking that is settled, cancelled or expired — never an
--    escalated one.
-- ---------------------------------------------------------------------------------------------------------------
UPDATE dispute_threads t SET
  resolved_at = now(),
  resolution_kind = CASE WHEN b.payment_state::text = 'confirmed' AND b.status::text NOT IN ('cancelled', 'expired')
                         THEN 'ticket_issued' ELSE 'cancelled' END,
  resolution_note = 'Auto-closed: booking settled',
  purge_after = now() + interval '72 hours'
FROM bookings b
WHERE b.id = t.booking_id AND t.kind = 'payment' AND t.resolved_at IS NULL
  AND b.payment_state::text <> 'disputed'
  AND (b.payment_state::text NOT IN ('pending_verification', 'holding')
       OR b.status::text IN ('cancelled', 'expired'));
