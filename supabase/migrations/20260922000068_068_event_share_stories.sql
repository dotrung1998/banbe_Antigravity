-- Migration: "Share event to Story" (see .claude/notes/07-notifications.md
-- — Task 4 of the 2026-09-22 real-device follow-up).
--
-- Smallest compatible extension to the existing `stories` table (066)
-- rather than a parallel `story_events` table: a `kind` discriminator
-- ('media' | 'event_share') plus a nullable `event_id`, since an
-- event-share story is still, in every other respect, a normal story —
-- same organizer_id/author_id, same 24h expires_at default, same RLS
-- audience (author/co-owner/follower), same story_views tracking, same
-- cleanup_expired_stories() sweep. No RLS policy needed above what 066
-- already wrote — SELECT/DELETE are already organizer_id-scoped, which
-- covers an event_share row identically to a media row.

ALTER TABLE stories ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'media';
ALTER TABLE stories ADD COLUMN IF NOT EXISTS event_id text REFERENCES events(id) ON DELETE SET NULL;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'stories_kind_check') THEN
    ALTER TABLE stories ADD CONSTRAINT stories_kind_check CHECK (kind IN ('media', 'event_share'));
  END IF;
END $$;

-- Ownership is enforced HERE, server-side, not by hiding the "Share to
-- Story" button client-side — a client-passed event_id is never trusted on
-- its own. Mirrors the same owner_id/user_id ownership check every other
-- organizer-scoped write in this schema already uses (organizers_update_own,
-- events RLS, stories_insert_own). SECURITY DEFINER so it can INSERT into
-- `stories` on the caller's behalf after that check passes — the same
-- pattern this codebase already uses for ownership-sensitive writes (e.g.
-- admin_purge_test_dispute_thread, 050/052).
CREATE OR REPLACE FUNCTION create_event_share_story(p_event_id text)
RETURNS stories
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id text;
  v_uid uuid := auth.uid();
  v_story stories;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_SIGNED_IN';
  END IF;

  SELECT organizer_id INTO v_org_id FROM events WHERE id = p_event_id;
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND';
  END IF;

  -- The actual event -> organizer -> owner_id/user_id relationship, same
  -- check every other organizer-write RLS policy in this schema uses — a
  -- goer who merely attended/saved/viewed the event never matches this.
  IF NOT EXISTS (
    SELECT 1 FROM organizers o WHERE o.id = v_org_id AND (o.owner_id = v_uid OR o.user_id = v_uid)
  ) THEN
    RAISE EXCEPTION 'NOT_ORGANIZER_OWNER';
  END IF;

  INSERT INTO stories (organizer_id, author_id, media_path, media_type, kind, event_id)
  VALUES (v_org_id, v_uid, '', 'application/x-banbe-event-share', 'event_share', p_event_id)
  RETURNING * INTO v_story;

  RETURN v_story;
END;
$$;
REVOKE ALL ON FUNCTION create_event_share_story(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_event_share_story(text) TO authenticated;
