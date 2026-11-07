-- Requirement: admin can re-open a RESOLVED dispute's full detail (decision,
-- reason, chat transcript) from the "Đã xử lý" list for up to 72h after
-- resolution (see purge_after in migration 033), but:
--   (a) never past the 72h hard purge, and
--   (b) never for the guest or organizer, only public.is_platform_admin().
--
-- Two gaps found investigating this (see .claude/notes/04-admin-escalation.md
-- and 05-notify-retention.md for the fixes this migration builds on):
--
-- 1. dispute_threads_select / dispute_messages_select (migration 033) let
--    the guest/organizer read a dispute_threads row regardless of
--    resolved_at — so within the 72h grace window (before the purge cron
--    deletes the row), the guest/organizer could already read their own
--    resolved dispute's chat transcript via a direct table query, same as
--    an open one. Fine for an open dispute; wrong for a resolved one, which
--    this ticket requires to be admin-only. Tightened below: once
--    resolved_at is set, only is_platform_admin() may read it.
--
-- 2. resync_dispute_thread() (migration 043) does
--    `INSERT ... ON CONFLICT (booking_id) DO UPDATE ... WHERE resolved_at
--    IS NULL` — that WHERE only guards the UPDATE branch of the upsert. If
--    a booking's dispute_threads row has already been hard-deleted by
--    purge_resolved_dispute_threads() (past the 72h window), there is no
--    conflicting row, so the INSERT branch fires unconditionally and
--    silently resurrects a brand-new, empty, unresolved-looking thread row
--    for an already-resolved booking — defeating the purge. This was
--    reachable from the client: loadDisputeChat() (src/state/GocContext.jsx)
--    calls resync_dispute_thread() automatically whenever a thread read
--    comes back empty, which is indistinguishable from "purged" at the
--    client. Fixed below by refusing to resync once the booking itself
--    (bookings.dispute_resolved_at, a permanent column — never purged) is
--    marked resolved; the self-heal use case this RPC exists for only ever
--    applies to a currently open dispute.

-- --- 1. Admin-only reads of a resolved dispute thread/chat ---------------
DROP POLICY IF EXISTS "dispute_threads_select" ON public.dispute_threads;
CREATE POLICY "dispute_threads_select" ON public.dispute_threads FOR SELECT TO authenticated USING (
  public.is_platform_admin()
  OR (
    resolved_at IS NULL
    AND (
      guest_id = auth.uid()
      OR EXISTS (SELECT 1 FROM public.organizers o WHERE o.id = dispute_threads.organizer_id
                 AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
    )
  )
);

DROP POLICY IF EXISTS "dispute_messages_select" ON public.dispute_messages;
CREATE POLICY "dispute_messages_select" ON public.dispute_messages FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.dispute_threads t WHERE t.id = dispute_messages.dispute_thread_id
    AND (
      public.is_platform_admin()
      OR (
        t.resolved_at IS NULL
        AND (
          t.guest_id = auth.uid()
          OR EXISTS (SELECT 1 FROM public.organizers o WHERE o.id = t.organizer_id
                     AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
        )
      )
    )
  )
);

-- --- 2. resync_dispute_thread() must not resurrect a purged/resolved case ---
CREATE OR REPLACE FUNCTION public.resync_dispute_thread(p_booking uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_authorized boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  -- bookings.dispute_resolved_at is permanent (never purged) — the
  -- authoritative "is this dispute already decided" check, independent of
  -- whether the ephemeral dispute_threads row itself still exists.
  IF v_b.dispute_resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'DISPUTE_ALREADY_RESOLVED');
  END IF;

  SELECT v_b.user_id = auth.uid() OR EXISTS(
    SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_b.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR public.is_platform_admin() INTO v_authorized;
  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  INSERT INTO dispute_threads (booking_id, event_id, guest_id, organizer_id)
  VALUES (v_b.id, v_b.event_id, v_b.user_id, (SELECT organizer_id FROM events WHERE id = v_b.event_id))
  ON CONFLICT (booking_id) DO UPDATE SET
    guest_id = EXCLUDED.guest_id,
    organizer_id = EXCLUDED.organizer_id
  WHERE dispute_threads.resolved_at IS NULL;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.resync_dispute_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.resync_dispute_thread(uuid) TO authenticated;
