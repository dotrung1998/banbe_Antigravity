-- Migration: Core Schema (ENUMs, profiles, organizers, events, event_photos)
-- Description: Creates custom ENUM types and the foundational tables for the events platform.

-- ============ ENUM Types ============
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_locale') THEN
    CREATE TYPE user_locale AS ENUM ('vi', 'en');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_status') THEN
    CREATE TYPE event_status AS ENUM ('draft', 'review', 'live', 'cancelled', 'ended');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_visibility') THEN
    CREATE TYPE event_visibility AS ENUM ('public', 'invite');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_approval') THEN
    CREATE TYPE event_approval AS ENUM ('instant', 'host_approves');
  END IF;
END $$;

-- ============ profiles ============
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL DEFAULT '',
  phone text DEFAULT '',
  phone_verified boolean NOT NULL DEFAULT false,
  avatar_url text,
  locale user_locale NOT NULL DEFAULT 'vi',
  role text NOT NULL DEFAULT 'participant',
  attended_count int NOT NULL DEFAULT 0,
  no_show_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ============ organizers ============
CREATE TABLE IF NOT EXISTS organizers (
  id text PRIMARY KEY,
  owner_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  user_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  name text NOT NULL,
  ig_handle text DEFAULT '',
  instagram text DEFAULT '',
  bio text DEFAULT '',
  about text DEFAULT '',
  hosting_since text DEFAULT '',
  verified boolean NOT NULL DEFAULT false,
  verify_requested_at timestamptz,
  pay_methods text[] DEFAULT '{}',
  bank_name text DEFAULT '',
  bank_account_name text DEFAULT '',
  bank_account_no text DEFAULT '',
  momo_phone text DEFAULT '',
  pay_qr_path text DEFAULT '',
  pay_note text DEFAULT '',
  refund_pledge text DEFAULT '',
  disputes_open int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ============ events ============
CREATE TABLE IF NOT EXISTS events (
  id text PRIMARY KEY,
  organizer_id text REFERENCES organizers(id) ON DELETE SET NULL,
  slug text UNIQUE,
  key text,
  name text NOT NULL,
  category text NOT NULL DEFAULT '',
  cat_key text,
  cat_label text,
  description text DEFAULT '',
  included text DEFAULT '',
  area text DEFAULT '',
  lat float8,
  lng float8,
  starts_at timestamptz,
  event_date date,
  event_time time,
  price_vnd int NOT NULL DEFAULT 0,
  price_cents bigint DEFAULT 0,
  capacity int NOT NULL DEFAULT 0,
  seats_remaining int DEFAULT 0,
  palette text DEFAULT 'concrete',
  greeting text DEFAULT '',
  visibility event_visibility NOT NULL DEFAULT 'public',
  approval event_approval NOT NULL DEFAULT 'instant',
  hold_minutes int NOT NULL DEFAULT 30,
  status event_status NOT NULL DEFAULT 'draft',
  cancelled_at timestamptz,
  cancel_reason text DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ============ event_photos ============
CREATE TABLE IF NOT EXISTS event_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text REFERENCES events(id) ON DELETE CASCADE,
  storage_path text NOT NULL,
  sort_order int NOT NULL DEFAULT 0
);

-- ============ Indexes ============
CREATE INDEX IF NOT EXISTS idx_events_status_starts_at ON events(status, starts_at);
CREATE INDEX IF NOT EXISTS idx_organizers_owner_id ON organizers(owner_id);

-- ============ Row Level Security ============
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "profiles_select_own" ON profiles;
CREATE POLICY "profiles_select_own" ON profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "profiles_insert_own" ON profiles;
CREATE POLICY "profiles_insert_own" ON profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
CREATE POLICY "profiles_update_own" ON profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

ALTER TABLE organizers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "organizers_select_public" ON organizers;
CREATE POLICY "organizers_select_public" ON organizers FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "organizers_insert_own" ON organizers;
CREATE POLICY "organizers_insert_own" ON organizers FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id OR auth.uid() = user_id);
DROP POLICY IF EXISTS "organizers_update_own" ON organizers;
CREATE POLICY "organizers_update_own" ON organizers FOR UPDATE TO authenticated USING (auth.uid() = owner_id OR auth.uid() = user_id) WITH CHECK (auth.uid() = owner_id OR auth.uid() = user_id);

ALTER TABLE events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "events_select_public" ON events;
CREATE POLICY "events_select_public" ON events FOR SELECT TO anon, authenticated USING (
  status = 'live'
  OR EXISTS (SELECT 1 FROM organizers o WHERE o.id = events.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);
DROP POLICY IF EXISTS "events_insert_own" ON events;
CREATE POLICY "events_insert_own" ON events FOR INSERT TO authenticated WITH CHECK (
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);
DROP POLICY IF EXISTS "events_update_own" ON events;
CREATE POLICY "events_update_own" ON events FOR UPDATE TO authenticated USING (
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = events.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
) WITH CHECK (
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = events.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);

ALTER TABLE event_photos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "event_photos_select_public" ON event_photos;
CREATE POLICY "event_photos_select_public" ON event_photos FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "event_photos_insert_own" ON event_photos;
CREATE POLICY "event_photos_insert_own" ON event_photos FOR INSERT TO authenticated WITH CHECK (
  EXISTS (SELECT 1 FROM events e WHERE e.id = event_id AND EXISTS (SELECT 1 FROM organizers o WHERE o.id = e.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())))
);
DROP POLICY IF EXISTS "event_photos_update_own" ON event_photos;
CREATE POLICY "event_photos_update_own" ON event_photos FOR UPDATE TO authenticated USING (
  EXISTS (SELECT 1 FROM events e WHERE e.id = event_id AND EXISTS (SELECT 1 FROM organizers o WHERE o.id = e.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())))
) WITH CHECK (
  EXISTS (SELECT 1 FROM events e WHERE e.id = event_id AND EXISTS (SELECT 1 FROM organizers o WHERE o.id = e.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())))
);
DROP POLICY IF EXISTS "event_photos_delete_own" ON event_photos;
CREATE POLICY "event_photos_delete_own" ON event_photos FOR DELETE TO authenticated USING (
  EXISTS (SELECT 1 FROM events e WHERE e.id = event_id AND EXISTS (SELECT 1 FROM organizers o WHERE o.id = e.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())))
);
