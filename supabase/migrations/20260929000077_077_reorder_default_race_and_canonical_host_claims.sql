-- Migration: fix the real server-side cause of reorder_refund_destinations()
-- failing (task B), and replace the client-composed host Refund Center
-- query with one canonical, ownership-enforcing RPC (task A) instead of
-- relying on a client-side filter.

-- ---------------------------------------------------------------------------
-- B — root cause: idx_refund_destinations_one_default (074) is a partial
-- UNIQUE INDEX on (user_id) WHERE is_default, checked immediately (not
-- deferred). reorder_refund_destinations()'s FOREACH loop updates rows one
-- at a time in p_ordered_ids order. Whenever the dragged-to-first row was
-- NOT already the default, the loop sets its is_default = true before it
-- reaches the row that previously held is_default = true (which is still
-- true at that moment) -> two rows with is_default = true simultaneously
-- for the same user_id -> 23505 unique_violation on every single drag of a
-- non-default row to the top. This is the exact Postgres error the client
-- was surfacing as "Chưa thể lưu thứ tự...".
--
-- Fix: clear is_default on all of the caller's own rows in one statement
-- BEFORE the per-row loop, so the loop only ever sets is_default = true
-- once nothing else is competing for it.
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

  -- Rejects duplicates (distinct-row count < array length), missing ids
  -- (owned count < total owned by this user) and foreign ids (not owned)
  -- all in one pair of checks — no partial reorder is ever applied.
  SELECT count(*) INTO v_owned_count FROM refund_destinations WHERE id = ANY(p_ordered_ids) AND user_id = auth.uid();
  SELECT count(*) INTO v_total_count FROM refund_destinations WHERE user_id = auth.uid();
  IF v_owned_count <> array_length(p_ordered_ids, 1) OR v_owned_count <> v_total_count THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- THE fix: never let two rows hold is_default = true at the same time.
  UPDATE refund_destinations SET is_default = false WHERE user_id = auth.uid() AND is_default = true;

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

-- ---------------------------------------------------------------------------
-- A — canonical host Refund Center claims, enforced server-side.
--
-- The previous client-side approach (GocContext.jsx/AppState+Payments.swift
-- loadRefundCenter) composed the query itself: fetch this event's bookings,
-- then fetch refund_claims via a client-built `.or(booking_id.eq...)`
-- string, then filter orphans in JS. That JS-side orphan filter (added in
-- the previous pass) is exactly the "UI filter" this ticket says is not a
-- real fix — it can only ever discard what the client already fetched, it
-- can't stop a malformed/cross-event/cross-organizer row from being fetched
-- in the first place, and it silently diverges from RLS/ownership logic
-- that lives in three separate places (RLS policy, client bookingIds
-- prefetch, client validClaims filter) with no single source of truth.
--
-- get_host_refund_claims() replaces that whole client composition with one
-- SECURITY DEFINER RPC whose SQL performs the entire canonical identity
-- chain (refund_claim -> booking -> booking.event_id = the requested event
-- -> event.organizer_id -> caller owns that organizer) as INNER JOINs. A
-- row can only ever appear in the result if every link resolves — an
-- orphaned claim (no booking), a claim whose booking belongs to a
-- different event, or a claim under an event the caller doesn't own is
-- structurally impossible to return, not merely filtered after the fact.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_host_refund_claims(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_host boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) INTO v_is_host;
  IF NOT v_is_host THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'claims', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', rc.id,
        'booking_id', b.id,
        'amount_vnd', rc.amount_vnd,
        'reason', rc.reason,
        'status', rc.status,
        'host_marked_at', rc.host_marked_at,
        'guest_confirmed_at', rc.guest_confirmed_at,
        'disputed_at', rc.disputed_at,
        'host_response_due_at', rc.host_response_due_at,
        'refund_due_at', rc.refund_due_at,
        'transfer_reference', rc.transfer_reference,
        'selected_destination_id', rc.selected_destination_id,
        'recipient_snapshot', rc.recipient_snapshot,
        'note', rc.note,
        'created_at', rc.created_at,
        'guest_user_id', b.user_id,
        'guest_name', coalesce(p.display_name, '')
      ) ORDER BY rc.created_at ASC), '[]'::jsonb)
      -- INNER JOINs only, on purpose: any row that can't resolve its full
      -- claim -> booking -> event(this one) -> organizer(caller) chain is
      -- dropped by the join itself, never reaches jsonb_agg.
      FROM refund_claims rc
      JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
      JOIN events e ON e.id = b.event_id AND e.id = p_event_id
      JOIN organizers o ON o.id = e.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
      LEFT JOIN profiles p ON p.id = b.user_id
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_host_refund_claims(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_host_refund_claims(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- A11 — one-time, narrow, non-destructive repair: flag (never delete)
-- refund_claims rows whose booking/event/organizer chain cannot resolve at
-- all, so they're visible for audit but excluded from every canonical
-- query going forward. get_host_refund_claims() above already can't return
-- these (INNER JOIN), so this column is defense-in-depth / operator
-- visibility, not required for correctness — but it lets an admin find and
-- decide what to do with genuinely orphaned historical rows without ever
-- broadly touching valid claims.
-- ---------------------------------------------------------------------------
ALTER TABLE refund_claims ADD COLUMN IF NOT EXISTS orphaned_at timestamptz;

UPDATE refund_claims rc
SET orphaned_at = now()
WHERE orphaned_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM bookings b
    JOIN events e ON e.id = b.event_id
    JOIN organizers o ON o.id = e.organizer_id
    WHERE b.id = COALESCE(rc.booking_id, rc.reservation_id)
  );
