-- Migration: a dedicated TEMPORARY chat for a goer-raised REFUND dispute.
--
-- The dispute chat that already exists (migrations 033/041/042/046, rendered
-- by DisputeChatPanel on both platforms) belongs to a PAYMENT dispute: the
-- HOST escalates ("banbe xem xét" / escalate_payment_dispute, or "Can't find
-- it" / reject_payment) and banbe rules on it via resolve_dispute(). A refund
-- dispute is the mirror image — the GOER raises it (dispute_refund(), "chưa
-- nhận được tiền"), there is no banbe ruling at all, it is settled by the two
-- of them (mark_refund_sent again -> host_marked_sent -> confirm_refund_
-- received -> guest_confirmed), and until today it had NO chat of its own at
-- all: both sides could only exchange one-shot system notifications
-- (refund_disputed / refund_marked_sent / refund_overdue) with no way to
-- actually talk about the money that hasn't arrived.
--
-- This reuses the same two tables rather than adding a parallel pair, so the
-- purge sweep, the retention story and the RLS shape stay in one place:
--
--   * dispute_threads gains `refund_claim_id` + `kind`. Payment-dispute rows
--     are untouched: booking_id still identifies them, kind defaults to
--     'payment'.
--   * booking_id stops being NOT NULL and its UNIQUE constraint becomes a
--     plain unique INDEX instead. That is the whole trick that makes this
--     additive: a refund thread carries booking_id = NULL (the booking is
--     reachable through refund_claims instead), and Postgres lets any number
--     of NULLs sit under a plain UNIQUE index. Every existing
--     `INSERT ... ON CONFLICT (booking_id)` upsert in escalate_payment_
--     dispute()/reject_payment()/resync_dispute_thread() therefore keeps
--     working UNCHANGED, and a booking can now carry BOTH a payment dispute
--     thread and a refund dispute thread instead of the second insert
--     silently colliding with the first (or vice versa).
--   * refund_claim_id gets its own plain unique index, so
--     `ON CONFLICT (refund_claim_id)` infers cleanly and one refund claim
--     always maps to at most one thread — which is what makes dispute_refund()
--     safe to call repeatedly (including a re-dispute inside the retention
--     window, see below).
--
-- Retention: "disappears 7 days after the dispute concludes". A refund dispute
-- concludes the moment its claim stops being 'disputed' (the host re-sent the
-- money, or it was confirmed/waived). goc_stamp_refund_dispute_chat_conclusions()
-- stamps resolved_at + purge_after = now() + 7 days on exactly those rows;
-- the EXISTING purge_resolved_dispute_threads() cron (daily, migration 033)
-- then hard-deletes them, cascade-dropping their dispute_messages. During the
-- 7-day window the thread stays READABLE by both parties (unlike a resolved
-- PAYMENT dispute, which migration 046 made admin-only the moment banbe rules
-- on it) and READ-ONLY — send_refund_dispute_message() refuses once resolved,
-- so a concluded dispute can't quietly grow a second argument.
--
-- The stamp is deliberately a no-op-safe UPDATE rather than logic threaded
-- through mark_refund_sent()/confirm_refund_received()/goc_auto_confirm_
-- refunds() separately: several functions can move a claim out of 'disputed'
-- (a batch refund, the 7-day auto-confirm, a manual admin edit), and a sweep
-- keyed purely on refund_claims.status cannot miss any of them the way a hook
-- in one function can. It runs from BOTH get_my_dispute_chats() (lazy, on
-- read — so the feature is correct even where pg_cron is unavailable) and its
-- own 15-minute cron (so it also happens when nobody happens to be looking).

-- ---------------------------------------------------------------------------
-- 1. Schema
-- ---------------------------------------------------------------------------
ALTER TABLE public.dispute_threads
  ADD COLUMN IF NOT EXISTS refund_claim_id uuid REFERENCES public.refund_claims(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'payment';

COMMENT ON COLUMN public.dispute_threads.refund_claim_id IS
  'Set for a refund dispute (goer reported not receiving the money); NULL for a payment dispute, which is keyed by booking_id instead.';
COMMENT ON COLUMN public.dispute_threads.kind IS
  '''payment'' (host escalated to banbe) | ''refund'' (goer reported a missing refund).';

-- Drop whatever UNIQUE constraint this table already has (booking_id's) and
-- rebuild it as a plain unique INDEX. Written as a DO block over pg_constraint
-- rather than a bare `DROP CONSTRAINT dispute_threads_booking_id_key` so it
-- does not depend on the auto-generated constraint name.
DO $$
DECLARE
  v_con record;
BEGIN
  FOR v_con IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.dispute_threads'::regclass AND contype = 'u'
  LOOP
    EXECUTE format('ALTER TABLE public.dispute_threads DROP CONSTRAINT %I', v_con.conname);
  END LOOP;
END $$;

ALTER TABLE public.dispute_threads ALTER COLUMN booking_id DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS dispute_threads_booking_id_uniq
  ON public.dispute_threads (booking_id);
CREATE UNIQUE INDEX IF NOT EXISTS dispute_threads_refund_claim_uniq
  ON public.dispute_threads (refund_claim_id);

-- get_my_dispute_chats() below scans by party, and has no index to ride on
-- otherwise (dispute_threads is tiny today but this is the table the whole
-- Messages-side entry now reads from).
CREATE INDEX IF NOT EXISTS dispute_threads_guest_idx
  ON public.dispute_threads (guest_id, created_at DESC);
CREATE INDEX IF NOT EXISTS dispute_threads_organizer_idx
  ON public.dispute_threads (organizer_id, created_at DESC);

-- Backfill: every refund claim that was ALREADY disputed when this migration
-- lands (dispute_refund() only opens a thread from here on) gets the same
-- chat, pre-populated with its parties, so the yellow entry and the jump
-- button work for disputes that are mid-flight at deploy time instead of
-- only for ones raised afterwards. The threads are created empty — the
-- backfilled arguments are in dispute_messages.data/refund_claims.note, and
-- inventing a first message from either side would put words in someone's
-- mouth in the one chat that is supposed to be a verbatim record.
INSERT INTO dispute_threads (booking_id, refund_claim_id, kind, event_id, guest_id, organizer_id)
SELECT NULL, rc.id, 'refund', b.event_id, b.user_id, e.organizer_id
FROM refund_claims rc
JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
JOIN events e ON e.id = b.event_id
WHERE rc.status = 'disputed'
ON CONFLICT (refund_claim_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. dispute_refund() — now opens the temporary chat as part of raising the
--    dispute, and re-opens a concluded one if the goer disputes again inside
--    the 7-day retention window. Body otherwise identical to migration 072.
-- ---------------------------------------------------------------------------
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
  INSERT INTO dispute_threads (booking_id, refund_claim_id, kind, event_id, guest_id, organizer_id)
  VALUES (NULL, p_claim_id, 'refund', v_event.id, v_booking.user_id, v_event.organizer_id)
  ON CONFLICT (refund_claim_id) DO UPDATE SET
    event_id = EXCLUDED.event_id,
    guest_id = EXCLUDED.guest_id,
    organizer_id = EXCLUDED.organizer_id,
    resolved_at = NULL,
    purge_after = NULL,
    resolution_kind = NULL,
    resolution_note = ''
  RETURNING id INTO v_thread_id;

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

-- ---------------------------------------------------------------------------
-- 3. Stamping the 7-day retention clock.
--    RETENTION below is the ONE place this window is defined.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.goc_stamp_refund_dispute_chat_conclusions()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int;
BEGIN
  WITH closed AS (
    UPDATE dispute_threads t
    SET resolved_at = now(),
        purge_after = now() + interval '7 days',
        resolution_kind = 'refund_settled'
    WHERE t.refund_claim_id IS NOT NULL
      AND t.resolved_at IS NULL
      AND EXISTS (
        SELECT 1 FROM refund_claims rc
        WHERE rc.id = t.refund_claim_id
          AND rc.status <> 'disputed'
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

-- Same "only if pg_cron is actually here" guard as migration 121's
-- expire_stale_admin_invites — the lazy stamp inside get_my_dispute_chats()
-- below is what keeps the feature correct without this job; the job only keeps
-- it exact when nobody is looking.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('goc_stamp_refund_dispute_chat_conclusions', '*/15 * * * *',
                          'SELECT public.goc_stamp_refund_dispute_chat_conclusions()');
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- ---------------------------------------------------------------------------
-- 4. RLS — a concluded REFUND dispute stays readable by both parties for the
--    whole 7-day window (and not one second past it, cron or no cron), while a
--    resolved PAYMENT dispute keeps migration 046's admin-only-when-resolved
--    rule untouched.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "dispute_threads_select" ON public.dispute_threads;
CREATE POLICY "dispute_threads_select" ON public.dispute_threads FOR SELECT TO authenticated USING (
  public.is_platform_admin()
  OR (
    (
      -- Open, OR concluded-but-not-yet-purged (refund disputes only).
      resolved_at IS NULL
      OR (refund_claim_id IS NOT NULL AND purge_after IS NOT NULL AND purge_after > now())
    )
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
        (
          t.resolved_at IS NULL
          OR (t.refund_claim_id IS NOT NULL AND t.purge_after IS NOT NULL AND t.purge_after > now())
        )
        AND (
          t.guest_id = auth.uid()
          OR EXISTS (SELECT 1 FROM public.organizers o WHERE o.id = t.organizer_id
                     AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
        )
      )
    )
  )
);

-- ---------------------------------------------------------------------------
-- 5. get_my_dispute_chats() — the ONE read path for the yellow "dispute"
--    section pinned at the top of Messages. Returns every dispute chat the
--    caller is a party to (goer or host), open ones first, each with the last
--    message so the collapsed row has something to show.
-- ---------------------------------------------------------------------------
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
  viewer_role text
)
-- VOLATILE (the default), not STABLE: the lazy conclusion sweep below writes,
-- and Postgres rejects any write inside a STABLE function. Nothing is lost —
-- the sweep is an idempotent "stamp once" UPDATE on a tiny table, and the
-- whole point of doing it here is that the caller doesn't have to wait on a
-- cron that may not be running.
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  -- Lazy sweep (see the note above get_my_dispute_chats' cron): makes the
  -- 7-day clock start on read even where pg_cron is unavailable. SECURITY
  -- DEFINER so the revoked-EXECUTE grant below doesn't block this call.
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
    -- Whoever the caller is NOT: the organizer when reading as the goer, the
    -- goer's own profile when reading as the host.
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
    -- count() is bigint; the column is int, so cast explicitly or the whole
    -- RETURN QUERY fails the result-shape check at runtime (not at CREATE
    -- time — plpgsql only type-checks this when it actually returns).
    COALESCE(msg_count.n, 0)::int,
    CASE WHEN t.guest_id = auth.uid() THEN 'guest' ELSE 'organizer' END
  FROM dispute_threads t
  LEFT JOIN events e ON e.id = t.event_id
  LEFT JOIN organizers o ON o.id = t.organizer_id
  LEFT JOIN profiles p ON p.id = t.guest_id
  LEFT JOIN refund_claims rc ON rc.id = t.refund_claim_id
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
  WHERE (t.resolved_at IS NULL
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

-- ---------------------------------------------------------------------------
-- 6. send_refund_dispute_message() — the refund twin of send_dispute_message()
--    (migration 048). A separate name rather than a second (uuid, text)
--    overload, which PostgREST could not tell apart from the existing one.
--    Read-only once the claim stops being 'disputed' — the same rule the
--    payment-dispute version applies on resolved_at.
-- ---------------------------------------------------------------------------
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

  SELECT * INTO v_t FROM dispute_threads WHERE refund_claim_id = p_refund_claim_id;
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