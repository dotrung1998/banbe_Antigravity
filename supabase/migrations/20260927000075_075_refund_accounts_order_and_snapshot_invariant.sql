-- Migration: refund_destinations ordering (product rule B) + the
-- mark-sent snapshot invariant (product rule C).

-- ---------------------------------------------------------------------------
-- B — persistent `position` ordering.
-- ---------------------------------------------------------------------------
ALTER TABLE refund_destinations ADD COLUMN IF NOT EXISTS position int;

-- Backfill: existing rows keep their current default-first / most-recent
-- order (mirrors the ORDER BY every client already queries with).
WITH ranked AS (
  SELECT id, row_number() OVER (PARTITION BY user_id ORDER BY is_default DESC, updated_at DESC) - 1 AS rn
  FROM refund_destinations
)
UPDATE refund_destinations rd SET position = ranked.rn
FROM ranked WHERE rd.id = ranked.id AND rd.position IS NULL;

ALTER TABLE refund_destinations ALTER COLUMN position SET DEFAULT 0;
ALTER TABLE refund_destinations ALTER COLUMN position SET NOT NULL;

-- ---------------------------------------------------------------------------
-- reorder_refund_destinations() — the goer drags an account to a new spot.
-- Transaction-safe, ownership-checked: every id in p_ordered_ids must
-- belong to the caller, and the call is rejected outright (no partial
-- reorder) if the set doesn't exactly match their own destinations.
-- Moving an account to position 0 makes it the default automatically
-- (product rule B3) — every other one is un-defaulted in the same
-- statement, so "exactly one default" (B5) never has a gap.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reorder_refund_destinations(p_ordered_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owned_count int;
  v_total_count int;
  v_id uuid;
  v_idx int := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF p_ordered_ids IS NULL OR array_length(p_ordered_ids, 1) IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_INPUT');
  END IF;

  SELECT count(*) INTO v_owned_count FROM refund_destinations WHERE id = ANY(p_ordered_ids) AND user_id = auth.uid();
  SELECT count(*) INTO v_total_count FROM refund_destinations WHERE user_id = auth.uid();
  IF v_owned_count <> array_length(p_ordered_ids, 1) OR v_owned_count <> v_total_count THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  FOREACH v_id IN ARRAY p_ordered_ids LOOP
    UPDATE refund_destinations
    SET position = v_idx,
        is_default = (v_idx = 0),
        updated_at = now()
    WHERE id = v_id;
    v_idx := v_idx + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.reorder_refund_destinations(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.reorder_refund_destinations(uuid[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- C — the mark-sent snapshot invariant. goc_refund_snapshot_valid() is the
-- one shared check both mark_refund_sent() and create_and_confirm_refund_
-- batch() (074) now call — a claim may become 'host_marked_sent' only with
-- a persisted, non-empty recipient snapshot (bank name, account number,
-- account-holder name). create_and_confirm_refund_batch() already required
-- `selected_destination_id IS NOT NULL`; this closes the exact loophole
-- that let an invalid claim exist: mark_refund_sent() — the OTHER path to
-- 'host_marked_sent' (Verifications.jsx's own "Đã hoàn tiền" button, and
-- Attendance.jsx's "Hoàn lại lần nữa") — never checked this at all.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION goc_refund_snapshot_valid(p_snapshot jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_snapshot IS NOT NULL
    AND coalesce(trim(p_snapshot->>'bank_name'), '') <> ''
    AND coalesce(trim(p_snapshot->>'account_number'), '') <> ''
    AND coalesce(trim(p_snapshot->>'account_holder_name'), '') <> '';
$$;

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

  -- THE fix: never allow this transition without a real, persisted
  -- recipient snapshot — a bare selected_destination_id with no valid
  -- snapshot content is treated the same as having none at all.
  IF v_claim.selected_destination_id IS NULL OR NOT goc_refund_snapshot_valid(v_claim.recipient_snapshot) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_DESTINATION_SELECTED');
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

-- create_and_confirm_refund_batch() (074) already required
-- selected_destination_id IS NOT NULL before applying; tightened here to
-- also run it through the same goc_refund_snapshot_valid() check, so both
-- paths share one single source of truth for "is this claim really ready
-- to be marked sent" — amount_vnd is read once per row and only ever
-- written back as itself, never zeroed, exactly as before.
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
    SELECT rc.id, rc.amount_vnd, rc.status, rc.selected_destination_id, rc.recipient_snapshot, b.user_id, e.name AS event_name
    FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    WHERE rc.id = ANY(p_claim_ids)
    FOR UPDATE OF rc
  LOOP
    IF v_row.status NOT IN ('owed', 'disputed')
       OR v_row.selected_destination_id IS NULL
       OR NOT goc_refund_snapshot_valid(v_row.recipient_snapshot) THEN
      INSERT INTO refund_batch_items (batch_id, claim_id, amount_vnd, applied, recipient_snapshot)
      VALUES (v_batch_id, v_row.id, v_row.amount_vnd, false, v_row.recipient_snapshot);
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    UPDATE refund_claims SET status = 'host_marked_sent', host_marked_at = now() WHERE id = v_row.id;
    INSERT INTO refund_batch_items (batch_id, claim_id, amount_vnd, applied, recipient_snapshot)
    VALUES (v_batch_id, v_row.id, v_row.amount_vnd, true, v_row.recipient_snapshot);
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

-- ---------------------------------------------------------------------------
-- One-time data repair (product rule C3): any EXISTING claim that reached
-- 'host_marked_sent' before this invariant existed, with no valid
-- snapshot, is not a real "sent" state — put back to 'owed' (never
-- guest_confirmed/disputed: those already imply a real snapshot existed at
-- some point, or are a goer's own action this migration must not touch).
-- Nothing about amount_vnd or any other claim is altered. Server-
-- authorized exactly as this ticket's own C3 allows — a schema migration,
-- not an ad hoc client mutation — and never invents recipient details.
-- ---------------------------------------------------------------------------
UPDATE refund_claims
SET status = 'owed',
    host_marked_at = NULL,
    note = COALESCE(note || E'\n', '') || 'System: reverted invalid host_marked_sent state (no valid recipient snapshot).'
WHERE status = 'host_marked_sent'
  AND (selected_destination_id IS NULL OR NOT goc_refund_snapshot_valid(recipient_snapshot));
