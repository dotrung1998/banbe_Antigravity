-- Migration 188: a 'removed' event status (an admin took the event down; note 54).
--
-- On its own on purpose: a value added with ALTER TYPE ... ADD VALUE cannot be USED in the same transaction that adds
-- it (see 107:19-23), and Supabase runs each migration file in one transaction. Migration 189 is what uses it.
--
-- Why a status and not a deleted_at column: every public read already filters events by status
-- (events_select_public / events_select_invited: status IN ('live','ended','cancelled'); hold_seats: status = 'live';
-- discovery, Pulse, fill, benchmarks, organizer stats: status IN (...)). A new value is therefore hidden everywhere
-- without touching any of those, and nothing can book it. The host still sees it (events_select_public's
-- is_event_host branch), admins see everything (events_select_admin).
--
-- Rollback: Postgres cannot drop an enum value. supabase/rollbacks/20261226000189_189_revert_admin_event_removal.sql
-- moves any removed events back to their previous status and drops 189's functions; the unused value stays.

ALTER TYPE event_status ADD VALUE IF NOT EXISTS 'removed';
