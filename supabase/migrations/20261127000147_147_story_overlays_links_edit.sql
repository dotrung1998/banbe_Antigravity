-- Story editing: text overlays + one tappable link on a media story, and the
-- ability for the author / organizer owner to edit them after posting.
-- Overlays are data (rendered live over the media), never burned into the
-- image, so an edit never re-uploads anything.

ALTER TABLE stories ADD COLUMN IF NOT EXISTS overlays jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE stories ADD COLUMN IF NOT EXISTS link_url text;
ALTER TABLE stories ADD COLUMN IF NOT EXISTS link_label text;

DO $$ BEGIN
  ALTER TABLE stories ADD CONSTRAINT stories_link_url_check
    CHECK (link_url IS NULL OR (length(link_url) <= 500 AND link_url ~* '^(https?|banbe)://'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE stories ADD CONSTRAINT stories_overlays_check
    CHECK (jsonb_typeof(overlays) = 'array' AND jsonb_array_length(overlays) <= 20);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Edit = overlays/link only. The policy lets the author or an organizer
-- owner update; the trigger below pins everything else.
DROP POLICY IF EXISTS "stories_update_own" ON stories;
CREATE POLICY "stories_update_own" ON stories FOR UPDATE TO authenticated
USING (
  expires_at > now() AND (
    author_id = auth.uid()
    OR EXISTS (SELECT 1 FROM organizers o WHERE o.id = stories.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
  )
)
WITH CHECK (
  author_id = auth.uid()
  OR EXISTS (SELECT 1 FROM organizers o WHERE o.id = stories.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);

CREATE OR REPLACE FUNCTION public.stories_edit_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.organizer_id IS DISTINCT FROM OLD.organizer_id
     OR NEW.author_id IS DISTINCT FROM OLD.author_id
     OR NEW.media_path IS DISTINCT FROM OLD.media_path
     OR NEW.media_type IS DISTINCT FROM OLD.media_type
     OR NEW.kind IS DISTINCT FROM OLD.kind
     OR NEW.event_id IS DISTINCT FROM OLD.event_id
     OR NEW.survey_id IS DISTINCT FROM OLD.survey_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.expires_at IS DISTINCT FROM OLD.expires_at THEN
    RAISE EXCEPTION 'Only a story''s overlays and link can be edited';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS stories_edit_guard ON stories;
CREATE TRIGGER stories_edit_guard BEFORE UPDATE ON stories
FOR EACH ROW EXECUTE FUNCTION public.stories_edit_guard();
