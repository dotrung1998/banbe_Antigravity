-- Refund auto-confirmation: a host_marked_sent claim that the guest has neither
-- confirmed nor disputed within 7 days of host_marked_at settles itself as
-- guest_confirmed. The guest can still dispute at any point before that
-- (dispute_refund() accepts host_marked_sent). The Terms and every in-app
-- "Things to do" card state this 7-day rule — keep them in sync with the
-- interval below.

ALTER TABLE public.refund_claims
  ADD COLUMN IF NOT EXISTS auto_confirmed boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.goc_auto_confirm_refunds()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int := 0;
  v_row record;
  v_recipient uuid;
  v_amount text;
BEGIN
  FOR v_row IN
    SELECT rc.id AS claim_id, rc.amount_vnd, b.id AS booking_id, b.user_id AS guest_id,
           e.id AS event_id, e.name AS event_name, o.owner_id, o.user_id AS org_user_id
    FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    LEFT JOIN organizers o ON o.id = e.organizer_id
    WHERE rc.status = 'host_marked_sent'
      AND rc.host_marked_at IS NOT NULL
      AND rc.host_marked_at < now() - interval '7 days'
    FOR UPDATE OF rc SKIP LOCKED
  LOOP
    UPDATE refund_claims
       SET status = 'guest_confirmed', guest_confirmed_at = now(), auto_confirmed = true
     WHERE id = v_row.claim_id AND status = 'host_marked_sent';
    IF NOT FOUND THEN CONTINUE; END IF;

    v_amount := replace(to_char(v_row.amount_vnd, 'FM999G999G999'), ',', '.');

    IF v_row.guest_id IS NOT NULL THEN
      INSERT INTO public.notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_row.guest_id, 'refund_confirmed',
        'Hoàn tiền được tự động xác nhận',
        'Sau 7 ngày không có phản hồi, khoản hoàn ' || v_amount || '₫ cho '
          || COALESCE(v_row.event_name, 'sự kiện') || ' đã được tự động xác nhận.',
        jsonb_build_object('claim_id', v_row.claim_id, 'booking_id', v_row.booking_id, 'event_id', v_row.event_id, 'amount_vnd', v_row.amount_vnd, 'auto', true)
      );
    END IF;

    v_recipient := COALESCE(v_row.owner_id, v_row.org_user_id);
    IF v_recipient IS NOT NULL THEN
      INSERT INTO public.notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_recipient, 'refund_confirmed',
        'Hoàn tiền được tự động xác nhận',
        'Khoản hoàn ' || v_amount || '₫ cho ' || COALESCE(v_row.event_name, 'sự kiện')
          || ' đã được tự động xác nhận sau 7 ngày khách không phản hồi.',
        jsonb_build_object('claim_id', v_row.claim_id, 'booking_id', v_row.booking_id, 'event_id', v_row.event_id, 'amount_vnd', v_row.amount_vnd, 'auto', true)
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.goc_auto_confirm_refunds() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.goc_auto_confirm_refunds() FROM anon;
REVOKE EXECUTE ON FUNCTION public.goc_auto_confirm_refunds() FROM authenticated;

SELECT cron.schedule(
  job_name  => 'goc_auto_confirm_refunds',
  schedule  => '15 * * * *',
  command   => $cmd$ SELECT public.goc_auto_confirm_refunds(); $cmd$
);
