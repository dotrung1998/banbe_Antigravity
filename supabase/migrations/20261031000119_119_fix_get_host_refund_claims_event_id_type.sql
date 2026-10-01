-- Migration: fix get_host_refund_claims()'s p_event_id parameter type —
-- CONFIRMED broken by a real authenticated integration test against the
-- deployed project (tests/e2e/refund-queue-type-mismatch.integration.mjs),
-- not assumed. This is the actual cause of the new "Could not load the
-- refund queue. Please try again." report.
--
-- Root cause: migrations 077/078 declared `p_event_id uuid`, but
-- `events.id` is `text` (migration 001 — events use human-readable slugs
-- like "test-s-ki-n-8444c8", never real UUIDs; every OTHER event-scoped
-- RPC in this entire schema — is_event_host, create_event_invites,
-- finalize_event_photo_count, etc. — correctly takes `p_event_id text`;
-- this was the one place that didn't). Two confirmed, independent failure
-- modes from the same typo:
--   1. Verifications.jsx's loadRefundQueue()/AppState+Payments.swift's
--      loadRefundQueue() call with `p_event_id: null` (the account-wide
--      queue). Even though the plpgsql-level `IF p_event_id IS NOT NULL`
--      branch is genuinely skipped at NULL, the function's own final
--      SELECT has a single SQL WHERE clause — `(p_event_id IS NULL OR
--      e.id = p_event_id)` — that Postgres must type-check as ONE
--      expression tree regardless of the OR's short-circuit VALUE at
--      runtime. `text = uuid` has no operator, so this raised a real
--      42883 "operator does not exist: text = uuid" on EVERY call, NULL
--      or not — confirmed live (same error code/message captured by the
--      test above). This was never visibly reported before THIS session's
--      prior pass added real error surfacing to loadRefundQueue (it used
--      to silently render an empty queue on any error) — the user is only
--      seeing it now because the error is finally visible, not because
--      anything newly broke.
--   2. Attendance.jsx's loadRefundCenter()/AttendanceView's equivalent
--      call with a REAL event id (e.g. "test-s-ki-n-8444c8") — fails even
--      earlier, at PostgREST's own parameter-binding layer, with 22P02
--      "invalid input syntax for type uuid", since that string isn't a
--      valid UUID literal at all.
--
-- Fix: redeclare with the correct `text` type (same convention every other
-- event-scoped RPC already uses). Parameter type changes create a NEW
-- Postgres function signature — DROP the old `(uuid)` overload explicitly
-- so it doesn't linger as a dead/conflicting overload for PostgREST's own
-- RPC routing. Function BODY is otherwise byte-for-byte identical to
-- migration 078's version — no other behavior changes, no ownership/RLS
-- loosening.
DROP FUNCTION IF EXISTS public.get_host_refund_claims(uuid);

CREATE OR REPLACE FUNCTION public.get_host_refund_claims(p_event_id text DEFAULT NULL)
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
      -- Self-booking (guest == host, same auth.uid() on both sides) is
      -- NOT excluded here, by design — ownership is checked on the
      -- ORGANIZER, never on whether the claim's own guest_user_id differs
      -- from the caller; a host who booked and cancelled their own event
      -- still owes themselves the same real refund.
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

REVOKE ALL ON FUNCTION public.get_host_refund_claims(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_host_refund_claims(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_host_refund_claims(text) TO authenticated;
