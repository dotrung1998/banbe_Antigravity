-- Migration 138: every dispute is its own record (rounds), nothing is overwritten.
--
-- Until now dispute_threads had ONE row per refund claim, and dispute_refund()
-- re-disputing a claim REOPENED that row (ON CONFLICT DO UPDATE ... resolved_at =
-- NULL), so a second dispute landed in the first one's chat and a closed
-- transcript was overwritten.
--
-- Now:
--   * dispute_threads allows several rows per claim, but only ONE OPEN at a time
--     (partial unique index);
--   * dispute_refund() starts a NEW thread for a new dispute and resets the claim's
--     per-dispute fields (closed flags, day 6 reminder), leaving the earlier thread,
--     its messages and its files exactly as they were until their own 7 day purge;
--   * the claim based RPCs (open chat, send, attach, close, delete my copy, lookup)
--     act on the claim's CURRENT (newest) thread;
--   * the closure facts live on the thread too (closed_at, closed_by_role), so the
--     list shows each round's own closure;
--   * get_refund_dispute_rounds() lists the earlier, still retained rounds so the
--     app can show them next to the current one. Earlier rounds are read through the
--     normal participant RLS on dispute_threads / dispute_messages.

ALTER TABLE public.dispute_threads
  ADD COLUMN IF NOT EXISTS closed_at timestamptz,
  ADD COLUMN IF NOT EXISTS closed_by_role text;

-- Backfill the thread level closure from the claim for threads closed so far.
UPDATE public.dispute_threads t
SET closed_at = COALESCE(rc.dispute_closed_at, t.resolved_at),
    closed_by_role = rc.dispute_closed_by_role
FROM public.refund_claims rc
WHERE rc.id = t.refund_claim_id AND t.resolved_at IS NOT NULL AND t.closed_at IS NULL;

DROP INDEX IF EXISTS public.dispute_threads_refund_claim_uniq;
CREATE UNIQUE INDEX IF NOT EXISTS dispute_threads_one_open_per_claim
  ON public.dispute_threads (refund_claim_id)
  WHERE refund_claim_id IS NOT NULL AND resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS dispute_threads_claim_created_idx
  ON public.dispute_threads (refund_claim_id, created_at DESC) WHERE refund_claim_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.dispute_refund(p_claim_id uuid, p_reason text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_recipient uuid;
  v_reason text := trim(p_reason);
  v_thread_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  IF NOT FOUND OR v_booking.user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_claim.status = 'disputed' THEN
    RETURN jsonb_build_object('success', true, 'status', v_claim.status, 'already', true);
  END IF;
  IF v_claim.status NOT IN ('owed', 'host_marked_sent') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;
  SELECT * INTO v_org FROM organizers WHERE id = v_event.organizer_id;
  v_recipient := COALESCE(v_org.owner_id, v_org.user_id);

  UPDATE refund_claims
  SET status = 'disputed',
      disputed_at = now(),
      host_response_due_at = now() + interval '48 hours',
      dispute_flagged_at = NULL,
      note = CASE WHEN v_reason <> ''
                  THEN COALESCE(note || E'\n', '') || 'Guest dispute: ' || v_reason
                  ELSE note END
  WHERE id = p_claim_id;

  -- The temporary chat, opened here rather than lazily by the UI so it exists
  -- for the organizer too the moment the dispute does. booking_id is
  -- deliberately NULL — this thread is keyed by the refund claim, so a booking
  -- that ALSO has a payment dispute keeps both chats instead of colliding on
  -- dispute_threads_booking_id_uniq.
  --
  -- DO UPDATE (not DO NOTHING) is what makes a re-dispute inside the 7-day
  -- retention window reopen the chat instead of silently dropping the goer into
  -- a read-only one they can no longer reply in: clearing resolved_at/purge_after
  -- moves it straight back to "open" for both parties and for
  -- get_my_dispute_chats().
  -- A NEW dispute is a NEW thread. An open one for this claim is reused (a double
  -- tap), but a closed one is never reopened: it keeps its messages and files for
  -- its own retention window.
  SELECT id INTO v_thread_id FROM dispute_threads
  WHERE refund_claim_id = p_claim_id AND resolved_at IS NULL
  ORDER BY created_at DESC LIMIT 1;
  IF v_thread_id IS NULL THEN
    INSERT INTO dispute_threads (booking_id, refund_claim_id, kind, event_id, guest_id, organizer_id)
    VALUES (NULL, p_claim_id, 'refund', v_event.id, v_booking.user_id, v_event.organizer_id)
    RETURNING id INTO v_thread_id;
  END IF;
  -- Per-dispute claim fields start fresh for the new round.
  UPDATE refund_claims
  SET dispute_closed_at = NULL, dispute_closed_by_role = NULL, dispute_autoclose_reminded_at = NULL
  WHERE id = p_claim_id;

  IF v_recipient IS NOT NULL AND v_claim.last_flagged_at IS NULL THEN
    UPDATE organizers SET disputes_open = COALESCE(disputes_open, 0) + 1 WHERE id = v_org.id;
    UPDATE refund_claims SET last_flagged_at = now() WHERE id = p_claim_id;
  END IF;

  IF v_recipient IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_recipient, 'refund_disputed',
      'Khách báo chưa nhận được hoàn tiền',
      'Khách báo chưa nhận được ' || replace(to_char(v_claim.amount_vnd, 'FM999G999G999'), ',', '.')
        || '₫ cho ' || COALESCE(v_event.name, 'sự kiện') || '.'
        || (CASE WHEN v_reason <> '' THEN ' Lý do: ' || v_reason ELSE '' END),
      jsonb_build_object('claim_id', v_claim.id, 'booking_id', v_booking.id, 'event_id', v_event.id, 'amount_vnd', v_claim.amount_vnd, 'reason', v_reason, 'dispute_thread_id', v_thread_id)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'disputed', 'dispute_thread_id', v_thread_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.dispute_refund(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.dispute_refund(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.send_refund_dispute_message(p_refund_claim_id uuid, p_body text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t dispute_threads%ROWTYPE;
  v_b bookings%ROWTYPE;
  v_body text := left(trim(COALESCE(p_body, '')), 2000);
  v_role text;
  v_msg_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF v_body = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMPTY_MESSAGE');
  END IF;

  SELECT * INTO v_t FROM dispute_threads WHERE refund_claim_id = p_refund_claim_id ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_DISPUTED');
  END IF;
  IF v_t.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'DISPUTE_RESOLVED');
  END IF;

  IF v_t.guest_id = auth.uid() THEN
    v_role := 'guest';
  ELSIF EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_t.organizer_id
                AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    v_role := 'organizer';
  ELSIF public.is_platform_admin() THEN
    v_role := 'admin';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  INSERT INTO dispute_messages (dispute_thread_id, sender_id, sender_role, body)
  VALUES (v_t.id, auth.uid(), v_role, v_body)
  RETURNING id INTO v_msg_id;

  -- Same notify-the-other-side shape as migration 050's send_dispute_message:
  -- the guest and both accounts an organizer row resolves to, minus the
  -- sender and any NULLs.
  --
  -- `booking_id` here is the REFUND thread's own null, deliberately replaced
  -- by the underlying booking's id: openNotification()'s existing
  -- `dispute_message` branch (both platforms) navigates purely off
  -- data.booking_id, so shipping the null would drop the tap on the floor.
  -- refund_claim_id + dispute_thread_id travel alongside it so that branch
  -- can route to the Messages-side dispute entry instead of the generic
  -- container screen.
  SELECT * INTO v_b FROM bookings
  WHERE id = (SELECT COALESCE(booking_id, reservation_id) FROM refund_claims WHERE id = p_refund_claim_id);

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  SELECT recipient, 'dispute_message', 'Tin nhắn mới về tranh chấp',
         v_body, jsonb_build_object(
           'booking_id', v_b.id,
           'refund_claim_id', p_refund_claim_id,
           'dispute_thread_id', v_t.id,
           'message_id', v_msg_id
         )
  FROM (
    SELECT v_t.guest_id AS recipient
    UNION
    SELECT o.owner_id FROM organizers o WHERE o.id = v_t.organizer_id
    UNION
    SELECT o.user_id FROM organizers o WHERE o.id = v_t.organizer_id
  ) recipients
  WHERE recipient IS NOT NULL AND recipient <> auth.uid();

  RETURN jsonb_build_object('success', true, 'message_id', v_msg_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.send_refund_dispute_message(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_refund_dispute_message(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.send_refund_dispute_attachment(
  p_refund_claim_id uuid,
  p_body text,
  p_attachment_path text,
  p_attachment_type text,
  p_attachment_width integer DEFAULT NULL,
  p_attachment_height integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t dispute_threads%ROWTYPE;
  v_b bookings%ROWTYPE;
  v_type text := lower(trim(COALESCE(p_attachment_type, '')));
  v_path text := trim(COALESCE(p_attachment_path, ''));
  v_body text := left(trim(COALESCE(p_body, '')), 2000);
  v_role text;
  v_msg_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF v_path = '' OR v_type = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_ATTACHMENT');
  END IF;
  -- Same allow-list the bucket itself enforces, checked here too so an
  -- unsupported type is refused before a message row is written.
  IF v_type NOT IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf') THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNSUPPORTED_TYPE');
  END IF;

  SELECT * INTO v_t FROM dispute_threads WHERE refund_claim_id = p_refund_claim_id ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_DISPUTED');
  END IF;
  IF v_t.kind <> 'refund' OR v_t.booking_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADMIN_RESOLUTION_REQUIRED');
  END IF;
  -- The closure check that makes "the other party closed it while my photo
  -- was uploading" end the same way it ends for a typed message: refused,
  -- with an error the client can explain rather than retry.
  IF v_t.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'DISPUTE_RESOLVED');
  END IF;
  -- The path must be inside THIS dispute's own prefix.
  IF split_part(v_path, '/', 1) <> v_t.id::text THEN
    RETURN jsonb_build_object('success', false, 'error', 'PATH_NOT_IN_THREAD');
  END IF;

  IF v_t.guest_id = auth.uid() THEN
    v_role := 'guest';
  ELSIF EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_t.organizer_id
                AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    v_role := 'organizer';
  ELSIF public.is_platform_admin() THEN
    v_role := 'admin';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- An attachment-only message is supported, exactly as it is in the
  -- ordinary chat: the row needs a non-NULL body, so the same placeholder
  -- that chat writes for a file/photo send is used here. It is a caption,
  -- never a claim about what the file shows.
  IF v_body = '' THEN
    v_body := CASE WHEN v_type LIKE 'image/%'
      THEN 'Sent a photo'
      ELSE 'Sent a file' END;
  END IF;

  INSERT INTO dispute_messages (
    dispute_thread_id, sender_id, sender_role, body,
    attachment_path, attachment_type, attachment_width, attachment_height
  )
  VALUES (v_t.id, auth.uid(), v_role, v_body, v_path, v_type, p_attachment_width, p_attachment_height)
  RETURNING id INTO v_msg_id;

  -- Same notify-the-other-side shape as migration 129's
  -- send_refund_dispute_message(), including the substituted booking_id that
  -- openNotification()'s dispute_message branch navigates by.
  SELECT * INTO v_b FROM bookings
  WHERE id = (SELECT COALESCE(booking_id, reservation_id) FROM refund_claims WHERE id = p_refund_claim_id);

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  SELECT recipient, 'dispute_message', 'Tin nhắn mới về tranh chấp',
         v_body, jsonb_build_object(
           'booking_id', v_b.id,
           'refund_claim_id', p_refund_claim_id,
           'dispute_thread_id', v_t.id,
           'message_id', v_msg_id
         )
  FROM (
    SELECT v_t.guest_id AS recipient
    UNION
    SELECT o.owner_id FROM organizers o WHERE o.id = v_t.organizer_id
    UNION
    SELECT o.user_id FROM organizers o WHERE o.id = v_t.organizer_id
  ) recipients
  WHERE recipient IS NOT NULL AND recipient <> auth.uid();

  RETURN jsonb_build_object(
    'success', true,
    'message_id', v_msg_id,
    'dispute_thread_id', v_t.id,
    'attachment_path', v_path
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.send_refund_dispute_attachment(uuid, text, text, text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_refund_dispute_attachment(uuid, text, text, text, integer, integer) TO authenticated;

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

  SELECT * INTO v_t FROM dispute_threads WHERE refund_claim_id = p_claim_id ORDER BY created_at DESC LIMIT 1;
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
      closed_at = now(),
      closed_by_role = v_role,
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

  SELECT * INTO v_t FROM dispute_threads WHERE refund_claim_id = p_claim_id ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
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

  SELECT * INTO v_t FROM dispute_threads WHERE refund_claim_id = p_claim_id ORDER BY created_at DESC LIMIT 1;
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
    CASE WHEN t.resolved_at IS NOT NULL THEN COALESCE(t.closed_at, rc.dispute_closed_at, t.resolved_at) END,
    CASE WHEN t.resolved_at IS NOT NULL THEN COALESCE(t.closed_by_role, rc.dispute_closed_by_role) END
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

CREATE OR REPLACE FUNCTION public.goc_stamp_refund_dispute_chat_conclusions()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int := 0;
  v_n int;
  r record;
BEGIN
  -- A. Day 6 reminder (once).
  FOR r IN
    SELECT rc.id AS claim_id, rc.amount_vnd, rc.disputed_at, t.id AS thread_id, t.guest_id, t.organizer_id,
           b.id AS booking_id, e.id AS event_id, e.name AS event_name
    FROM refund_claims rc
    JOIN dispute_threads t ON t.refund_claim_id = rc.id AND t.resolved_at IS NULL
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    WHERE rc.status::text = 'disputed'
      AND rc.dispute_closed_at IS NULL
      AND rc.dispute_autoclose_reminded_at IS NULL
      AND rc.disputed_at <= now() - interval '6 days'
      AND rc.disputed_at > now() - interval '7 days'
    FOR UPDATE OF rc
  LOOP
    UPDATE refund_claims SET dispute_autoclose_reminded_at = now() WHERE id = r.claim_id;
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    SELECT x.recipient, 'refund_dispute_autoclose_soon',
           'Tranh chấp hoàn tiền sắp tự đóng',
           'Tranh chấp khoản hoàn cho ' || COALESCE(r.event_name, 'sự kiện')
             || ' sẽ tự đóng sau 24 giờ nếu không có phản hồi. Khoản hoàn không thay đổi.',
           jsonb_build_object('claim_id', r.claim_id, 'booking_id', r.booking_id, 'event_id', r.event_id,
                              'dispute_thread_id', r.thread_id)
    FROM (
      SELECT r.guest_id AS recipient
      UNION SELECT o.owner_id FROM organizers o WHERE o.id = r.organizer_id
      UNION SELECT o.user_id FROM organizers o WHERE o.id = r.organizer_id
    ) x WHERE x.recipient IS NOT NULL;
  END LOOP;

  -- B. Auto-close after 7 days without action.
  FOR r IN
    SELECT rc.id AS claim_id, rc.amount_vnd, t.id AS thread_id, t.guest_id, t.organizer_id,
           b.id AS booking_id, e.id AS event_id, e.name AS event_name
    FROM refund_claims rc
    JOIN dispute_threads t ON t.refund_claim_id = rc.id AND t.resolved_at IS NULL
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    WHERE rc.status::text = 'disputed'
      AND rc.dispute_closed_at IS NULL
      AND rc.disputed_at <= now() - interval '7 days'
    FOR UPDATE OF rc
  LOOP
    UPDATE dispute_threads
    SET resolved_at = now(), purge_after = now() + interval '7 days',
        resolution_kind = 'refund_auto_closed', closed_at = now(), closed_by_role = 'auto'
    WHERE id = r.thread_id;
    UPDATE refund_claims SET dispute_closed_at = now(), dispute_closed_by_role = 'auto' WHERE id = r.claim_id;
    INSERT INTO dispute_messages (dispute_thread_id, sender_role, body)
    VALUES (r.thread_id, 'system', 'Dispute closed automatically after 7 days without action.');
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    SELECT x.recipient, 'refund_dispute_closed',
           'Tranh chấp hoàn tiền đã tự đóng',
           'Tranh chấp khoản hoàn cho ' || COALESCE(r.event_name, 'sự kiện')
             || ' đã tự đóng sau 7 ngày. Bản ghi vẫn đọc được trong 7 ngày.',
           jsonb_build_object('claim_id', r.claim_id, 'booking_id', r.booking_id, 'event_id', r.event_id,
                              'amount_vnd', r.amount_vnd, 'dispute_thread_id', r.thread_id)
    FROM (
      SELECT r.guest_id AS recipient
      UNION SELECT o.owner_id FROM organizers o WHERE o.id = r.organizer_id
      UNION SELECT o.user_id FROM organizers o WHERE o.id = r.organizer_id
    ) x WHERE x.recipient IS NOT NULL;
    v_count := v_count + 1;
  END LOOP;

  -- C. Conclusions (migration 135 rules, unchanged).
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
  SELECT count(*) INTO v_n FROM closed;
  RETURN v_count + v_n;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.goc_stamp_refund_dispute_chat_conclusions() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.goc_stamp_refund_dispute_chat_conclusions() FROM anon;
REVOKE EXECUTE ON FUNCTION public.goc_stamp_refund_dispute_chat_conclusions() FROM authenticated;

-- Earlier, still retained rounds of a claim's disputes (newest first), for the
-- participants of that claim. The CURRENT round is get_refund_dispute_thread().
CREATE OR REPLACE FUNCTION public.get_refund_dispute_rounds(p_claim_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_head jsonb;
  v_current uuid;
BEGIN
  v_head := public.get_refund_dispute_thread(p_claim_id);
  IF COALESCE((v_head ->> 'found')::boolean, false) IS NOT TRUE
     AND (v_head ->> 'error') IS NOT NULL THEN
    RETURN jsonb_build_object('rounds', '[]'::jsonb);
  END IF;
  SELECT id INTO v_current FROM dispute_threads WHERE refund_claim_id = p_claim_id
  ORDER BY created_at DESC LIMIT 1;
  RETURN jsonb_build_object('rounds', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'dispute_thread_id', t.id,
      'opened_at', t.created_at,
      'closed_at', COALESCE(t.closed_at, t.resolved_at),
      'closed_by_role', t.closed_by_role,
      'purge_after', t.purge_after,
      'message_count', (SELECT count(*) FROM dispute_messages m WHERE m.dispute_thread_id = t.id)
    ) ORDER BY t.created_at DESC)
    FROM dispute_threads t
    WHERE t.refund_claim_id = p_claim_id
      AND t.id IS DISTINCT FROM v_current
      AND t.resolved_at IS NOT NULL
      AND (t.purge_after IS NULL OR t.purge_after > now())
      AND (
        public.is_platform_admin()
        OR EXISTS (SELECT 1 FROM organizers o WHERE o.id = t.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
        OR (t.guest_id = auth.uid() AND t.guest_deleted_at IS NULL)
      )
  ), '[]'::jsonb));
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_refund_dispute_rounds(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_refund_dispute_rounds(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_refund_dispute_rounds(uuid) TO authenticated;
