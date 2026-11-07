-- "Message host" pass.
--
-- 1. events.chat_greeting — optional opening message the HOST sets per event.
--    It is shown to a goer who taps "Message <host>" as the first bubble of the
--    not-yet-created conversation. It is display-only: nothing is written to
--    threads/messages until the goer actually sends something, so opening the
--    chat and backing out leaves no trace in the inbox.
-- 2. thread_preferences.deleted_at — per-participant "Delete" (hide for me).
--    The other participant keeps the conversation; a message newer than
--    deleted_at makes the thread reappear for the person who deleted it.

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS chat_greeting text;

ALTER TABLE public.events
  DROP CONSTRAINT IF EXISTS events_chat_greeting_len;
ALTER TABLE public.events
  ADD CONSTRAINT events_chat_greeting_len CHECK (chat_greeting IS NULL OR char_length(chat_greeting) <= 500);

ALTER TABLE public.thread_preferences
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
