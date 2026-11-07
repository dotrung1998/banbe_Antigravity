-- Migration: a temporary, ephemeral chat for an escalated dispute, separate
-- from the guest's ordinary (event, guest) thread — plus the resolution
-- flow that closes it out: a final confirmation email (with the receipt
-- image and a PDF transcript attached, sent by a separate Vercel function —
-- see api/dispute-resolved-email.js), a one-line note left in the ORDINARY
-- thread, and — after a grace window, not immediately — a hard purge of the
-- dispute thread's own rows.
--
-- Deliberately its own tables, not a tagged slice of the ordinary
-- `threads`/`messages`: those hold a guest's entire chat history with an
-- organizer, and giving anything the ability to bulk-delete rows out of
-- that table is a much bigger blast radius than a mistake here should ever
-- have. A dispute thread's own tables can be purged outright with no risk
-- to anything else.

CREATE TABLE IF NOT EXISTS public.dispute_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES public.bookings(id) ON DELETE CASCADE,
  event_id text NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  guest_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  organizer_id text REFERENCES public.organizers(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Set the moment resolve_dispute() closes it out. From then on it's
  -- read-only (send_dispute_message refuses once this is set) and hidden
  -- from both parties' UI, even though the rows themselves live on for the
  -- grace window below — this is the "soft delete" half of the purge.
  resolved_at timestamptz,
  resolution_kind text,      -- 'ticket_issued' | 'cancelled', mirrors resolve_dispute's p_uphold
  resolution_note text NOT NULL DEFAULT '',
  email_sent_at timestamptz, -- set by api/dispute-resolved-email.js once the confirmation email actually lands
  -- The hard-delete sweep (purge_resolved_dispute_threads(), below) only
  -- ever touches rows past this — a real grace window, not "purge
  -- immediately," so a bounced or failed email attachment leaves a chance
  -- to notice and retry before the transcript is gone for good.
  purge_after timestamptz
);

CREATE TABLE IF NOT EXISTS public.dispute_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dispute_thread_id uuid NOT NULL REFERENCES public.dispute_threads(id) ON DELETE CASCADE,
  sender_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  sender_role text NOT NULL, -- 'guest' | 'organizer' | 'system' — who this reads as, independent of whether the profile survives
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS dispute_messages_thread_idx ON public.dispute_messages (dispute_thread_id, created_at);
CREATE INDEX IF NOT EXISTS dispute_threads_purge_idx ON public.dispute_threads (purge_after) WHERE resolved_at IS NOT NULL;

ALTER TABLE public.dispute_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dispute_messages ENABLE ROW LEVEL SECURITY;

-- Only the guest, the event's organizer, or a platform admin can see a
-- dispute thread exists at all — same three parties reject/escalate/
-- resolve already restrict to.
DROP POLICY IF EXISTS "dispute_threads_select" ON public.dispute_threads;
CREATE POLICY "dispute_threads_select" ON public.dispute_threads FOR SELECT TO authenticated USING (
  guest_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.organizers o WHERE o.id = dispute_threads.organizer_id
             AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
  OR public.is_platform_admin()
);

DROP POLICY IF EXISTS "dispute_messages_select" ON public.dispute_messages;
CREATE POLICY "dispute_messages_select" ON public.dispute_messages FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.dispute_threads t WHERE t.id = dispute_messages.dispute_thread_id
    AND (t.guest_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.organizers o WHERE o.id = t.organizer_id
                    AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
         OR public.is_platform_admin())
  )
);

-- No client-facing INSERT/UPDATE/DELETE policy on either table at all —
-- every write goes through the SECURITY DEFINER RPCs below, which apply
-- their own authorization and state checks (open vs. resolved) that a bare
-- RLS WITH CHECK can't express as precisely (e.g. "not yet resolved").

-- ---------------------------------------------------------------------------
-- send_dispute_message() — the guest or organizer posting into the
-- temporary dispute chat. Refuses once resolve_dispute() has closed it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_dispute_message(p_booking uuid, p_body text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t dispute_threads%ROWTYPE;
  v_body text := left(trim(COALESCE(p_body, '')), 2000);
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF v_body = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMPTY_MESSAGE');
  END IF;

  SELECT * INTO v_t FROM dispute_threads WHERE booking_id = p_booking;
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
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  INSERT INTO dispute_messages (dispute_thread_id, sender_id, sender_role, body)
  VALUES (v_t.id, auth.uid(), v_role, v_body);

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.send_dispute_message(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_dispute_message(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- escalate_payment_dispute() — extended (migration 032 first added this
-- function) to also open the dispute thread itself.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.escalate_payment_dispute(
  p_booking uuid, p_reason text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_from payment_state;
  v_authorized boolean;
  v_thread_id uuid;
  v_reason text := left(trim(COALESCE(p_reason, '')), 400);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_b.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) INTO v_authorized;
  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  v_from := v_b.payment_state;
  IF v_from NOT IN ('pending_verification', 'holding') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_from);
  END IF;

  UPDATE bookings SET
    payment_state = 'disputed',
    disputed_at = now(),
    dispute_reason = CASE WHEN v_reason <> '' THEN v_reason ELSE v_b.dispute_reason END,
    verify_due_at = NULL
  WHERE id = p_booking
  RETURNING * INTO v_b;

  PERFORM log_payment_event(
    p_booking, 'T3_disputed_escalated', v_from, 'disputed', auth.uid(), 'organizer', NULL, NULL,
    jsonb_build_object('reason', v_b.dispute_reason, 'transaction_id', v_b.transaction_id,
                       'proof_path', v_b.proof_path, 'payment_ref', v_b.payment_ref)
  );

  -- The temporary dispute chat itself — one per booking, matching the
  -- UNIQUE (booking_id) constraint. ON CONFLICT DO NOTHING makes this safe
  -- to call again (e.g. a dispute reopened after a resolved one is a
  -- distinct booking's row anyway; the same booking can't re-escalate once
  -- resolve_dispute has moved it out of 'disputed').
  INSERT INTO dispute_threads (booking_id, event_id, guest_id, organizer_id)
  VALUES (v_b.id, v_b.event_id, v_b.user_id, (SELECT organizer_id FROM events WHERE id = v_b.event_id))
  ON CONFLICT (booking_id) DO NOTHING;

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Người tổ chức và bạn chưa thống nhất được về khoản chuyển khoản này, nên đã chuyển cho banbe xem xét. Chỗ của bạn vẫn được giữ trong lúc chờ.',
            'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_b.user_id, 'payment_disputed', 'Thanh toán đang được xem xét',
          'banbe đang xem xét khoản thanh toán của bạn. Chỗ vẫn được giữ trong lúc chờ.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                             'reason', v_b.dispute_reason));

  UPDATE organizers o SET disputes_open = COALESCE(o.disputes_open, 0) + 1
  FROM events e WHERE e.id = v_b.event_id AND o.id = e.organizer_id;

  RETURN jsonb_build_object('success', true, 'state', 'disputed');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.escalate_payment_dispute(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.escalate_payment_dispute(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- resolve_dispute() — extended (was migration 026's admin-only ruling) to
-- also close out the dispute thread: mark it resolved (hidden from both
-- parties from this point on — the "soft delete" half), schedule the hard
-- purge for 72 hours out, and leave the one-line note in the guest's
-- ORDINARY thread the request asks for. The confirmation email itself
-- (with the receipt image and a PDF transcript attached) is sent by a
-- separate Vercel function, api/dispute-resolved-email.js, which the client
-- calls right after this RPC succeeds — an admin's browser session token is
-- what authorizes that call, this RPC's job is only the database state.
-- ---------------------------------------------------------------------------
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
  -- hard-purged later by purge_resolved_dispute_threads() below.
  UPDATE dispute_threads SET
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
-- purge_resolved_dispute_threads() — the actual hard delete, and only ever
-- of threads resolve_dispute() already marked resolved at least 72h ago.
-- Runs daily via pg_cron; also callable directly (SECURITY DEFINER,
-- admin/service-role only in practice since nothing client-facing exposes
-- it) for a manual purge sweep if ever needed.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_resolved_dispute_threads()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int;
BEGIN
  WITH purged AS (
    DELETE FROM dispute_threads
    WHERE resolved_at IS NOT NULL AND purge_after IS NOT NULL AND purge_after < now()
    RETURNING id
  )
  SELECT count(*) INTO v_count FROM purged;
  -- dispute_messages rows cascade with their thread (ON DELETE CASCADE).
  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.purge_resolved_dispute_threads() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.purge_resolved_dispute_threads() FROM anon;
GRANT EXECUTE ON FUNCTION public.purge_resolved_dispute_threads() TO authenticated;

SELECT cron.schedule(
  job_name  => 'banbe_purge_resolved_dispute_threads',
  schedule  => '30 3 * * *',
  command   => $cmd$ SELECT public.purge_resolved_dispute_threads(); $cmd$
);
