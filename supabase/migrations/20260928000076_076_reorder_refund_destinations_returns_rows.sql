-- Migration: reorder_refund_destinations() now returns the canonical saved
-- rows in one round trip.
--
-- Product rule B3: "RPC must return the canonical saved ordered rows, or
-- client must receive an authoritative revision/result before ending the
-- mutation." Previously the client had to fire a SEPARATE
-- loadRefundDestinations() fetch after this RPC to find out what actually
-- got persisted — a second network round trip that could race with
-- anything else touching this same state, and the exact class of bug that
-- produces a "snap back" if the two ever land out of order. The client no
-- longer needs that second fetch on success at all: this single call's own
-- response is now the authoritative order.

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

  RETURN jsonb_build_object(
    'success', true,
    'destinations', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'user_id', user_id, 'label', label, 'bank_name', bank_name,
        'account_number', account_number, 'account_holder_name', account_holder_name,
        'transfer_note', transfer_note, 'is_default', is_default, 'position', position,
        'confirmed_at', confirmed_at, 'updated_at', updated_at
      ) ORDER BY position), '[]'::jsonb)
      FROM refund_destinations WHERE user_id = auth.uid()
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.reorder_refund_destinations(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.reorder_refund_destinations(uuid[]) TO authenticated;
