-- Migration: replace auto-generated invoice/receipt with organizer-uploaded
-- files (see .claude/notes/08-payment-documents.md for the full audit this
-- migration is based on).
--
-- WHY: an auto-generated document (024's ensure_payment_document()) is a
-- banbe-authored artifact from frozen jsonb fields — never something the
-- organizer actually produced or can correct. Organizers increasingly want
-- to hand out their own real invoice/receipt (a proper accounting document,
-- sometimes from their own bookkeeping software). This migration stops the
-- auto-generation and adds the columns/storage/RPC an uploaded file needs,
-- without touching the five trigger functions that used to call it — see
-- below for why that's safe.

-- ---------------------------------------------------------------------------
-- 1. New columns.
-- ---------------------------------------------------------------------------
ALTER TABLE public.payment_documents
  ADD COLUMN IF NOT EXISTS file_path text,
  ADD COLUMN IF NOT EXISTS uploaded_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS upload_reason text,
  ADD COLUMN IF NOT EXISTS superseded_at timestamptz,
  ADD COLUMN IF NOT EXISTS purge_after timestamptz;

-- ---------------------------------------------------------------------------
-- 2. The old "one row ever per (booking, kind)" unique index is
--    incompatible with keeping a superseded row queryable for 24h (Task 5's
--    soft-delete window) — a replacement needs the old and new row to
--    coexist briefly. Replaced with a partial index: still at most one
--    *live* document per booking+kind, any number of superseded ones.
-- ---------------------------------------------------------------------------
DROP INDEX IF EXISTS public.payment_documents_booking_kind_idx;
CREATE UNIQUE INDEX IF NOT EXISTS payment_documents_booking_kind_live_idx
  ON public.payment_documents (booking_id, kind) WHERE superseded_at IS NULL;

-- Superseded rows waiting out their 24h window — what the purge cron scans.
CREATE INDEX IF NOT EXISTS payment_documents_purge_after_idx
  ON public.payment_documents (purge_after) WHERE purge_after IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3. Stop auto-generation. ensure_payment_document() becomes a no-op stub
--    rather than rewriting its five call sites (confirm_payment() 024,
--    reserve/free-event auto-confirm paths in 025/026/031/053) — every one
--    of those either PERFORM-calls it or wraps the result in
--    `BEGIN ... EXCEPTION WHEN OTHERS THEN NULL END` and only reads
--    `v_receipt.number` afterwards, which is NULL-safe on a NULL composite
--    in plpgsql. Confirmed by reading each site in full — see
--    .claude/notes/08-payment-documents.md's Task 1 table.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_payment_document(
  p_booking uuid, p_kind payment_doc_kind
)
RETURNS public.payment_documents
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Deliberately does nothing. Documents are now organizer-uploaded via
  -- upload_payment_document() below, not minted from booking data.
  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Storage: a private bucket for the uploaded files themselves. Same
--    `<booking_id>/<filename>` path shape as `pay-proof` (005/024), so the
--    same `split_part(name, '/', 1) = booking id` trick scopes RLS to
--    exactly one booking. 10MB (vs pay-proof's 5MB): an organizer's own
--    invoice/receipt is more likely to be a scanned multi-page PDF than a
--    phone photo.
--
--    Admin is deliberately NOT granted a bypass here, unlike pay-proof's
--    (040_admin_rbac.sql) — that bypass exists because dispute review
--    genuinely needs the proof screenshot; nothing here is dispute-relevant,
--    and .claude/notes/08-payment-documents.md's Task 7 confirmed no admin
--    code path reads payment_documents at all. Keep it that way rather than
--    copy-pasting pay-proof's admin clause onto this bucket.
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('payment-documents', 'payment-documents', false, 10485760,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "payment_documents_bucket_organizer_insert" ON storage.objects;
CREATE POLICY "payment_documents_bucket_organizer_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'payment-documents' AND EXISTS (
    SELECT 1 FROM public.bookings b
    JOIN public.events e ON e.id = b.event_id
    JOIN public.organizers o ON o.id = e.organizer_id
    WHERE b.id::text = split_part((objects).name, '/', 1)
      AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);

DROP POLICY IF EXISTS "payment_documents_bucket_read" ON storage.objects;
CREATE POLICY "payment_documents_bucket_read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'payment-documents' AND EXISTS (
    SELECT 1 FROM public.bookings b
    JOIN public.events e ON e.id = b.event_id
    LEFT JOIN public.organizers o ON o.id = e.organizer_id
    WHERE b.id::text = split_part((objects).name, '/', 1)
      AND (b.user_id = auth.uid() OR o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);

-- Organizers may also need to delete/replace their own upload (the RPC
-- below handles supersession bookkeeping, but the old *object* itself is
-- only actually removed by the purge cron once purge_after passes — this
-- policy is for the rare case an organizer immediately re-uploads the exact
-- same path, e.g. retrying a failed upload).
DROP POLICY IF EXISTS "payment_documents_bucket_organizer_update" ON storage.objects;
CREATE POLICY "payment_documents_bucket_organizer_update"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'payment-documents' AND EXISTS (
    SELECT 1 FROM public.bookings b
    JOIN public.events e ON e.id = b.event_id
    JOIN public.organizers o ON o.id = e.organizer_id
    WHERE b.id::text = split_part((objects).name, '/', 1)
      AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);

-- ---------------------------------------------------------------------------
-- 5. Task 4: the participant's one-time, account-level opt-in. Same
--    pattern as profiles.locale/theme — a plain column, written by the
--    client's existing persistAccountPreference()-style update, no new RPC.
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS auto_email_documents boolean NOT NULL DEFAULT false;

-- ---------------------------------------------------------------------------
-- 6. upload_payment_document() — the actual replacement for
--    ensure_payment_document(). Organizer-only (booking's event's
--    organizer, not the guest — this is the organizer handing the guest a
--    real document, the reverse direction of the old auto-mint). Requires
--    upload_reason only when replacing a live document of the same kind
--    (Task 5); supersedes the old row with a 24h purge window before
--    inserting the new one; still issues a real sequential number via the
--    existing counter series so an organizer's own numbering stays
--    continuous across the switch from auto-generated to uploaded.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upload_payment_document(
  p_booking uuid, p_kind payment_doc_kind, p_file_path text,
  p_upload_reason text DEFAULT NULL
)
RETURNS public.payment_documents
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking  bookings%ROWTYPE;
  v_event    events%ROWTYPE;
  v_org      organizers%ROWTYPE;
  v_existing payment_documents%ROWTYPE;
  v_doc      payment_documents%ROWTYPE;
  v_reason   text;
  v_year     int;
  v_seq      int;
  v_number   text;
  v_prefix   text;
  v_org_email text;
  v_purge_after timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking;
  IF NOT FOUND THEN RAISE EXCEPTION 'BOOKING_NOT_FOUND'; END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;
  SELECT * INTO v_org FROM organizers WHERE id = v_event.organizer_id;

  IF v_org.id IS NULL OR NOT (v_org.owner_id = auth.uid() OR v_org.user_id = auth.uid()) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  IF p_file_path IS NULL OR btrim(p_file_path) = '' THEN
    RAISE EXCEPTION 'FILE_REQUIRED';
  END IF;
  -- The bucket's own RLS already scopes uploads to this booking's path
  -- prefix, but a client bug (or a stale path from a different booking)
  -- would otherwise still let a row be created pointing at someone else's
  -- file — check it here too rather than trust the caller.
  IF split_part(p_file_path, '/', 1) <> p_booking::text THEN
    RAISE EXCEPTION 'INVALID_PATH';
  END IF;

  SELECT * INTO v_existing FROM payment_documents
   WHERE booking_id = p_booking AND kind = p_kind AND superseded_at IS NULL;

  v_reason := NULLIF(btrim(COALESCE(p_upload_reason, '')), '');

  IF FOUND THEN
    IF v_reason IS NULL THEN
      RAISE EXCEPTION 'REASON_REQUIRED';
    END IF;
    v_purge_after := now() + interval '24 hours';
    UPDATE payment_documents
      SET superseded_at = now(), purge_after = v_purge_after
      WHERE id = v_existing.id;
  END IF;

  v_year := EXTRACT(YEAR FROM now())::int;
  v_prefix := CASE WHEN p_kind = 'invoice' THEN 'HD' ELSE 'PT' END;

  INSERT INTO payment_document_counters (organizer_id, kind, year, next_number)
  VALUES (v_org.id, p_kind, v_year, 1)
  ON CONFLICT (organizer_id, kind, year)
  DO UPDATE SET next_number = payment_document_counters.next_number + 1
  RETURNING next_number INTO v_seq;

  v_number := v_prefix || '-' || upper(v_org.id) || '-' || v_year::text
              || '-' || lpad(v_seq::text, 4, '0');

  INSERT INTO payment_documents (
    booking_id, event_id, organizer_id, user_id, kind, number,
    file_path, uploaded_by, upload_reason
  ) VALUES (
    p_booking, v_event.id, v_org.id, v_booking.user_id, p_kind, v_number,
    p_file_path, auth.uid(), v_reason
  )
  RETURNING * INTO v_doc;

  -- Task 3 (always) / Task 6 (on replacement, a distinct kind+message).
  -- email_registrations (014) is the queryable email mirror this schema
  -- already uses instead of reading auth.users directly from plpgsql.
  IF v_existing.id IS NOT NULL THEN
    SELECT email INTO v_org_email FROM email_registrations
     WHERE auth_user_id = COALESCE(v_org.owner_id, v_org.user_id) LIMIT 1;

    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_booking.user_id, 'payment_document_replaced',
      CASE WHEN p_kind = 'invoice' THEN 'Hoá đơn đã được cập nhật' ELSE 'Biên nhận đã được cập nhật' END,
      'Người tổ chức đã tải lên bản mới. Lý do: ' || v_reason
        || COALESCE('. Liên hệ ' || v_org_email || ' nếu bạn cần bản cũ trước khi bị xoá.', '.'),
      jsonb_build_object(
        'document_id', v_doc.id, 'booking_id', p_booking, 'kind', p_kind,
        'reason', v_reason, 'organizer_email', v_org_email,
        'previous_purge_after', v_purge_after
      )
    );
  ELSE
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_booking.user_id, 'payment_document_uploaded',
      CASE WHEN p_kind = 'invoice' THEN 'Hoá đơn đã sẵn sàng' ELSE 'Biên nhận đã sẵn sàng' END,
      'Người tổ chức vừa tải lên ' || CASE WHEN p_kind = 'invoice' THEN 'hoá đơn' ELSE 'biên nhận' END || ' của bạn.',
      jsonb_build_object('document_id', v_doc.id, 'booking_id', p_booking, 'kind', p_kind)
    );
  END IF;

  RETURN v_doc;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.upload_payment_document(uuid, payment_doc_kind, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.upload_payment_document(uuid, payment_doc_kind, text, text) TO authenticated;
