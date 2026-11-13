-- Migration 220 · when an event ends (note 82). NOT APPLIED until the owner says yes.
--
-- Two columns on events, both optional so every existing row stays valid:
--   end_time  time     the end on the venue's wall clock, like event_time (an end at or before event_time means the
--                      next day, e.g. 22:00 → 02:00)
--   end_open  boolean  true = "open-ended" (no set end: a pop-up, a gallery night, a party)
-- Neither set = not stated (events created before this). The two never both hold (CHECK).
-- No RPC change: the create flow writes them with the host's own events_update_own update after
-- create_event_draft / resubmit_event_for_review, like chat_greeting. Readable through the existing table grants.
-- Rollback: supabase/rollbacks/20261231000220_220_revert_event_end_time.sql

ALTER TABLE public.events ADD COLUMN IF NOT EXISTS end_time time;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS end_open boolean NOT NULL DEFAULT false;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'events_end_one_mode' AND conrelid = 'public.events'::regclass) THEN
    ALTER TABLE public.events ADD CONSTRAINT events_end_one_mode CHECK (NOT (end_open AND end_time IS NOT NULL));
  END IF;
END $$;

COMMENT ON COLUMN public.events.end_time IS 'Note 82: end on the venue wall clock (like event_time); at or before event_time = next day. NULL with end_open false = not stated.';
COMMENT ON COLUMN public.events.end_open IS 'Note 82: true = open-ended (no set end). Never true together with end_time.';
