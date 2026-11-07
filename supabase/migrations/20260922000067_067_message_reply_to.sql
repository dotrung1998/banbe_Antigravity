-- Migration: reply-to-media reference for chat messages
-- (see .claude/notes/07-notifications.md — chat-image viewer bottom composer).
--
-- The chat-image fullscreen viewer's own composer needs a way for a reply
-- sent from it to visibly reference the exact image it was replying to,
-- rather than encoding that in the message body text (fragile, unparseable
-- once other features touch `body`, and impossible to join back to the
-- original attachment's metadata). The smallest explicit addition: a
-- nullable self-reference. No new RLS needed — the existing
-- `messages_select_thread_participant`/`messages_insert_participant`
-- policies (003_social_chat.sql) already scope by `thread_id`, which this
-- column doesn't change; an ordinary text/system message simply has this
-- column NULL and is completely unaffected.
ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_to_message_id uuid REFERENCES messages(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_messages_reply_to ON messages(reply_to_message_id) WHERE reply_to_message_id IS NOT NULL;
