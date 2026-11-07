-- Migration: Social & Chat (threads, messages, favorites, follows, invites)
-- Description: Creates social interaction tables for chat threads, messages, favorites, follows, and invites.

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_kind') THEN
    CREATE TYPE message_kind AS ENUM ('text', 'system');
  END IF;
END $$;

-- ============ threads ============
CREATE TABLE IF NOT EXISTS threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text REFERENCES events(id) ON DELETE CASCADE,
  guest_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  organizer_id text REFERENCES organizers(id) ON DELETE CASCADE,
  UNIQUE (event_id, guest_id)
);

-- ============ messages ============
CREATE TABLE IF NOT EXISTS messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid REFERENCES threads(id) ON DELETE CASCADE,
  sender_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  body text NOT NULL,
  kind message_kind NOT NULL DEFAULT 'text',
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);

-- ============ favorites ============
CREATE TABLE IF NOT EXISTS favorites (
  user_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  event_id text REFERENCES events(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, event_id)
);

-- ============ follows ============
CREATE TABLE IF NOT EXISTS follows (
  user_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  organizer_id text REFERENCES organizers(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, organizer_id)
);

-- ============ invites ============
CREATE TABLE IF NOT EXISTS invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text REFERENCES events(id) ON DELETE CASCADE,
  phone text NOT NULL,
  claimed_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  claimed_at timestamptz
);

-- ============ Indexes ============
CREATE INDEX IF NOT EXISTS idx_messages_thread_created ON messages(thread_id, created_at);

-- ============ Row Level Security ============
ALTER TABLE threads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "threads_select_participant" ON threads;
CREATE POLICY "threads_select_participant" ON threads FOR SELECT TO authenticated USING (
  auth.uid() = guest_id 
  OR EXISTS (
    SELECT 1 FROM organizers o 
    WHERE o.id = threads.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);
DROP POLICY IF EXISTS "threads_insert_guest" ON threads;
CREATE POLICY "threads_insert_guest" ON threads FOR INSERT TO authenticated WITH CHECK (auth.uid() = guest_id);

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "messages_select_thread_participant" ON messages;
CREATE POLICY "messages_select_thread_participant" ON messages FOR SELECT TO authenticated USING (
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
DROP POLICY IF EXISTS "messages_insert_participant" ON messages;
CREATE POLICY "messages_insert_participant" ON messages FOR INSERT TO authenticated WITH CHECK (
  auth.uid() = sender_id
  AND EXISTS (
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

ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "favorites_select_own" ON favorites;
CREATE POLICY "favorites_select_own" ON favorites FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "favorites_insert_own" ON favorites;
CREATE POLICY "favorites_insert_own" ON favorites FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "favorites_delete_own" ON favorites;
CREATE POLICY "favorites_delete_own" ON favorites FOR DELETE TO authenticated USING (auth.uid() = user_id);

ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "follows_select_own" ON follows;
CREATE POLICY "follows_select_own" ON follows FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "follows_insert_own" ON follows;
CREATE POLICY "follows_insert_own" ON follows FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "follows_delete_own" ON follows;
CREATE POLICY "follows_delete_own" ON follows FOR DELETE TO authenticated USING (auth.uid() = user_id);

ALTER TABLE invites ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "invites_select_host" ON invites;
CREATE POLICY "invites_select_host" ON invites FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM events e
    JOIN organizers o ON e.organizer_id = o.id
    WHERE e.id = invites.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);
DROP POLICY IF EXISTS "invites_insert_host" ON invites;
CREATE POLICY "invites_insert_host" ON invites FOR INSERT TO authenticated WITH CHECK (
  EXISTS (
    SELECT 1 FROM events e
    JOIN organizers o ON e.organizer_id = o.id
    WHERE e.id = invites.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);
DROP POLICY IF EXISTS "invites_update_host" ON invites;
CREATE POLICY "invites_update_host" ON invites FOR UPDATE TO authenticated USING (
  EXISTS (
    SELECT 1 FROM events e
    JOIN organizers o ON e.organizer_id = o.id
    WHERE e.id = invites.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
) WITH CHECK (
  EXISTS (
    SELECT 1 FROM events e
    JOIN organizers o ON e.organizer_id = o.id
    WHERE e.id = invites.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);
