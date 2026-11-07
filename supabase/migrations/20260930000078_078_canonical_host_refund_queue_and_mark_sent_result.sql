-- Migration: extend get_host_refund_claims() to also serve the ACCOUNT-LEVEL
-- (cross-event) host refund queue used by Verifications.jsx/VerificationsView
-- (task A), and make mark_refund_sent() return the full canonical claim +
-- an amount_vnd guard + the ticket's named business error code (task C).
--
-- Why: Account > Awaiting verification > Refunds (Verifications.jsx's
-- `loadRefundQueue`/AppState+Payments.swift's `loadRefundQueue()`) was NEVER
-- routed through migration 077's get_host_refund_claims() at all — it had
-- its own, separate, client-composed query (refund_claims -> bookings ->
-- events -> profiles, all fetched and joined in JS) that also never checked
-- whether a claim had a valid recipient snapshot before showing the "Mark
-- refund sent" CTA. That is the actual cause of "TDK404 / 80.000đ / Mark
-- refund sent" surviving on this screen even after the Attendance Refund
-- Center was fixed: two entirely independent implementations of "what is a
-- host allowed to act on", only one of which got fixed.

-- ---------------------------------------------------------------------------
-- get_host_refund_claims(): p_event_id becomes optional. NULL means "every
-- claim across every event the caller hosts" (the Account-level queue);
-- given, scopes to one event exactly as before (Attendance's own call site
-- is unchanged — same name, same first positional argument). An admin
-- (profiles.role = 'admin') sees every organizer's claims, matching the
-- privilege the old client-side loadRefundQueue() granted admins via
-- `s.accountType === 'admin'` — now enforced server-side instead of by a
-- client-trusted flag. event_id/event_name are added to the payload so the
-- Account-level queue can label each row without its own separate events
-- fetch.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_host_refund_claims(p_event_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin boolean;
  v_is_host boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT EXISTS(SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin') INTO v_is_admin;

  IF p_event_id IS NOT NULL AND NOT v_is_admin THEN
    SELECT EXISTS (
      SELECT 1 FROM events e
      JOIN organizers o ON o.id = e.organizer_id
      WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    ) INTO v_is_host;
    IF NOT v_is_host THEN
      RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
    END IF;
  END IF;

  -- A caller with no organizer at all (and not admin) gets an empty queue,
  -- not an error — mirrors the old client's own "no orgs -> empty" gate,
  -- just enforced here instead of trusted from the client.
  IF p_event_id IS NULL AND NOT v_is_admin
     AND NOT EXISTS (SELECT 1 FROM organizers o WHERE o.owner_id = auth.uid() OR o.user_id = auth.uid()) THEN
    RETURN jsonb_build_object('success', true, 'claims', '[]'::jsonb);
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
        'guest_name', coalesce(p.display_name, ''),
        'event_id', e.id,
        'event_name', e.name
      ) ORDER BY rc.created_at ASC), '[]'::jsonb)
      -- INNER JOINs only: a row can only ever come back if claim -> booking
      -- -> event -> an organizer the caller owns (or admin) all resolve.
      FROM refund_claims rc
      JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
      JOIN events e ON e.id = b.event_id
      JOIN organizers o ON o.id = e.organizer_id
      LEFT JOIN profiles p ON p.id = b.user_id
      WHERE (p_event_id IS NULL OR e.id = p_event_id)
        AND (v_is_admin OR o.owner_id = auth.uid() OR o.user_id = auth.uid())
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_host_refund_claims(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_host_refund_claims(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- mark_refund_sent(): task C. Adds the amount_vnd > 0 guard, renames the
-- "no valid destination" business code to the stable name this ticket
-- specifies (REFUND_DESTINATION_REQUIRED — was NO_DESTINATION_SELECTED,
-- updated at every call site in the same pass), and returns the complete,
-- current claim row on every path (the fresh transition AND the idempotent
-- repeat-tap path) so the client can replace its local copy by id directly
-- instead of trusting its own pre-mutation view of the claim.
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
    RETURN jsonb_build_object('success', true, 'status', v_claim.status, 'already', true, 'claim', to_jsonb(v_claim));
  END IF;
  IF v_claim.status NOT IN ('owed', 'disputed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;
  IF v_claim.amount_vnd IS NULL OR v_claim.amount_vnd <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_AMOUNT');
  END IF;

  -- Never allow this transition without a real, persisted recipient
  -- snapshot — a bare selected_destination_id with no valid snapshot
  -- content is treated the same as having none at all.
  IF v_claim.selected_destination_id IS NULL OR NOT goc_refund_snapshot_valid(v_claim.recipient_snapshot) THEN
    RETURN jsonb_build_object('success', false, 'error', 'REFUND_DESTINATION_REQUIRED');
  END IF;

  UPDATE refund_claims
  SET status = 'host_marked_sent',
      host_marked_at = now(),
      note = CASE WHEN v_note <> ''
                  THEN COALESCE(note || E'\n', '') || 'Host note: ' || v_note
                  ELSE note END
  WHERE id = p_claim_id
  RETURNING * INTO v_claim;

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

  RETURN jsonb_build_object('success', true, 'status', 'host_marked_sent', 'claim', to_jsonb(v_claim));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_refund_sent(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_refund_sent(uuid, text) TO authenticated;
