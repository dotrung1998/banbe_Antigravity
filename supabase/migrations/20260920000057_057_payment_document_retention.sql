-- Migration: long-term retention + advance-warning reminders for LIVE
-- payment_documents (see .claude/notes/08-payment-documents.md for the
-- 056 migration this extends).
--
-- WHY: 056 only ever set purge_after on a SUPERSEDED row (24h replacement
-- window) — a live, never-replaced document had no expiry at all, which on
-- this project's Supabase Free plan (500MB DB / 1GB storage) is unbounded
-- growth. Vietnamese accounting practice and general prudence around
-- payment proof argue against an aggressive delete, so this is a long
-- (12-month, anchored to the event date) window with 7-day and 1-day
-- advance warnings, not a short one.

-- ---------------------------------------------------------------------------
-- 1. Reminder tracking — one timestamp per threshold, so the cron can tell
--    "already sent" from "not due yet" without a separate log table.
-- ---------------------------------------------------------------------------
ALTER TABLE public.payment_documents
  ADD COLUMN IF NOT EXISTS reminder_7d_sent_at timestamptz,
  ADD COLUMN IF NOT EXISTS reminder_1d_sent_at timestamptz;

-- ---------------------------------------------------------------------------
-- 2. Task 1: upload_payment_document() (056) now sets purge_after on the
--    newly-inserted row too — event start + 12 months — but ONLY when it is
--    NOT a replacement. A replacement's *old* row keeps 056's untouched 24h
--    logic (v_existing's UPDATE, above, is unchanged); its *new* row is the
--    one now live and gets the same 12-month clock as any first upload,
--    since it's what participants/organizers will need to keep proof of
--    from here on. events.starts_at is the primary anchor (timestamptz);
--    event_date+event_time is the fallback for a row where starts_at was
--    never backfilled, and now() is the last-resort fallback for an event
--    with neither (never expected, but purge_after must never be null on a
--    freshly uploaded live document).
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
  v_live_purge_after timestamptz;
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

  -- Task 1's 12-month window, anchored to the event rather than to the
  -- upload moment — a document uploaded long after an event still expires
  -- relative to when the event actually happened.
  v_live_purge_after := COALESCE(
    v_event.starts_at,
    (v_event.event_date + COALESCE(v_event.event_time, '00:00'::time))::timestamptz,
    now()
  ) + interval '12 months';

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
    file_path, uploaded_by, upload_reason, purge_after
  ) VALUES (
    p_booking, v_event.id, v_org.id, v_booking.user_id, p_kind, v_number,
    p_file_path, auth.uid(), v_reason, v_live_purge_after
  )
  RETURNING * INTO v_doc;

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
