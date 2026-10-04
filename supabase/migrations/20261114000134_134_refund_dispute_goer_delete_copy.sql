-- Migration 134: the goer can close a refund dispute AND delete THEIR copy of it.
--
-- Additive on 129 to 133. Nothing here edits an applied migration.
--
-- WHAT "DELETE MY COPY" MEANS
-- A refund dispute is ONE shared record: one dispute_threads row and its
-- dispute_messages rows and storage objects, read by both the goer and the
-- host. The host is entitled to keep their record for the usual 7 days after
-- closure, so "the goer deletes it" cannot mean deleting those rows or files.
-- It is recorded as the goer's own fact on the thread:
--
--   dispute_threads.guest_deleted_at
--     "the guest removed their copy". From then on every read path
--     (RLS on the thread and its messages, the private attachment bucket, and
--     the RPCs that read them) refuses the GUEST side only. The host's access
--     and the existing 7 day purge (purge_resolved_dispute_threads, which
--     removes the rows and files for both sides) are untouched.
--
-- It moves no money (refund_claims.status is never written here), does not
-- touch the ordinary booking conversation (threads/messages are different
-- tables) and is idempotent.

ALTER TABLE public.dispute_threads
  ADD COLUMN IF NOT EXISTS guest_deleted_at timestamptz;

COMMENT ON COLUMN public.dispute_threads.guest_deleted_at IS
  'When the guest removed their own copy of this refund dispute. Hides the thread, its messages and its files from the GUEST only. The host keeps the shared record until purge_after; the purge cron still removes it for both.';

-- ---------------------------------------------------------------------------
-- 1. RLS: the guest side stops reading once its copy is deleted.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "dispute_threads_select" ON public.dispute_threads;
CREATE POLICY "dispute_threads_select" ON public.dispute_threads FOR SELECT TO authenticated USING (
  public.is_platform_admin()
  OR (
    (
      resolved_at IS NULL
      OR (refund_claim_id IS NOT NULL AND purge_after IS NOT NULL AND purge_after > now())
    )
    AND (
      (guest_id = auth.uid() AND guest_deleted_at IS NULL)
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
        (
          t.resolved_at IS NULL
          OR (t.refund_claim_id IS NOT NULL AND t.purge_after IS NOT NULL AND t.purge_after > now())
        )
        AND (
          (t.guest_id = auth.uid() AND t.guest_deleted_at IS NULL)
          OR EXISTS (SELECT 1 FROM public.organizers o WHERE o.id = t.organizer_id
                     AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
        )
      )
    )
  )
);

DROP POLICY IF EXISTS "dispute_attachments_participant_read" ON storage.objects;
CREATE POLICY "dispute_attachments_participant_read"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'dispute-attachments'
    AND EXISTS (
      SELECT 1 FROM public.dispute_threads t
      WHERE t.id::text = split_part((objects).name, '/', 1)
      AND (
        public.is_platform_admin()
        OR (
          (
            t.resolved_at IS NULL
            OR (t.refund_claim_id IS NOT NULL AND t.purge_after IS NOT NULL AND t.purge_after > now())
          )
          AND (
            (t.guest_id = auth.uid() AND t.guest_deleted_at IS NULL)
            OR EXISTS (SELECT 1 FROM public.organizers o WHERE o.id = t.organizer_id
                       AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
          )
        )
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 2. delete_my_refund_dispute_copy(): GUEST ONLY, closes first if still open,
--    idempotent, moves no money.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_my_refund_dispute_copy(p_claim_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_t dispute_threads%ROWTYPE;
  v_close jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;
  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);

  -- Only the goer of THIS claim. The host and admins keep the shared record.
  IF v_booking.user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  SELECT * INTO v_t FROM dispute_threads WHERE refund_claim_id = p_claim_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_DISPUTED');
  END IF;
  IF v_t.kind <> 'refund' OR v_t.booking_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADMIN_RESOLUTION_REQUIRED');
  END IF;

  IF v_t.guest_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'already', true,
      'dispute_thread_id', v_t.id, 'guest_deleted_at', v_t.guest_deleted_at,
      'purge_after', v_t.purge_after);
  END IF;

  IF v_t.resolved_at IS NULL THEN
    v_close := public.close_refund_dispute(p_claim_id, '');
    IF COALESCE((v_close ->> 'success')::boolean, false) IS NOT TRUE THEN
      RETURN v_close;
    END IF;
    SELECT * INTO v_t FROM dispute_threads WHERE id = v_t.id;
  END IF;

  UPDATE dispute_threads SET guest_deleted_at = now()
  WHERE id = v_t.id
  RETURNING * INTO v_t;

  RETURN jsonb_build_object('success', true, 'already', false,
    'dispute_thread_id', v_t.id, 'guest_deleted_at', v_t.guest_deleted_at,
    'resolved_at', v_t.resolved_at, 'purge_after', v_t.purge_after);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_my_refund_dispute_copy(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.delete_my_refund_dispute_copy(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_my_refund_dispute_copy(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Read RPCs redefined with the same bodies as 130 plus the guest-deleted rule.
--    get_refund_dispute_transcript() calls get_refund_dispute_thread(), so it
--    inherits the rule without being redefined.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_refund_dispute_thread(p_claim_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_t dispute_threads%ROWTYPE;
  v_role text;
  v_conv_thread uuid;
  v_guest_name text;
  v_msg_count int;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('found', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;
  SELECT * INTO v_org FROM organizers WHERE id = v_event.organizer_id;

  IF v_booking.user_id = auth.uid() THEN
    v_role := 'guest';
  ELSIF EXISTS (SELECT 1 FROM organizers o
                 WHERE o.id = v_event.organizer_id
                   AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    v_role := 'organizer';
  ELSIF public.is_platform_admin() THEN
    v_role := 'admin';
  ELSE
    RETURN jsonb_build_object('found', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- The EXISTING conversation between this guest and this event's organizer,
  -- resolved on threads' own UNIQUE (event_id, guest_id) — the dispute is
  -- shown inside it rather than beside a second copy of it.
  SELECT id INTO v_conv_thread FROM threads
  WHERE event_id = v_booking.event_id AND guest_id = v_booking.user_id;

  SELECT * INTO v_t FROM dispute_threads WHERE refund_claim_id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', false, 'reason', 'not_disputed');
  END IF;

  -- The goer deleted THEIR copy (delete_my_refund_dispute_copy). The shared
  -- thread and its messages are still here for the host, so this is purely
  -- an access rule for the guest side.
  IF v_role = 'guest' AND v_t.guest_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('found', false, 'reason', 'deleted_by_you',
                              'guest_deleted_at', v_t.guest_deleted_at);
  END IF;

  SELECT count(*) INTO v_msg_count FROM dispute_messages dm WHERE dm.dispute_thread_id = v_t.id;

  -- "Who am I talking to" is always the OTHER party, resolved server-side from
  -- the caller's own position — so the goer sees the organizer and the host
  -- sees the goer, and neither has to trust a role the client sent up.
  -- profiles has display_name only (001_core_schema), with the same 'banbe'
  -- fallback migration 129's own list uses for a blank/deleted profile.
  SELECT COALESCE(NULLIF(p.display_name, ''), 'banbe') INTO v_guest_name
  FROM profiles p WHERE p.id = v_booking.user_id;

  RETURN jsonb_build_object(
    'found', true,
    'dispute_thread_id', v_t.id,
    'refund_claim_id', p_claim_id,
    'booking_id', v_booking.id,
    'conversation_thread_id', v_conv_thread,
    'event_id', v_booking.event_id,
    'event_name', v_event.name,
    'organizer_name', v_org.name,
    'amount_vnd', v_claim.amount_vnd,
    'claim_status', v_claim.status,
    'claim_reason', v_claim.reason,
    'disputed_at', v_claim.disputed_at,
    'host_response_due_at', v_claim.host_response_due_at,
    'dispute_closed_at', v_claim.dispute_closed_at,
    'dispute_closed_by_role', v_claim.dispute_closed_by_role,
    'resolved_at', v_t.resolved_at,
    'purge_after', v_t.purge_after,
    'resolution_kind', v_t.resolution_kind,
    'resolution_note', v_t.resolution_note,
    'message_count', v_msg_count,
    'viewer_role', v_role,
    'other_name', CASE WHEN v_role = 'guest' THEN v_org.name ELSE v_guest_name END
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_refund_dispute_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_refund_dispute_thread(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_refund_dispute_for_conversation(p_thread uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_thread threads%ROWTYPE;
  v_claim_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('found', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_thread FROM threads WHERE id = p_thread;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', false, 'error', 'THREAD_NOT_FOUND');
  END IF;

  IF v_thread.guest_id IS DISTINCT FROM auth.uid()
     AND NOT EXISTS (SELECT 1 FROM organizers o
                      WHERE o.id = v_thread.organizer_id
                        AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
     AND NOT public.is_platform_admin() THEN
    RETURN jsonb_build_object('found', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  SELECT rc.id INTO v_claim_id
  FROM refund_claims rc
  JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
  JOIN dispute_threads dt ON dt.refund_claim_id = rc.id
  WHERE b.event_id = v_thread.event_id
    AND b.user_id = v_thread.guest_id
    AND dt.resolved_at IS NULL
    AND NOT (dt.guest_deleted_at IS NOT NULL AND dt.guest_id = auth.uid())
  ORDER BY rc.disputed_at DESC NULLS LAST, rc.created_at DESC
  LIMIT 1;

  -- No open dispute: fall back to the most recently closed one that is still
  -- inside its 7-day window, so the conversation can keep showing the
  -- collapsed "Dispute completed" card until the purge actually removes it.
  IF v_claim_id IS NULL THEN
    SELECT rc.id INTO v_claim_id
    FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN dispute_threads dt ON dt.refund_claim_id = rc.id
    WHERE b.event_id = v_thread.event_id
      AND b.user_id = v_thread.guest_id
      AND dt.resolved_at IS NOT NULL
      AND dt.purge_after IS NOT NULL
      AND dt.purge_after > now()
      AND NOT (dt.guest_deleted_at IS NOT NULL AND dt.guest_id = auth.uid())
    ORDER BY dt.resolved_at DESC
    LIMIT 1;
  END IF;

  IF v_claim_id IS NULL THEN
    RETURN jsonb_build_object('found', false, 'reason', 'none');
  END IF;

  RETURN public.get_refund_dispute_thread(v_claim_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_refund_dispute_for_conversation(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_refund_dispute_for_conversation(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_dispute_chats()
RETURNS TABLE (
  thread_id uuid,
  kind text,
  booking_id uuid,
  refund_claim_id uuid,
  event_id text,
  event_key text,
  event_name text,
  other_name text,
  other_avatar_url text,
  amount_vnd int,
  claim_status refund_status,
  disputed_at timestamptz,
  resolved_at timestamptz,
  purge_after timestamptz,
  last_message_at timestamptz,
  last_message_body text,
  message_count int,
  viewer_role text,
  source_booking_id uuid,
  conversation_thread_id uuid,
  dispute_closed_at timestamptz,
  dispute_closed_by_role text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  PERFORM public.goc_stamp_refund_dispute_chat_conclusions();

  RETURN QUERY
  SELECT
    t.id,
    t.kind,
    t.booking_id,
    t.refund_claim_id,
    t.event_id,
    e.key,
    e.name,
    CASE
      WHEN t.guest_id = auth.uid() THEN o.name
      WHEN t.guest_id IS NULL THEN o.name
      ELSE COALESCE(NULLIF(p.display_name, ''), 'banbe')
    END,
    CASE WHEN t.guest_id = auth.uid() THEN NULL ELSE p.avatar_url END,
    rc.amount_vnd,
    rc.status,
    rc.disputed_at,
    t.resolved_at,
    t.purge_after,
    last_msg.created_at,
    last_msg.body,
    COALESCE(msg_count.n, 0)::int,
    CASE WHEN t.guest_id = auth.uid() THEN 'guest' ELSE 'organizer' END,
    COALESCE(rc.booking_id, rc.reservation_id),
    conv.id,
    rc.dispute_closed_at,
    rc.dispute_closed_by_role
  FROM dispute_threads t
  LEFT JOIN events e ON e.id = t.event_id
  LEFT JOIN organizers o ON o.id = t.organizer_id
  LEFT JOIN profiles p ON p.id = t.guest_id
  LEFT JOIN refund_claims rc ON rc.id = t.refund_claim_id
  LEFT JOIN threads conv ON conv.event_id = t.event_id AND conv.guest_id = t.guest_id
  LEFT JOIN LATERAL (
    SELECT dm.created_at, dm.body
    FROM dispute_messages dm
    WHERE dm.dispute_thread_id = t.id
    ORDER BY dm.created_at DESC
    LIMIT 1
  ) last_msg ON true
  LEFT JOIN LATERAL (
    SELECT count(*) AS n FROM dispute_messages dm WHERE dm.dispute_thread_id = t.id
  ) msg_count ON true
  WHERE NOT (t.guest_deleted_at IS NOT NULL AND t.guest_id = auth.uid())
    AND (t.resolved_at IS NULL
         OR (t.refund_claim_id IS NOT NULL AND t.purge_after IS NOT NULL AND t.purge_after > now()))
    AND (
      t.guest_id = auth.uid()
      OR EXISTS (SELECT 1 FROM organizers oo WHERE oo.id = t.organizer_id
                 AND (oo.owner_id = auth.uid() OR oo.user_id = auth.uid()))
      OR public.is_platform_admin()
    )
  ORDER BY (t.resolved_at IS NOT NULL), last_msg.created_at DESC NULLS LAST, t.created_at DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_dispute_chats() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_dispute_chats() TO authenticated;
