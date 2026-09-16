-- Migration: one-time cleanup of pre-migration-056 auto-generated
-- payment_documents rows (see .claude/notes/08-payment-documents.md).
--
-- Every row with file_path IS NULL predates the organizer-upload feature
-- entirely — it was minted by the now-neutered ensure_payment_document()
-- and never had a real file behind it. There are no real users on this app
-- yet (confirmed: only test accounts), so these are hard-deleted directly
-- rather than run through the 24h soft-delete path that applies to a real
-- replacement.
--
-- payment_document_counters is reset alongside them (deleted outright, not
-- just zeroed — upload_payment_document()'s ON CONFLICT ... DO UPDATE
-- re-creates a row at next_number=1 the first time each organizer/kind/year
-- combination is actually used again) so the first real upload for every
-- organizer starts a clean HD-/PT- series instead of continuing whatever
-- count the old auto-generated rows happened to leave behind.

DO $$
DECLARE
  v_deleted_docs int;
  v_deleted_counters int;
BEGIN
  DELETE FROM public.payment_documents WHERE file_path IS NULL;
  GET DIAGNOSTICS v_deleted_docs = ROW_COUNT;

  DELETE FROM public.payment_document_counters;
  GET DIAGNOSTICS v_deleted_counters = ROW_COUNT;

  RAISE NOTICE 'cleanup: deleted % payment_documents row(s) with no file_path, reset % payment_document_counters row(s)',
    v_deleted_docs, v_deleted_counters;
END $$;
