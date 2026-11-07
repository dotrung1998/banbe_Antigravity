-- Migration: fix a regression in the previous fix, and a pre-existing bug
-- in resolve_dispute() that the previous fix's error banner exposed but
-- couldn't repair.
--
-- ---------------------------------------------------------------------------
-- WHY 042'S SELF-HEAL COULD NEVER ACTUALLY FIRE FOR AN ALREADY-DISPUTED
-- BOOKING (e.g. ART10025)
-- ---------------------------------------------------------------------------
-- Migration 042 made reject_payment()/escalate_payment_dispute()'s
-- `INSERT ... ON CONFLICT (booking_id) DO UPDATE` re-link a stale
-- dispute_threads row — but BOTH of those functions refuse to run at all
-- once payment_state = 'disputed' (`IF v_from NOT IN ('pending_verification',
-- 'holding') THEN RETURN ... INVALID_STATE`). A booking already sitting on
-- the admin's Disputes.jsx screen (banbetestadmin@gmail.com's exact
-- situation) is BY DEFINITION already 'disputed' — so there was never any
-- way to actually invoke the self-heal 042 added. The result: the chat
-- correctly started reporting the RLS denial as a real error instead of a
-- silent "No messages yet." (as intended), but nothing the UI offered could
-- fix it — a regression in outcome even though the error-surfacing itself
-- was correct.
--
-- resolve_dispute() is the only RPC that is actually reachable while
-- payment_state = 'disputed' — so it is the only place left that can repair
-- this. Extended here to also re-link dispute_threads.organizer_id/guest_id
-- (same ON CONFLICT... no, this is an UPDATE not an INSERT — added directly
-- to the existing "close out the temporary dispute chat" UPDATE) from the
-- booking's own current, correct values before marking it resolved.
--
-- ---------------------------------------------------------------------------
-- THE SEPARATE "buttons do nothing" BUG (resolveDispute, not resolve_dispute)
-- ---------------------------------------------------------------------------
-- Not this migration's fix — client-side only, see GocContext.jsx's
-- resolveDispute / AppState+Payments.swift's resolveDispute: the
-- confirmation-email fetch to api/dispute-resolved-email.js used to be
-- awaited INSIDE the same try block as the resolve_dispute() RPC call,
-- BEFORE disputeBusy was cleared and loadDisputes()/loadAdminDisputes() ran.
-- That endpoint (puppeteer-core + @sparticuz/chromium) has never been
-- load-tested end to end (see 05-notify-retention.md) — a slow cold start
-- or a hang there silently blocked every visible sign that the resolution
-- had already succeeded server-side, which is indistinguishable from "the
-- button does nothing." Fixed by decoupling: the email send is now
-- fire-and-forget, after the UI-critical state refresh, on both platforms.
CREATE OR REPLACE FUNCTION public.resolve_dispute(
  p_booking uuid, p_uphold boolean, p_resolution text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_note text := left(trim(COALESCE(p_resolution, '')), 400);
  v_result jsonb;
  v_thread_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADMIN_ONLY');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  IF v_b.payment_state <> 'disputed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_DISPUTED', 'state', v_b.payment_state);
  END IF;

  UPDATE bookings SET dispute_resolved_at = now(), dispute_resolution = v_note
  WHERE id = p_booking;

  IF p_uphold THEN
    v_result := verify_payment(p_booking, 'admin', 'admin',
                               jsonb_build_object('dispute_resolution', v_note));
  ELSE
    UPDATE bookings SET
      payment_state = 'expired', status = 'expired', verify_due_at = NULL
    WHERE id = p_booking;
    PERFORM log_payment_event(p_booking, 'dispute_resolved_against_buyer',
                              'disputed', 'expired', auth.uid(), 'admin', NULL, NULL,
                              jsonb_build_object('resolution', v_note));
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (v_b.user_id, 'dispute_resolved', 'Kết quả xem xét thanh toán',
            'banbe đã xem xét và không xác nhận được khoản thanh toán này. Chỗ đã được mở lại.',
            jsonb_build_object('booking_id', p_booking, 'resolution', v_note));
    v_result := jsonb_build_object('success', true, 'state', 'expired');
  END IF;

  UPDATE organizers o SET disputes_open = GREATEST(COALESCE(o.disputes_open, 1) - 1, 0)
  FROM events e WHERE e.id = v_b.event_id AND o.id = e.organizer_id;

  -- Close out the temporary dispute chat — soft-deleted now (resolved_at
  -- set, hidden from both parties by every client query from here on),
  -- hard-purged later by purge_resolved_dispute_threads(). Also re-links
  -- guest_id/organizer_id from the booking's own current values: this is
  -- the only RPC still reachable once payment_state = 'disputed', so it is
  -- the last chance to repair a row a stale INSERT ever mislinked before
  -- it's gone for good — the transcript email (api/dispute-resolved-email.js)
  -- reads dispute_messages via this same thread right after this call.
  UPDATE dispute_threads SET
    guest_id = v_b.user_id,
    organizer_id = (SELECT organizer_id FROM events WHERE id = v_b.event_id),
    resolved_at = now(),
    resolution_kind = CASE WHEN p_uphold THEN 'ticket_issued' ELSE 'cancelled' END,
    resolution_note = v_note,
    purge_after = now() + interval '72 hours'
  WHERE booking_id = p_booking;

  -- The one line the ordinary thread gets, per the request — everything
  -- else about the dispute stays out of the guest's permanent chat history.
  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, NULL,
            'Tranh chấp đã được giải quyết. Email xác nhận đã được gửi cho cả hai bên.'
            || ' / Dispute resolved. Confirmation email sent to both parties.',
            'system');
  END IF;

  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.resolve_dispute(uuid, boolean, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_dispute(uuid, boolean, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- resync_dispute_thread() — the actual, generally-reachable fix for a
-- mislinked dispute_threads row. resolve_dispute()'s repair above only ever
-- fires at the moment a dispute is closed, which is too late to unblock the
-- chat while it's still open (ART10025's exact situation: still 'disputed',
-- not yet resolved). reject_payment()/escalate_payment_dispute() can't be
-- re-run to repair it either — both refuse once payment_state = 'disputed'.
-- This has no state restriction at all: callable whether the booking is
-- holding, pending_verification, or disputed, by the guest, the event's
-- organizer, or an admin — the same three parties dispute_threads_select
-- already trusts. The client calls this once, automatically, the moment
-- loadDisputeChat notices a thread it should be able to see isn't there
-- (see GocContext.jsx/AppState+Payments.swift), then retries the load.
-- ---------------------------------------------------------------------------
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
