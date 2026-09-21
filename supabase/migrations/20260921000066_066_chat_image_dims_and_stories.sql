-- Migration: chat attachment aspect-ratio metadata + a real Stories system
-- (see .claude/notes/07-notifications.md, 14-photo-viewer.md).
--
-- Two independent additions:
-- 1. messages.attachment_width/height — lets the client render each chat
--    image at its own true aspect ratio instead of a fixed square/portrait
--    box (the white-side-rail bug).
-- 2. stories/story_views — a genuine 24h-lifecycle story system. Reuses the
--    EXISTING `follows(user_id, organizer_id)` table (003_social_chat.sql)
--    as the social graph, per this ticket's own instruction to check for
--    one before inventing a new model — a "host" in this app IS an
--    `organizers` row, and `follows` already ties a goer to one. No new
--    follow table needed. (Note: the web/iOS client never actually wrote to
--    `follows` before this pass — `toggleFollow()` was local-only React
--    state, keyed by event key, not organizer id. Fixed alongside this
--    migration so stories have a real audience — see GocContext.jsx.)

-- ============ 1. chat attachment dimensions ============
ALTER TABLE messages ADD COLUMN IF NOT EXISTS attachment_width int;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS attachment_height int;

-- ============ 2. stories ============
CREATE TABLE IF NOT EXISTS stories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id text NOT NULL REFERENCES organizers(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  media_path text NOT NULL,
  media_type text NOT NULL,
  width int,
  height int,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours')
);
CREATE INDEX IF NOT EXISTS idx_stories_organizer_active ON stories(organizer_id, expires_at);

CREATE TABLE IF NOT EXISTS story_views (
  story_id uuid NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
  viewer_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  viewed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, viewer_id)
);

ALTER TABLE stories ENABLE ROW LEVEL SECURITY;

-- Only an active (unexpired) story is ever selectable, and only by: its own
-- author, a co-owner of the organizer it belongs to, or someone who follows
-- that organizer. An expired row simply stops matching — no separate
-- "is it expired" branch needed anywhere else in the policy.
DROP POLICY IF EXISTS "stories_select_active_permitted" ON stories;
CREATE POLICY "stories_select_active_permitted" ON stories FOR SELECT TO authenticated
USING (
  expires_at > now() AND (
    author_id = auth.uid()
    OR EXISTS (SELECT 1 FROM organizers o WHERE o.id = stories.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
    OR EXISTS (SELECT 1 FROM follows f WHERE f.organizer_id = stories.organizer_id AND f.user_id = auth.uid())
  )
);

DROP POLICY IF EXISTS "stories_insert_own" ON stories;
CREATE POLICY "stories_insert_own" ON stories FOR INSERT TO authenticated
WITH CHECK (
  author_id = auth.uid() AND
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = stories.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);

DROP POLICY IF EXISTS "stories_delete_own" ON stories;
CREATE POLICY "stories_delete_own" ON stories FOR DELETE TO authenticated
USING (
  author_id = auth.uid()
  OR EXISTS (SELECT 1 FROM organizers o WHERE o.id = stories.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);

ALTER TABLE story_views ENABLE ROW LEVEL SECURITY;

-- A viewer can only ever write their OWN view row (the primary key on
-- (story_id, viewer_id) also makes this idempotent — re-viewing the same
-- story is a harmless upsert, not a duplicate row).
DROP POLICY IF EXISTS "story_views_insert_own" ON story_views;
CREATE POLICY "story_views_insert_own" ON story_views FOR INSERT TO authenticated
WITH CHECK (viewer_id = auth.uid());

-- A viewer can read their own view rows (so the client knows what it's
-- already recorded); a story's author/organizer co-owner can read all of
-- that story's views (a real view count, not required by this ticket's UI
-- today but cheap to allow correctly now rather than lock it down and redo
-- it later).
DROP POLICY IF EXISTS "story_views_select" ON story_views;
CREATE POLICY "story_views_select" ON story_views FOR SELECT TO authenticated
USING (
  viewer_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM stories st WHERE st.id = story_views.story_id AND (
      st.author_id = auth.uid()
      OR EXISTS (SELECT 1 FROM organizers o WHERE o.id = st.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
    )
  )
);

-- ============ storage bucket for story media ============
-- Path convention: `<organizer_id>/<file>` — same split_part(name,'/',1)
-- convention chat-attachments (065) and pay-qr already use, keyed on
-- organizer id instead of thread id since visibility here is
-- follows-based, not thread-membership-based.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('stories', 'stories', false, 20971520, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "stories_media_read" ON storage.objects;
CREATE POLICY "stories_media_read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'stories' AND (
    EXISTS (SELECT 1 FROM organizers o WHERE o.id = split_part((objects).name, '/', 1) AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
    OR EXISTS (SELECT 1 FROM follows f WHERE f.organizer_id = split_part((objects).name, '/', 1) AND f.user_id = auth.uid())
  )
);

DROP POLICY IF EXISTS "stories_media_insert" ON storage.objects;
CREATE POLICY "stories_media_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'stories' AND
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = split_part((objects).name, '/', 1) AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);

DROP POLICY IF EXISTS "stories_media_delete" ON storage.objects;
CREATE POLICY "stories_media_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'stories' AND
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = split_part((objects).name, '/', 1) AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);

-- ============ cleanup ============
-- Hard-deletes only stories that are ALREADY past expires_at (the WHERE
-- clause is the entire safety guarantee — never touches a live story no
-- matter when/how often this runs). story_views cascades. Returns the freed
-- media_paths so a caller can also remove the actual storage objects (a
-- plain SQL DELETE on `stories` cannot reach into the Storage backend
-- itself — the caller, e.g. an admin/cron script with the service-role key,
-- is expected to call storage.remove() on the returned paths, the same
-- division of responsibility 08-payment-documents.md's own retention sweep
-- already uses). Safe to call opportunistically/often — a no-op when
-- nothing has expired yet.
CREATE OR REPLACE FUNCTION cleanup_expired_stories()
RETURNS TABLE(freed_media_path text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  DELETE FROM stories WHERE expires_at <= now() RETURNING media_path;
END;
$$;
REVOKE ALL ON FUNCTION cleanup_expired_stories() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION cleanup_expired_stories() TO authenticated;
