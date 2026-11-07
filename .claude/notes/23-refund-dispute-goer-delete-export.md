# Refund dispute: goer close/delete choices + real attachment export (iOS + migration 134)

## Status: WORKING on iOS; migration 134 verified on the local harness, NOT yet applied to remote. Web untouched.

- Migration `20261114000134_134_refund_dispute_goer_delete_copy.sql`: `dispute_threads.guest_deleted_at`, `delete_my_refund_dispute_copy(claim)` (goer only, closes first if open, idempotent), RLS + storage read policy + `get_refund_dispute_thread` / `get_refund_dispute_for_conversation` / `get_my_dispute_chats` hide the thread from the GUEST once flagged. Host access and the 7 day purge are unchanged. No refund status change.
- "Delete my copy" is an access flag, never a row/file delete: the host still needs the shared record.
- iOS export: `Lib/DisputeExport.swift` (PDF + stored ZIP, real bytes via the user's own storage download, any missing/invalid file fails the whole export). `State/AppState+DisputeExport.swift` state; `Views/RefundDisputeFlows.swift` is the one shared dialog flow used by `DisputeChatPanel` and `RefundDisputeEntry`.
- Share sheet result (`BanbeShareSheet.onFinish`) decides what follows: only a completed activity leads to the delete confirmation, which is a separate explicit tap. Dismissal is never treated as saved.
- Harness: `supabase/_localtest/06_goer_delete_copy_assert.sql` (wired into `run.sh`). Tests: `BanbeAppTests/DisputeExportTests.swift`.
