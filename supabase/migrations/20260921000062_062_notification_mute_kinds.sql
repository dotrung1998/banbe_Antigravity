-- Migration: per-account notification-kind muting (BUG 4, "•••" menu
-- replacing the bell screen's old per-row "×" delete button —
-- 07-notifications.md's 2026-09-18 follow-up).
--
-- WHY a single new column, not a new table: filtering happens entirely on
-- the READ side (loadNotifications()/the 5s toast poll, both client-side),
-- never on insert — none of the ~15 RPCs that write a `notifications` row
-- need touching. `profiles_update_own` (001) already covers writing this
-- column with no new RLS, the same pattern `auto_email_documents` (056)
-- already established for a self-service, no-RPC-needed preference.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS muted_notification_kinds text[] NOT NULL DEFAULT '{}';
