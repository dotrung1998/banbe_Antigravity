-- Migration: three independent additions for this pass's Inbox/Chat work
-- (see .claude/notes/07-notifications.md) — kept in one file since none of
-- the three touch the others' tables.
--
-- 1. thread_preferences — per-participant star/archive state for a thread.
--    NOT stored on `threads` itself: a guest and the organizer on the same
--    thread must be able to star/archive independently (one participant
--    archiving a conversation shouldn't hide it from the other side).
-- 2. app_feedback — generic feedback storage; no existing table covers this
--    (confirmed via grep before adding), so the smallest reasonable shape.
-- 3. messages.attachment_path/attachment_type + a new private
--    `chat-attachments` bucket, for the composer's new "+" attach flow.

-- ============ 1. thread_preferences ============
CREATE TABLE IF NOT EXISTS thread_preferences (
  thread_id uuid REFERENCES threads(id) ON DELETE CASCADE,
  user_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  starred boolean NOT NULL DEFAULT false,
  archived boolean NOT NULL DEFAULT false,
  PRIMARY KEY (thread_id, user_id)
);

ALTER TABLE thread_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "thread_preferences_own" ON thread_preferences;
CREATE POLICY "thread_preferences_own" ON thread_preferences FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- ============ 2. app_feedback ============
CREATE TABLE IF NOT EXISTS app_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  body text NOT NULL DEFAULT '',
  is_bug_report boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE app_feedback ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "app_feedback_insert_own" ON app_feedback;
CREATE POLICY "app_feedback_insert_own" ON app_feedback FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "app_feedback_select_own" ON app_feedback;
CREATE POLICY "app_feedback_select_own" ON app_feedback FOR SELECT TO authenticated
USING (auth.uid() = user_id);

-- ============ 3. chat message attachments ============
ALTER TABLE messages ADD COLUMN IF NOT EXISTS attachment_path text;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS attachment_type text;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('chat-attachments', 'chat-attachments', false, 20971520,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO NOTHING;

-- Object path convention: `<thread_id>/<file>` — same split_part(name,'/',1)
-- convention pay-qr's own policies already use (005_storage_buckets.sql).
DROP POLICY IF EXISTS "chat_attachments_participant_read" ON storage.objects;
CREATE POLICY "chat_attachments_participant_read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'chat-attachments' AND
  EXISTS (
    SELECT 1 FROM threads t
    WHERE t.id = (split_part((objects).name, '/', 1))::uuid
    AND (
      t.guest_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM organizers o
        WHERE o.id = t.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
      )
    )
  )
);

DROP POLICY IF EXISTS "chat_attachments_participant_insert" ON storage.objects;
CREATE POLICY "chat_attachments_participant_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'chat-attachments' AND
  EXISTS (
    SELECT 1 FROM threads t
    WHERE t.id = (split_part((objects).name, '/', 1))::uuid
    AND (
      t.guest_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM organizers o
        WHERE o.id = t.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
      )
    )
  )
);
