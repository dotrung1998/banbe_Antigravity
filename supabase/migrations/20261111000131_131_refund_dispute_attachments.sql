-- Migration: attachments in the TEMPORARY refund-dispute chat.
--
-- Additive on top of migration 129 (the chat itself) and 130 (closure +
-- transcript export). Nothing about the payment-dispute chat changes: it has
-- no attachment columns written here, no new bucket, and both of its
-- functions are untouched.
--
-- Why this can't reuse the ordinary chat's `chat-attachments` bucket: that
-- bucket's policies key every object off `threads` (migration 065) —
-- `split_part(name,'/',1)` must be a THREAD id, and the caller must be that
-- booking conversation's guest or the event's organizer. A refund dispute is
-- not a conversation: it is keyed by `refund_claims.id`, rendered INSIDE a
-- conversation, and it deliberately has its own short retention life (7 days
-- after the dispute closes, then a hard delete). Filing dispute files under a
-- thread id would have made them look exactly like ordinary chat files to
-- every policy, the purge, and any future export — i.e. they would have
-- survived the temporary chat that owns them, and a purge would either miss
-- them or have to risk ordinary chat files. So they get their own bucket and
-- their own lifecycle.
--
-- The rules that shape everything below:
--
--   * PRIVATE + participant-scoped. `dispute-attachments` is a private
--     bucket. Read access is granted to exactly the two parties of that one
--     dispute thread (plus platform admins, who already have admin chat
--     access everywhere) — the same shape as `dispute_messages_select`.
--   * Attachments follow the dispute's OWN retention. The read policy
--     mirrors the row policy verbatim, including the refund retention
--     window: open dispute -> readable; closed but not yet purged -> still
--     readable; after `purge_after` -> neither the rows nor the files are
--     reachable, even if the object somehow outlived its thread.
--   * Nothing may be added after closure. The INSERT policy requires an
--     unresolved thread, and send_refund_dispute_attachment() re-checks
--     `resolved_at IS NULL` at INSERT time — which is also what closes the
--     "the other party closed the dispute while my photo was uploading"
--     race: the file is already in storage by then, the message is refused,
--     and the client deletes the object it just wrote (cleanup is why the
--     DELETE policy below exists at all).
--   * A message may be attachment-only. `body` stays NOT NULL (no schema
--     change that existing rows or the web client would have to care about),
--     so the RPC substitutes the same placeholder the ordinary chat uses
--     ("Sent a photo" / "Sent a file") when the sender typed nothing.
--   * The purge removes the files. purge_resolved_dispute_threads() is
--     redefined to delete this bucket's objects for exactly the threads it
--     deletes. Its return value (a thread count) is unchanged, and ordinary
--     `chat-attachments` objects are never touched.

-- ---------------------------------------------------------------------------
-- 1. Schema — additive columns on dispute_messages only.
-- ---------------------------------------------------------------------------
ALTER TABLE public.dispute_messages
  ADD COLUMN IF NOT EXISTS attachment_path text,
  ADD COLUMN IF NOT EXISTS attachment_type text,
  ADD COLUMN IF NOT EXISTS attachment_width integer,
  ADD COLUMN IF NOT EXISTS attachment_height integer;

COMMENT ON COLUMN public.dispute_messages.attachment_path IS
  'Object path in the private dispute-attachments bucket ("<dispute_thread_id>/<file>"), or NULL for a text-only line. Deleted with the thread by purge_resolved_dispute_threads().';
COMMENT ON COLUMN public.dispute_messages.attachment_type IS
  'MIME type of the attachment (image/jpeg, image/png, image/webp, application/pdf), or NULL for a text-only line.';
COMMENT ON COLUMN public.dispute_messages.attachment_width IS
  'Pixel width of the image as uploaded, so a client can size a preview box at the source ratio without downloading it first.';
COMMENT ON COLUMN public.dispute_messages.attachment_height IS
  'Pixel height of the image as uploaded. NULL for documents.';

-- ---------------------------------------------------------------------------
-- 2. Private bucket, participant-scoped, refund-retention-aware.
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('dispute-attachments', 'dispute-attachments', false, 20971520,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO NOTHING;

-- Object path convention: `<dispute_thread_id>/<file>` — the same
-- "first path segment is the owning entity" convention pay-qr and
-- chat-attachments already use.
--
-- Every predicate below compares `dispute_threads.id::text` to
-- split_part(name,'/',1) rather than casting the path segment to uuid: a
-- client that uploads to a malformed path would otherwise make the cast
-- raise, which turns one bad object into a permission error for every other
-- row in the bucket.
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
            -- Open, OR concluded-but-not-yet-purged (refund disputes only) —
            -- deliberately the SAME window dispute_messages_select grants,
            -- so a file can never outlive the row that describes it.
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

DROP POLICY IF EXISTS "dispute_attachments_participant_insert" ON storage.objects;
CREATE POLICY "dispute_attachments_participant_insert"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'dispute-attachments'
    AND EXISTS (
      SELECT 1 FROM public.dispute_threads t
      WHERE t.id::text = split_part((objects).name, '/', 1)
      -- The thread must still be OPEN: an upload that starts before closure
      -- and finishes after it is refused here, exactly as the message insert
      -- below is.
      AND t.resolved_at IS NULL
      AND (
        t.guest_id = auth.uid()
        OR EXISTS (SELECT 1 FROM public.organizers o WHERE o.id = t.organizer_id
                   AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
      )
    )
  );

-- Cleanup only, and only ever scoped to the caller's own disputes: an upload
-- whose message insert was refused (or whose network died halfway) has to be
-- removable by the account that uploaded it, or every failed attempt would
-- leave a permanent orphan in a bucket nothing else ever cleans.
DROP POLICY IF EXISTS "dispute_attachments_participant_delete" ON storage.objects;
CREATE POLICY "dispute_attachments_participant_delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'dispute-attachments'
    AND EXISTS (
      SELECT 1 FROM public.dispute_threads t
      WHERE t.id::text = split_part((objects).name, '/', 1)
      AND (
        public.is_platform_admin()
        OR t.guest_id = auth.uid()
        OR EXISTS (SELECT 1 FROM public.organizers o WHERE o.id = t.organizer_id
                   AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 3. send_refund_dispute_attachment() — the refund twin of the ordinary
--    chat's attachment send, and the ONLY way an attachment reaches this
--    transcript (dispute_messages still has no client INSERT policy).
--
--    A separate name rather than extra parameters on
--    send_refund_dispute_message(): that function's signature is
--    (uuid, text) and PostgREST resolves by exact parameter list, so adding
--    optional parameters would silently create a second overload instead of
--    replacing it — and the web client already calls the two-argument form.
--
--    The upload itself is a direct Storage call (the bucket policies above
--    authorize it); this function's job is the half RLS can't express:
--    proving the caller is a party, proving the thread is still open AT THE
--    MOMENT the message is written, and proving the path they handed up
--    really belongs to this thread — otherwise a client could attach another
--    dispute's object (or a path that doesn't exist) to its own message.
-- ---------------------------------------------------------------------------
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

  SELECT * INTO v_t FROM dispute_threads WHERE refund_claim_id = p_refund_claim_id;
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
REVOKE EXECUTE ON FUNCTION public.send_refund_dispute_attachment(uuid, text, text, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_refund_dispute_attachment(uuid, text, text, text, integer, integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. get_refund_dispute_transcript() — attachment metadata in the export.
--
--    Purely additive: every key it already returned keeps its name and
--    meaning, and the per-message objects simply gain the same four fields
--    the transcript table has. `attachment_notice` is stated plainly rather
--    than left for the client to imply, because the file this export points
--    at is deleted with the temporary chat — an exported reference must
--    never read as a permanent link.
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
  v_thread uuid;
  v_attach_count int := 0;
  v_purge_after timestamptz;
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

  v_thread := (v_head ->> 'dispute_thread_id')::uuid;
  SELECT count(*) INTO v_msg_count FROM dispute_messages dm WHERE dm.dispute_thread_id = v_thread;
  SELECT count(*) INTO v_attach_count FROM dispute_messages dm
  WHERE dm.dispute_thread_id = v_thread AND dm.attachment_path IS NOT NULL;
  SELECT purge_after INTO v_purge_after FROM dispute_threads WHERE id = v_thread;

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
    'attachment_count', v_attach_count,
    -- Says exactly what an exported attachment line can and cannot promise:
    -- what was attached, and that the file itself does not survive this
    -- transcript. Never a URL — the only URLs that ever existed here are
    -- short-lived signed ones, and the object is gone after the purge.
    'attachment_notice',
      'Attachments listed below were shared in this dispute only. The files themselves were private to the two parties and are deleted together with this transcript on '
      || COALESCE(to_char(v_purge_after, 'YYYY-MM-DD'), 'its purge date')
      || ' — an exported reference records that a file was sent, not a link that will keep working.',
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
        'created_at', dm.created_at,
        'attachment_path', dm.attachment_path,
        'attachment_type', dm.attachment_type,
        'attachment_width', dm.attachment_width,
        'attachment_height', dm.attachment_height
      ) ORDER BY dm.created_at, dm.id)
      FROM dispute_messages dm
      WHERE dm.dispute_thread_id = v_thread
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_refund_dispute_transcript(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_refund_dispute_transcript(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_refund_dispute_transcript(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. purge_resolved_dispute_threads() — the files go with the transcript.
--
--    The thread count this returns is unchanged, so the cron wrapper and any
--    manual caller keep working exactly as before. What changes is that the
--    attachment objects for the threads being hard-deleted are removed in the
--    same sweep, BEFORE the threads themselves go (the objects are addressed
--    by thread id, so the ids have to be captured first).
--
--    Scoped to `bucket_id = 'dispute-attachments'` by name, which is what
--    keeps ordinary `chat-attachments` objects — a different bucket, keyed by
--    `threads` — completely out of this statement.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_resolved_dispute_threads()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int;
  v_files int;
BEGIN
  WITH doomed AS (
    DELETE FROM dispute_threads
    WHERE resolved_at IS NOT NULL AND purge_after IS NOT NULL AND purge_after < now()
    RETURNING id
  ),
  removed_files AS (
    DELETE FROM storage.objects o
    WHERE o.bucket_id = 'dispute-attachments'
      AND EXISTS (SELECT 1 FROM doomed d WHERE d.id::text = split_part(o.name, '/', 1))
    RETURNING 1
  )
  SELECT (SELECT count(*) FROM doomed), (SELECT count(*) FROM removed_files)
  INTO v_count, v_files;
  -- dispute_messages rows cascade with their thread (ON DELETE CASCADE), and
  -- the attachment objects for those threads were deleted just above.
  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.purge_resolved_dispute_threads() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.purge_resolved_dispute_threads() FROM anon;
GRANT EXECUTE ON FUNCTION public.purge_resolved_dispute_threads() TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. Migration 051/052's purge_test_dispute_messages_only() empties a test
--    thread's transcript WITHOUT deleting the thread, so it deliberately
--    leaves this bucket alone: those rows are not being purged, they are
--    being cleared so a test can start over, and deleting the files here
--    would make an ordinary test run destroy real evidence. Nothing else in
--    the migration chain deletes dispute rows, so the sweep in section 5 is
--    the only path that removes these files — which is the point.
-- ---------------------------------------------------------------------------