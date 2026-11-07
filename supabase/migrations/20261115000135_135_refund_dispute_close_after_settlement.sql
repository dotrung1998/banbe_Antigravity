-- Migration 135: a refund dispute stays open until the refund is settled, and
-- can only be closed after that.
--
-- Additive on 129 to 134. The flow this enforces:
--   1. the host marks the refund sent        (refund_claims.status host_marked_sent)
--   2. the goer confirms it was received      (status guest_confirmed)
--   3. only then can either party close the dispute chat.
--
-- Two things in 129/130 contradicted that:
--   * goc_stamp_refund_dispute_chat_conclusions() concluded (made read-only,
--     started the 7 day purge) any refund dispute the moment its claim left
--     'disputed', i.e. as soon as the host marked it sent. The chat is now only
--     concluded by an explicit close, by a waived claim, or as a safety net 7
--     days after the goer confirmed receipt without anyone pressing close.
--   * close_refund_dispute() accepted a close at any claim status. It now
--     refuses with REFUND_NOT_CONFIRMED until the claim is guest_confirmed or
--     waived. Admins are unaffected. It still writes nothing to
--     refund_claims.status.

CREATE OR REPLACE FUNCTION public.goc_stamp_refund_dispute_chat_conclusions()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int;
BEGIN
  WITH closed AS (
    UPDATE dispute_threads t
    SET resolved_at = COALESCE(t.resolved_at, now()),
        purge_after = COALESCE(t.purge_after, now() + interval '7 days'),
        resolution_kind = COALESCE(t.resolution_kind, 'refund_settled')
    WHERE t.refund_claim_id IS NOT NULL
      AND t.resolved_at IS NULL
      AND EXISTS (
        SELECT 1 FROM refund_claims rc
        WHERE rc.id = t.refund_claim_id
          AND (
            rc.dispute_closed_at IS NOT NULL
            OR rc.status::text = 'waived'
            OR (rc.status::text = 'guest_confirmed'
                AND COALESCE(rc.guest_confirmed_at, rc.created_at) < now() - interval '7 days')
          )
      )
    RETURNING t.id
  )
  SELECT count(*) INTO v_count FROM closed;
  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.goc_stamp_refund_dispute_chat_conclusions() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.goc_stamp_refund_dispute_chat_conclusions() FROM anon;
REVOKE EXECUTE ON FUNCTION public.goc_stamp_refund_dispute_chat_conclusions() FROM authenticated;

CREATE OR REPLACE FUNCTION public.close_refund_dispute(p_claim_id uuid, p_note text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t dispute_threads%ROWTYPE;
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_role text;
  v_note text := left(trim(COALESCE(p_note, '')), 500);
  v_recipients uuid[];
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;
  SELECT * INTO v_org FROM organizers WHERE id = v_event.organizer_id;

  -- Exactly the two parties send_refund_dispute_message() already accepts,
  -- read off the CLAIM's own booking rather than off a dispute_threads row
  -- so a thread that a stale/mislinked organizer_id would hide can't be used
  -- to lock a real party out of closing their own dispute. banbe admins are
  -- admitted too — they already have admin chat access on every thread.
  IF v_booking.user_id = auth.uid() THEN
    v_role := 'guest';
  ELSIF EXISTS (SELECT 1 FROM organizers o
                 WHERE o.id = v_event.organizer_id
                   AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    v_role := 'organizer';
  ELSIF public.is_platform_admin() THEN
    v_role := 'admin';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  SELECT * INTO v_t FROM dispute_threads WHERE refund_claim_id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_DISPUTED');
  END IF;

  -- An escalated PAYMENT dispute (host escalated to banbe) keeps its
  -- admin-only resolution in resolve_dispute() — migrations 043/046 closed
  -- that off deliberately, and closing it from a participant's own screen
  -- would quietly reintroduce exactly what those migrations removed.
  IF v_t.kind <> 'refund' OR v_t.booking_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADMIN_RESOLUTION_REQUIRED');
  END IF;

  -- Idempotent: a second tap, or a retry after a dropped response, returns
  -- the SAME answer without touching resolved_at/purge_after. Re-stamping
  -- would silently extend the 7-day retention window every time.
  IF v_t.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'already', true,
      'dispute_thread_id', v_t.id,
      'resolved_at', v_t.resolved_at,
      'purge_after', v_t.purge_after,
      'dispute_closed_at', v_claim.dispute_closed_at
    );
  END IF;

  -- The dispute can only be closed once the refund itself has been settled
  -- through the normal flow: the host marks it sent, then the goer confirms it
  -- was received (status 'guest_confirmed'), or the claim was waived. Closing
  -- still never WRITES the status; it only refuses to run before this point.
  -- Platform admins keep their existing ability to close.
  IF v_role <> 'admin' AND v_claim.status::text NOT IN ('guest_confirmed', 'waived') THEN
    RETURN jsonb_build_object('success', false, 'error', 'REFUND_NOT_CONFIRMED',
                              'claim_status', v_claim.status);
  END IF;

  -- 1. The chat goes read-only and gets its retention window. purge_after is
  --    7 days from THIS close, matching migration 129's RETENTION.
  UPDATE dispute_threads
  SET resolved_at = now(),
      purge_after = now() + interval '7 days',
      resolution_kind = 'refund_closed_by_party',
      resolution_note = v_note
  WHERE id = v_t.id
  RETURNING * INTO v_t;

  -- 2. The claim records that its dispute was closed — and nothing else.
  --    refund_claims.status is deliberately NOT touched (see the header).
  UPDATE refund_claims
  SET dispute_closed_at = now(),
      dispute_closed_by_role = v_role
  WHERE id = p_claim_id;

  -- 3. A system line in the transcript itself, so the export shows the
  --    closure in the same place the argument happened rather than only as
  --    a column in an export header. sender_role 'system' — neither party
  --    is made to appear to have said this.
  INSERT INTO dispute_messages (dispute_thread_id, sender_role, body)
  VALUES (
    v_t.id, 'system',
    CASE WHEN v_role = 'guest'
      THEN 'Dispute closed by the guest and marked as completed.'
      WHEN v_role = 'organizer'
      THEN 'Dispute closed by the organizer and marked as completed.'
      ELSE 'Dispute closed and marked as completed.' END
  );

  -- 4. Tell the other side. Same recipient shape as migration 129's
  --    send_refund_dispute_message(): the guest and both organizer accounts,
  --    minus the sender. data carries claim_id so the iOS deep-link can route
  --    straight to the right booking conversation's dispute card, and
  --    booking_id is the CLAIM's underlying booking (the thread's own
  --    booking_id is NULL for refund disputes — see migration 129).
  SELECT array_agg(recipient) INTO v_recipients FROM (
    SELECT v_booking.user_id AS recipient
    UNION
    SELECT o.owner_id FROM organizers o WHERE o.id = v_event.organizer_id
    UNION
    SELECT o.user_id FROM organizers o WHERE o.id = v_event.organizer_id
  ) r
  WHERE recipient IS NOT NULL AND recipient <> auth.uid();

  IF v_recipients IS NOT NULL THEN
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    SELECT recipient,
           'refund_dispute_closed',
           'Tranh chấp hoàn tiền đã kết thúc',
           'Tranh chấp khoản hoàn '
             || replace(to_char(v_claim.amount_vnd, 'FM999G999G999'), ',', '.')
             || '₫ cho ' || COALESCE(v_event.name, 'sự kiện')
             || ' đã được đóng. Bản ghi vẫn đọc được trong 7 ngày.',
           jsonb_build_object(
             'claim_id', v_claim.id,
             'booking_id', v_booking.id,
             'event_id', v_event.id,
             'amount_vnd', v_claim.amount_vnd,
             'dispute_thread_id', v_t.id
           )
    FROM unnest(v_recipients) AS r(recipient);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'already', false,
    'dispute_thread_id', v_t.id,
    'resolved_at', v_t.resolved_at,
    'purge_after', v_t.purge_after,
    'dispute_closed_at', now(),
    'closed_by_role', v_role
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.close_refund_dispute(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.close_refund_dispute(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_refund_dispute(uuid, text) TO authenticated;
