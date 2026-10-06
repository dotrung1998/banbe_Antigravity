-- 153: Cloudflare R2 hybrid for PUBLIC media (phase one). ADDITIVE ONLY.
-- See .claude/notes/28-r2-hybrid-media.md. Nothing here changes any existing
-- column, policy or bucket; legacy Supabase Storage keeps working unchanged.
--
-- media_assets is the authoritative record for objects delivered from R2.
-- All writes are service-role (api/media.js); clients can only read their own
-- rows. Public delivery needs no row read: the clients derive the URL from the
-- *_r2_ref string stored on the referencing row.

CREATE TABLE IF NOT EXISTS public.media_assets (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider         text NOT NULL DEFAULT 'r2' CHECK (provider IN ('r2')),
  kind             text NOT NULL CHECK (kind IN ('event_photo', 'organizer_avatar')),
  scope            text NOT NULL,                 -- 'ev-<eventId>' | 'org-<organizerId>'
  event_id         text REFERENCES public.events(id) ON DELETE SET NULL,
  organizer_id     text REFERENCES public.organizers(id) ON DELETE SET NULL,
  owner_user_id    uuid NOT NULL,                 -- the verified uploader (from the JWT, never the client)
  ext              text NOT NULL CHECK (ext IN ('jpg', 'png', 'webp')),
  version          int  NOT NULL DEFAULT 1,       -- key prefix 'v<version>/'
  status           text NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'published', 'deleted', 'failed')),
  variants         jsonb NOT NULL DEFAULT '{}'::jsonb,  -- {thumb:{key,bytes,w,h,sha256},card:{...},full:{...}}
  declared         jsonb NOT NULL DEFAULT '{}'::jsonb,  -- what init authorised: {thumb:{bytes,contentType},...}
  source           text NOT NULL DEFAULT 'upload' CHECK (source IN ('upload', 'migration')),
  legacy_bucket    text,                          -- migration: the Supabase object this was copied from
  legacy_path      text,
  legacy_sha256    text,
  idempotency_key  text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  published_at     timestamptz,
  deleted_at       timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS media_assets_idem_uq
  ON public.media_assets (owner_user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS media_assets_legacy_uq
  ON public.media_assets (legacy_bucket, legacy_path) WHERE legacy_path IS NOT NULL AND status <> 'deleted';
CREATE INDEX IF NOT EXISTS media_assets_event_idx ON public.media_assets (event_id) WHERE status = 'published';
CREATE INDEX IF NOT EXISTS media_assets_org_idx   ON public.media_assets (organizer_id) WHERE status = 'published';
CREATE INDEX IF NOT EXISTS media_assets_pending_idx ON public.media_assets (created_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS media_assets_owner_recent_idx ON public.media_assets (owner_user_id, created_at DESC);

ALTER TABLE public.media_assets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS media_assets_owner_read ON public.media_assets;
CREATE POLICY media_assets_owner_read ON public.media_assets
  FOR SELECT TO authenticated USING (owner_user_id = auth.uid());
-- No INSERT/UPDATE/DELETE policies: only the service role (which bypasses RLS) writes.
REVOKE ALL ON public.media_assets FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.media_assets FROM authenticated;

-- Nullable pointers. Legacy columns (storage_path / cover_image / avatar_path)
-- are never rewritten for migrated assets, so older app builds keep rendering
-- from Supabase Storage. Clients prefer *_r2_ref only when their read flag is on.
ALTER TABLE public.event_photos ADD COLUMN IF NOT EXISTS r2_ref text;
ALTER TABLE public.events       ADD COLUMN IF NOT EXISTS cover_r2_ref text;
ALTER TABLE public.organizers   ADD COLUMN IF NOT EXISTS avatar_r2_ref text;

-- Defence in depth: a ref must be the exact shape the resolvers accept.
DO $$ BEGIN
  ALTER TABLE public.event_photos ADD CONSTRAINT event_photos_r2_ref_shape
    CHECK (r2_ref IS NULL OR r2_ref ~ '^r2:ev-[A-Za-z0-9_-]+/[0-9a-f-]{36}\.(jpg|png|webp)$');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.events ADD CONSTRAINT events_cover_r2_ref_shape
    CHECK (cover_r2_ref IS NULL OR cover_r2_ref ~ '^r2:ev-[A-Za-z0-9_-]+/[0-9a-f-]{36}\.(jpg|png|webp)$');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.organizers ADD CONSTRAINT organizers_avatar_r2_ref_shape
    CHECK (avatar_r2_ref IS NULL OR avatar_r2_ref ~ '^r2:org-[A-Za-z0-9_-]+/[0-9a-f-]{36}\.(jpg|png|webp)$');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- A client may never write its own *_r2_ref (only api/media.js, with the
-- service role): a forged ref would point other users' browsers at an
-- arbitrary key on the media domain. Column-level REVOKE would be a no-op here
-- (Supabase grants table-level privileges), so this is enforced by trigger.
-- The ref's scope must also match the row it sits on.
CREATE OR REPLACE FUNCTION public.guard_r2_ref() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $fn$
DECLARE
  v_new text; v_old text; v_scope text;
BEGIN
  IF TG_TABLE_NAME = 'event_photos' THEN
    v_new := NEW.r2_ref;  v_scope := 'ev-' || NEW.event_id;
    v_old := CASE WHEN TG_OP = 'UPDATE' THEN OLD.r2_ref END;
  ELSIF TG_TABLE_NAME = 'events' THEN
    v_new := NEW.cover_r2_ref;  v_scope := 'ev-' || NEW.id;
    v_old := CASE WHEN TG_OP = 'UPDATE' THEN OLD.cover_r2_ref END;
  ELSE
    v_new := NEW.avatar_r2_ref;  v_scope := 'org-' || NEW.id;
    v_old := CASE WHEN TG_OP = 'UPDATE' THEN OLD.avatar_r2_ref END;
  END IF;

  IF v_new IS NOT DISTINCT FROM v_old THEN RETURN NEW; END IF;      -- untouched
  IF coalesce(auth.role(), current_setting('request.jwt.claim.role', true), '') = 'service_role'
     OR current_user NOT IN ('authenticated', 'anon') THEN          -- service role / migrations
    IF v_new IS NOT NULL AND position('r2:' || v_scope || '/' IN v_new) <> 1 THEN
      RAISE EXCEPTION 'r2_ref scope mismatch' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'r2_ref is server-managed' USING ERRCODE = '42501';
END $fn$;

DROP TRIGGER IF EXISTS event_photos_guard_r2_ref ON public.event_photos;
CREATE TRIGGER event_photos_guard_r2_ref BEFORE INSERT OR UPDATE ON public.event_photos
  FOR EACH ROW EXECUTE FUNCTION public.guard_r2_ref();
DROP TRIGGER IF EXISTS events_guard_r2_ref ON public.events;
CREATE TRIGGER events_guard_r2_ref BEFORE INSERT OR UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.guard_r2_ref();
DROP TRIGGER IF EXISTS organizers_guard_r2_ref ON public.organizers;
CREATE TRIGGER organizers_guard_r2_ref BEFORE INSERT OR UPDATE ON public.organizers
  FOR EACH ROW EXECUTE FUNCTION public.guard_r2_ref();
