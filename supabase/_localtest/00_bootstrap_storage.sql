-- LOCAL TEST HARNESS ONLY — never deployed, not part of the migration chain.
-- The real Supabase `storage` schema is created by the storage service, which
-- does not run inside a bare postgres container. These migrations assume it
-- exists, so recreate the minimum surface they touch: storage.buckets (005)
-- and storage.objects (the RLS policies in 005/056/065/066/079/...).

CREATE SCHEMA IF NOT EXISTS storage;

CREATE TABLE IF NOT EXISTS storage.buckets (
  id text PRIMARY KEY,
  name text NOT NULL,
  owner uuid,
  public boolean DEFAULT false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS storage.objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id text REFERENCES storage.buckets(id),
  name text,
  owner uuid,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  metadata jsonb
);

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Real Supabase's auth.users carries these; migrations 006/123/124 reference
-- them (phone_confirmed_at) or ALTER them (raw_user_meta_data -> jsonb).
-- The container's auth.users predates them.
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS phone_confirmed_at timestamptz;
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS date_of_birth date;
ALTER TABLE auth.users ALTER COLUMN raw_user_meta_data TYPE jsonb;

-- Migration 123 binds public.dob_session_confirmations to auth.sessions(id).
CREATE TABLE IF NOT EXISTS auth.sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Provided by the real storage service; migration 164's storage policy calls it.
CREATE OR REPLACE FUNCTION storage.foldername(name text)
RETURNS text[] LANGUAGE plpgsql AS $$
DECLARE _parts text[];
BEGIN
  SELECT string_to_array(name, '/') INTO _parts;
  RETURN _parts[1:array_length(_parts, 1) - 1];
END
$$;
