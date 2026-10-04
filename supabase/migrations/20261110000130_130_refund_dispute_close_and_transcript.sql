-- Migration: closing a REFUND dispute by either party, and exporting its
-- transcript — additive on top of migration 129, which added the temporary
-- chat itself but left the dispute with exactly two endings: the host re-sent
-- the money (or the claim was confirmed/waived), which stamped the 7-day
-- retention clock lazily, or nothing at all happened and the chat stayed
-- open forever. Neither party had any way to say "we're done arguing about
-- this" without one of them fabricating a transfer.
--
-- The design constraint that shapes everything below: closing the dispute
-- must NOT move the money. refund_claims.status is the single field the whole
-- refund state machine is built on ('owed' -> 'host_marked_sent' ->
-- 'guest_confirmed', with 'disputed' and 'waived' as branches), and every
-- financial RPC gates on it — mark_refund_sent, resend_refund,
-- confirm_refund_received, mark_refund_waived, the batch runner, the
-- destination rules. Writing 'guest_confirmed' or 'waived' on close would
-- tell both apps the goer got their money (or never was owed it) when nobody
-- has said any such thing, and would block the host from still sending it.
--
-- So closure is recorded as its OWN fact on the claim, additively:
--
--   refund_claims.dispute_closed_at / dispute_closed_by_role
--     "this claim's dispute was closed by one of its two parties", with no
--     financial meaning whatsoever. The claim stays exactly as it was —
--     still 'disputed', still owed, still actionable by mark_refund_sent /
--     confirm_refund_received afterwards.
--
--   dispute_threads.resolved_at / purge_after / resolution_kind
--     the existing soft-delete pair migration 129 already stamps, which is
--     what flips the chat read-only, starts the 7-day window, and lets the
--     EXISTING purge_resolved_dispute_threads() cron (daily, migration 033)
--     hard-delete the transcript for both parties at the end of it. Nothing
--     about that cron changes here — a refund transcript dies the same way a
--     payment transcript always has, and the ordinary booking conversation
--     is a different table entirely and is never touched.
--
-- Authorization: close_refund_dispute() accepts EITHER party — the goer or
-- the organizer account that owns the thread's organizer row — after an
-- explicit in-app confirmation, and is idempotent (a second call returns
-- already=true without re-notifying or re-stamping, so a double tap or a
-- retry after a flaky network can never move the purge deadline).
--
-- It refuses anything that isn't a refund dispute: a thread with a
-- booking_id, or kind <> 'refund', is a PAYMENT dispute, and those stay
-- admin-only through resolve_dispute() exactly as migrations 043/046 built
-- them. This migration does not touch resolve_dispute, and payment-dispute
-- permissions are not weakened anywhere in it.
--
-- get_my_dispute_chats() is redefined below with three ADDITIONAL columns
-- (source_booking_id, conversation_thread_id, dispute_closed_at,
-- dispute_closed_by_role). Every pre-existing column keeps its name, type and
-- meaning — in particular `booking_id` still returns the THREAD's own
-- booking_id, still NULL for a refund dispute, because the web client uses it
-- to look the thread back up by booking_id (src/screens/Inbox.jsx passes it
-- straight to DisputeChatPanel). The new source_booking_id /
-- conversation_thread_id are what let a client find the EXISTING booking
-- conversation a refund dispute belongs to without creating a second one and
-- without matching on event names.

-- ---------------------------------------------------------------------------
-- 1. Schema — additive columns only, no status/constraint changes.
-- ---------------------------------------------------------------------------
ALTER TABLE public.refund_claims
  ADD COLUMN IF NOT EXISTS dispute_closed_at timestamptz,
  ADD COLUMN IF NOT EXISTS dispute_closed_by_role text;

COMMENT ON COLUMN public.refund_claims.dispute_closed_at IS
  'When one of the two parties closed this claim''s refund dispute. Carries NO financial meaning: refund_claims.status is deliberately untouched, so the refund is still owed / still confirmable exactly as before. NULL until close_refund_dispute() runs (or until the dispute concluded some other way, which stamps the chat thread instead).';
COMMENT ON COLUMN public.refund_claims.dispute_closed_by_role IS
  '''guest'' | ''organizer'' — which party pressed "Close dispute". NULL while the dispute is open.';

-- get_my_dispute_chats() scans by dispute status + closure across every
-- refund claim of theirs; refund_claims has no index on either column.
CREATE INDEX IF NOT EXISTS refund_claims_dispute_closed_idx
  ON public.refund_claims (dispute_closed_at)
  WHERE dispute_closed_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. close_refund_dispute() — either party, idempotent, no money moved.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 3. get_refund_dispute_thread() — the ONE verified read of "does this claim
--    have a dispute chat, who am I in it, and is it still open".
--
--    Both entry points (the host's refund queue and the goer's refund card)
--    used to look this up in the get_my_dispute_chats() LIST and read
--    viewer_role off whatever row happened to be there — so a stale list
--    (or a first-ever screen reached before any Inbox load) meant no button
--    and no "who am I talking to" label. This resolves the thread by the
--    exact claim id every time, and derives the role from the caller's own
--    position on it, server-side.
--
--    found=false is a legitimate answer for "this claim was never disputed"
--    or "already purged"; NOT_AUTHORIZED is returned for anyone who is not a
--    party, which is the same distinction the client already gets from
--    reportStaleNotification().
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
REVOKE EXECUTE ON FUNCTION public.get_refund_dispute_thread(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_refund_dispute_thread(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. get_refund_dispute_for_conversation() — the inverse lookup the booking
--    conversation needs, so "open the dispute on THIS booking's chat" is an
--    exact thread-id match rather than a guess from the event name.
--
--    Returns the same shape as get_refund_dispute_thread() above for the one
--    refund claim on this conversation that is either an open dispute or was
--    closed inside its retention window. A guest with several bookings on one
--    event shares a single threads row (UNIQUE(event_id, guest_id)), so this
--    deliberately prefers the open dispute and, failing that, the most
--    recently opened one — never a name match, never a fuzzy event lookup.
-- ---------------------------------------------------------------------------
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
REVOKE EXECUTE ON FUNCTION public.get_refund_dispute_for_conversation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_refund_dispute_for_conversation(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. get_refund_dispute_transcript() — the export payload.
--
--    Deliberately NOT "whatever dispute_messages the caller happens to have
--    loaded": this returns the COMPLETE history with both participants,
--    per-message timestamps, the event/booking reference, the amount and the
--    claim's own status, so "Download transcript" produces a record that
--    stands on its own rather than a screenshot of the visible tail.
--
--    Authorized exactly like get_refund_dispute_thread() — both parties, plus
--    admins — and available both while the dispute is open (offered BEFORE
--    closing, so nobody has to close first to keep a copy) and throughout the
--    7-day post-closure window. After the purge it returns found=false,
--    because the rows it would read are genuinely gone.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_refund_dispute_transcript(p_claim_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_head jsonb;
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_guest_name text;
  v_msg_count int;
BEGIN
  v_head := public.get_refund_dispute_thread(p_claim_id);
  IF COALESCE((v_head ->> 'found')::boolean, false) IS NOT TRUE THEN
    RETURN v_head;
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;
  SELECT * INTO v_org FROM organizers WHERE id = v_event.organizer_id;
  -- Same "banbe" fallback migration 129's own get_my_dispute_chats() uses —
  -- profiles has display_name only, and a deleted/blank profile must still
  -- produce a readable participant line rather than an empty one.
  SELECT COALESCE(NULLIF(p.display_name, ''), 'banbe') INTO v_guest_name
  FROM profiles p WHERE p.id = v_booking.user_id;

  SELECT count(*) INTO v_msg_count
  FROM dispute_messages dm
  WHERE dm.dispute_thread_id = (v_head ->> 'dispute_thread_id')::uuid;

  RETURN v_head || jsonb_build_object(
    'organizer_label', v_org.name,
    'guest_label', COALESCE(v_guest_name, 'banbe'),
    'booking_id', v_booking.id,
    'booking_code', v_booking.code,
    -- event_id (the raw id) is already in the head object; event_key is the
    -- human-facing slug the list function also returns, kept distinct here so
    -- the two RPCs never disagree about what "event_key" means.
    'event_key', v_event.key,
    'claim_reason', v_claim.reason,
    'claim_note', v_claim.note,
    'host_marked_at', v_claim.host_marked_at,
    'guest_confirmed_at', v_claim.guest_confirmed_at,
    'refund_due_at', v_claim.refund_due_at,
    'transcript_message_count', v_msg_count,
    'exported_at', now(),
    'messages', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', dm.id,
        'sender_role', dm.sender_role,
        'sender_name', CASE dm.sender_role
          WHEN 'guest' THEN COALESCE(v_guest_name, 'banbe')
          WHEN 'organizer' THEN v_org.name
          ELSE 'banbe' END,
        'body', dm.body,
        'created_at', dm.created_at
      ) ORDER BY dm.created_at, dm.id)
      FROM dispute_messages dm
      WHERE dm.dispute_thread_id = (v_head ->> 'dispute_thread_id')::uuid
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_refund_dispute_transcript(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_refund_dispute_transcript(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_refund_dispute_transcript(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. goc_stamp_refund_dispute_chat_conclusions() — same lazy sweep as
--    migration 129, now also concluding a dispute that was closed by one of
--    its parties rather than by the claim leaving 'disputed'.
--
--    close_refund_dispute() already stamps resolved_at itself, so this is a
--    safety net for the paths it does not own (a claim concluded elsewhere
--    while the thread row was somehow still open, e.g. an admin edit). It
--    stays idempotent and stays an UPDATE on a tiny table.
-- ---------------------------------------------------------------------------
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
          AND (rc.status <> 'disputed' OR rc.dispute_closed_at IS NOT NULL)
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

-- ---------------------------------------------------------------------------
-- 7. get_my_dispute_chats() — four ADDITIONAL columns, nothing removed.
--    Every pre-existing column keeps its name, position-independent meaning
--    and (critically) its value: `booking_id` still returns t.booking_id, so
--    the web Inbox's `chat.booking_id` → DisputeChatPanel lookup is
--    unaffected by this migration.
--
--      source_booking_id      the refund claim's underlying booking — the id
--                             a client must navigate by. Exact, never an
--                             event name.
--      conversation_thread_id the EXISTING (event_id, guest_id) thread the
--                             dispute renders inside, so a client opens the
--                             booking conversation it already has instead of
--                             creating a second conversation for the dispute.
--      dispute_closed_at      drives "Dispute completed" and clears the
--                             active-dispute indicator/count for both sides.
--      dispute_closed_by_role which party pressed close.
--
-- DROP, THEN CREATE — NOT `CREATE OR REPLACE`. This function is declared
-- `RETURNS TABLE(...)`, so its return type is a composite built from those
-- OUT parameter names; PostgreSQL refuses to change a function's return type
-- with CREATE OR REPLACE ("cannot change return type of existing function"),
-- and adding columns to the OUT list is exactly that. The DROP is safe here
-- because nothing depends on this function: it is a leaf read path called
-- only over PostgREST (web src/state/GocContext.jsx, iOS loadDisputeChats),
-- with no view, trigger or other function referencing it — verified against
-- the full migration chain. The window between DROP and CREATE is a few
-- milliseconds inside this transaction; PostgREST caches its schema, so no
-- in-flight request sees the gap.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_my_dispute_chats();
CREATE FUNCTION public.get_my_dispute_chats()
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