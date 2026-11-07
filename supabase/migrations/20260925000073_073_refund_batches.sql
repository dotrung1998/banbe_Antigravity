-- Migration: refund_batches / refund_batch_items — a real batch model for
-- host bulk refund confirmation (product rule 4), not just a client-side
-- multi-select. create_and_confirm_refund_batch() is the only write path
-- (create + confirm happen together, atomically, in one call) — there is
-- deliberately no separate "create a draft batch" RPC, so a batch row can
-- never exist without its items already being marked sent.

CREATE TABLE IF NOT EXISTS refund_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id text REFERENCES organizers(id) ON DELETE SET NULL,
  created_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  note text,
  total_amount_vnd int NOT NULL DEFAULT 0,
  recipient_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS refund_batch_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES refund_batches(id) ON DELETE CASCADE,
  claim_id uuid NOT NULL REFERENCES refund_claims(id) ON DELETE CASCADE,
  amount_vnd int NOT NULL DEFAULT 0,
  -- false = this claim was selected client-side but was no longer eligible
  -- (already resolved elsewhere, or the guest still has no confirmed
  -- refund destination) by the time this batch's own transaction ran —
  -- skipped, not touched, and reported back to the host as `skipped_count`.
  applied boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_refund_batch_items_batch ON refund_batch_items(batch_id);
CREATE INDEX IF NOT EXISTS idx_refund_batch_items_claim ON refund_batch_items(claim_id);

ALTER TABLE refund_batches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "refund_batches_select_host" ON refund_batches;
CREATE POLICY "refund_batches_select_host" ON refund_batches FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM organizers o
    WHERE o.id = refund_batches.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);

ALTER TABLE refund_batch_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "refund_batch_items_select_host" ON refund_batch_items;
CREATE POLICY "refund_batch_items_select_host" ON refund_batch_items FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM refund_batches rb
    JOIN organizers o ON o.id = rb.organizer_id
    WHERE rb.id = refund_batch_items.batch_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);

-- ---------------------------------------------------------------------------
-- create_and_confirm_refund_batch() — host taps "Xác nhận đã chuyển tiền"
-- for 1, many, or all selected rows at once.
--
-- Re-checks eligibility (status IN ('owed','disputed') AND the guest has a
-- CONFIRMED refund_destinations row) for every claim INSIDE this same
-- transaction, `FOR UPDATE` locked, so nothing selected a moment earlier
-- client-side but already resolved/confirmed by someone else in the
-- meantime gets touched — those are recorded as a skipped batch item and
-- counted in `skipped_count`, never marked sent. A row already
-- host_marked_sent/guest_confirmed/waived is never overwritten.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_and_confirm_refund_batch(p_claim_ids uuid[], p_note text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer_id text;
  v_batch_id uuid := gen_random_uuid();
  v_total int := 0;
  v_applied int := 0;
  v_skipped int := 0;
  v_row record;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  IF p_claim_ids IS NULL OR array_length(p_claim_ids, 1) IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_CLAIMS_SELECTED');
  END IF;

  -- Every selected claim must belong to an event this caller organizes.
  IF EXISTS (
    SELECT 1 FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    LEFT JOIN organizers o ON o.id = e.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    WHERE rc.id = ANY(p_claim_ids) AND o.id IS NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  SELECT o.id INTO v_organizer_id
  FROM refund_claims rc
  JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
  JOIN events e ON e.id = b.event_id
  JOIN organizers o ON o.id = e.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  WHERE rc.id = p_claim_ids[1];

  INSERT INTO refund_batches (id, organizer_id, created_by, note, total_amount_vnd, recipient_count)
  VALUES (v_batch_id, v_organizer_id, auth.uid(), NULLIF(trim(p_note), ''), 0, 0);

  FOR v_row IN
    SELECT rc.id, rc.amount_vnd, rc.status, b.user_id, e.name AS event_name
    FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    WHERE rc.id = ANY(p_claim_ids)
    FOR UPDATE OF rc
  LOOP
    IF v_row.status NOT IN ('owed', 'disputed') OR NOT EXISTS (
      SELECT 1 FROM refund_destinations rd WHERE rd.user_id = v_row.user_id AND rd.confirmed_at IS NOT NULL
    ) THEN
      INSERT INTO refund_batch_items (batch_id, claim_id, amount_vnd, applied) VALUES (v_batch_id, v_row.id, v_row.amount_vnd, false);
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    UPDATE refund_claims SET status = 'host_marked_sent', host_marked_at = now() WHERE id = v_row.id;
    INSERT INTO refund_batch_items (batch_id, claim_id, amount_vnd, applied) VALUES (v_batch_id, v_row.id, v_row.amount_vnd, true);
    v_total := v_total + v_row.amount_vnd;
    v_applied := v_applied + 1;

    IF v_row.user_id IS NOT NULL THEN
      INSERT INTO public.notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_row.user_id, 'refund_marked_sent',
        'Người tổ chức đã báo hoàn tiền',
        COALESCE(v_row.event_name, 'Sự kiện') || ' báo đã hoàn '
          || replace(to_char(v_row.amount_vnd, 'FM999G999G999'), ',', '.') || '₫ cho bạn.',
        jsonb_build_object('claim_id', v_row.id, 'amount_vnd', v_row.amount_vnd, 'batch_id', v_batch_id)
      );
    END IF;
  END LOOP;

  UPDATE refund_batches SET total_amount_vnd = v_total, recipient_count = v_applied WHERE id = v_batch_id;

  RETURN jsonb_build_object(
    'success', true, 'batch_id', v_batch_id,
    'applied_count', v_applied, 'skipped_count', v_skipped, 'total_amount_vnd', v_total
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_and_confirm_refund_batch(uuid[], text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_and_confirm_refund_batch(uuid[], text) TO authenticated;
