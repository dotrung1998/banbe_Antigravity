-- Migration: real read-tracking for public.messages (Chat.jsx/ChatView,
-- distinct from the permanent Notifications bell's `notifications.read_at`
-- and from `dispute_messages`' own separate retention rules).
--
-- Confirmed gap (see .claude/notes/07-notifications.md): `messages` had
-- SELECT/INSERT RLS (003_social_chat.sql) and a DELETE policy scoped to the
-- sender (054, messages_delete_own), but no UPDATE policy at all — meaning
-- RLS defaulted to deny, and the client-side markThreadMessagesRead() this
-- same pass adds (GocContext.jsx / AppState+Data.swift) would otherwise
-- silently update zero rows.
--
-- Scoped to the same thread-participant check messages_select_thread_participant
-- already uses (guest_id = me, OR organizer_id owned by me) — a participant
-- can mark ANY message in their own thread read, mirroring how a normal
-- messaging app's "mark read" works; the app-layer code only ever calls
-- this for rows it didn't send (sender_id != me), but RLS itself doesn't
-- need to re-enforce that narrower rule to stay safe, since a participant
-- writing read_at on their own outgoing message is harmless.

DROP POLICY IF EXISTS "messages_update_participant" ON messages;
CREATE POLICY "messages_update_participant" ON messages FOR UPDATE TO authenticated USING (
  EXISTS (
    SELECT 1 FROM threads t
    WHERE t.id = messages.thread_id
    AND (
      t.guest_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM organizers o
        WHERE o.id = t.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
      )
    )
  )
) WITH CHECK (
  EXISTS (
    SELECT 1 FROM threads t
    WHERE t.id = messages.thread_id
    AND (
      t.guest_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM organizers o
        WHERE o.id = t.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
      )
    )
  )
);
