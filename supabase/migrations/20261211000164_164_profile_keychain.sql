-- 164: profile keychain (decorative charm on the profile card).
-- Additive only. See .claude/notes/35-foryou-alert-organizer-ensure-keychain.md
-- ("Shared keychain contract"). Visitors never read profile_keychains directly:
-- they go through get_profile_keychain(). Custom art lives in a PRIVATE bucket;
-- clients can never write to it (server-issued signed upload tokens only).

-- ---------------------------------------------------------------------------
-- Bucket (private, 256 KB, png/webp only)
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('keychain-art', 'keychain-art', false, 262144, ARRAY['image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE
  SET public = false, file_size_limit = 262144, allowed_mime_types = ARRAY['image/png', 'image/webp'];

-- ---------------------------------------------------------------------------
-- keychain_assets: written ONLY by the service role (api/media keychain_* ops)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.keychain_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  path text NOT NULL UNIQUE,
  content_type text NOT NULL CHECK (content_type IN ('image/png', 'image/webp')),
  bytes integer NOT NULL CHECK (bytes > 0 AND bytes <= 262144),
  width integer CHECK (width IS NULL OR width BETWEEN 32 AND 512),
  height integer CHECK (height IS NULL OR height BETWEEN 32 AND 512),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'ready', 'deleted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (path LIKE owner_id::text || '/%')
);
CREATE INDEX IF NOT EXISTS keychain_assets_owner_idx ON public.keychain_assets (owner_id, status);

ALTER TABLE public.keychain_assets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS keychain_assets_owner_select ON public.keychain_assets;
CREATE POLICY keychain_assets_owner_select ON public.keychain_assets
  FOR SELECT TO authenticated USING (owner_id = auth.uid());
-- No INSERT/UPDATE/DELETE policy: service role only.
REVOKE ALL ON public.keychain_assets FROM anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.keychain_assets FROM authenticated;
GRANT SELECT ON public.keychain_assets TO authenticated;

-- DB-level quota guard (the API enforces it first): max 3 non-deleted assets / user.
CREATE OR REPLACE FUNCTION public.keychain_assets_quota_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.status <> 'deleted' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('keychain_assets:' || NEW.owner_id::text, 0));
    IF (SELECT count(*) FROM public.keychain_assets
         WHERE owner_id = NEW.owner_id AND status <> 'deleted' AND id <> NEW.id) >= 3 THEN
      RAISE EXCEPTION 'KEYCHAIN_QUOTA_EXCEEDED' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.keychain_assets_quota_guard() FROM anon, authenticated, PUBLIC;
DROP TRIGGER IF EXISTS keychain_assets_quota ON public.keychain_assets;
CREATE TRIGGER keychain_assets_quota BEFORE INSERT ON public.keychain_assets
  FOR EACH ROW EXECUTE FUNCTION public.keychain_assets_quota_guard();

-- ---------------------------------------------------------------------------
-- profile_keychains: appearance metadata only (no sensor data, no positions)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profile_keychains (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT false,
  design_id text NOT NULL DEFAULT 'sky-star' CHECK (design_id IN (
    'sky-star','sky-moon','sky-cloud',
    'love-heart','love-ribbon','love-bow',
    'bloom-flower','bloom-tulip','bloom-strawberry','bloom-lemon',
    'cafe-cup','cafe-note','cafe-vinyl',
    'pals-cat','pals-bear','pals-paw',
    'trip-ticket','trip-plane','trip-compass','trip-suitcase',
    'banbe-b','banbe-stub','banbe-spark','banbe-wave',
    'custom')),
  anchor text NOT NULL DEFAULT 'top_right' CHECK (anchor IN ('top_left','top_right','bottom_left','bottom_right')),
  size text NOT NULL DEFAULT 'm' CHECK (size IN ('s','m','l')),
  motion_enabled boolean NOT NULL DEFAULT true,
  custom_asset_id uuid REFERENCES public.keychain_assets(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (design_id <> 'custom' OR custom_asset_id IS NOT NULL)
);

ALTER TABLE public.profile_keychains ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS profile_keychains_owner_select ON public.profile_keychains;
DROP POLICY IF EXISTS profile_keychains_owner_insert ON public.profile_keychains;
DROP POLICY IF EXISTS profile_keychains_owner_update ON public.profile_keychains;
DROP POLICY IF EXISTS profile_keychains_owner_delete ON public.profile_keychains;
CREATE POLICY profile_keychains_owner_select ON public.profile_keychains
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY profile_keychains_owner_insert ON public.profile_keychains
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY profile_keychains_owner_update ON public.profile_keychains
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY profile_keychains_owner_delete ON public.profile_keychains
  FOR DELETE TO authenticated USING (user_id = auth.uid());
REVOKE ALL ON public.profile_keychains FROM anon, PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profile_keychains TO authenticated;

-- ---------------------------------------------------------------------------
-- Internal: build the camelCase config (service/definer use only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.keychain_config_json(p_uid uuid, p_public boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE r public.profile_keychains%ROWTYPE; a public.keychain_assets%ROWTYPE; v_asset jsonb := NULL;
BEGIN
  SELECT * INTO r FROM public.profile_keychains WHERE user_id = p_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('enabled', false, 'designId', 'sky-star', 'anchor', 'top_right', 'size', 'm',
                              'motionEnabled', true, 'customAsset', NULL, 'updatedAt', NULL);
  END IF;
  IF r.custom_asset_id IS NOT NULL AND (NOT p_public OR r.design_id = 'custom') THEN
    SELECT * INTO a FROM public.keychain_assets WHERE id = r.custom_asset_id AND owner_id = p_uid AND status = 'ready';
    IF FOUND THEN
      v_asset := jsonb_build_object('id', a.id, 'path', a.path, 'width', a.width, 'height', a.height);
    END IF;
  END IF;
  RETURN jsonb_build_object('enabled', r.enabled, 'designId', r.design_id, 'anchor', r.anchor, 'size', r.size,
                            'motionEnabled', r.motion_enabled, 'customAsset', v_asset, 'updatedAt', r.updated_at);
END;
$$;
REVOKE ALL ON FUNCTION public.keychain_config_json(uuid, boolean) FROM anon, authenticated, PUBLIC;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_keychain()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  RETURN jsonb_build_object('success', true, 'keychain', public.keychain_config_json(v_uid, false));
END;
$$;

CREATE OR REPLACE FUNCTION public.save_my_keychain(p_config jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  cur public.profile_keychains%ROWTYPE;
  v_enabled boolean; v_design text; v_anchor text; v_size text; v_motion boolean; v_asset uuid;
  v_tmp text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_CONFIG');
  END IF;

  SELECT * INTO cur FROM public.profile_keychains WHERE user_id = v_uid;
  v_enabled := COALESCE(cur.enabled, false);
  v_design  := COALESCE(cur.design_id, 'sky-star');
  v_anchor  := COALESCE(cur.anchor, 'top_right');
  v_size    := COALESCE(cur.size, 'm');
  v_motion  := COALESCE(cur.motion_enabled, true);
  v_asset   := cur.custom_asset_id;

  IF p_config ? 'enabled' THEN
    IF jsonb_typeof(p_config->'enabled') <> 'boolean' THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_ENABLED'); END IF;
    v_enabled := (p_config->>'enabled')::boolean;
  END IF;
  IF p_config ? 'motionEnabled' THEN
    IF jsonb_typeof(p_config->'motionEnabled') <> 'boolean' THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_MOTION'); END IF;
    v_motion := (p_config->>'motionEnabled')::boolean;
  END IF;
  IF p_config ? 'designId' THEN
    IF jsonb_typeof(p_config->'designId') <> 'string' OR (p_config->>'designId') NOT IN (
      'sky-star','sky-moon','sky-cloud','love-heart','love-ribbon','love-bow',
      'bloom-flower','bloom-tulip','bloom-strawberry','bloom-lemon','cafe-cup','cafe-note','cafe-vinyl',
      'pals-cat','pals-bear','pals-paw','trip-ticket','trip-plane','trip-compass','trip-suitcase',
      'banbe-b','banbe-stub','banbe-spark','banbe-wave','custom') THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_DESIGN');
    END IF;
    v_design := p_config->>'designId';
  END IF;
  IF p_config ? 'anchor' THEN
    IF jsonb_typeof(p_config->'anchor') <> 'string' OR (p_config->>'anchor') NOT IN ('top_left','top_right','bottom_left','bottom_right') THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_ANCHOR');
    END IF;
    v_anchor := p_config->>'anchor';
  END IF;
  IF p_config ? 'size' THEN
    IF jsonb_typeof(p_config->'size') <> 'string' OR (p_config->>'size') NOT IN ('s','m','l') THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_SIZE');
    END IF;
    v_size := p_config->>'size';
  END IF;
  IF p_config ? 'customAssetId' THEN
    IF jsonb_typeof(p_config->'customAssetId') = 'null' THEN
      v_asset := NULL;
    ELSIF jsonb_typeof(p_config->'customAssetId') = 'string' THEN
      v_tmp := p_config->>'customAssetId';
      IF v_tmp !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_ASSET');
      END IF;
      v_asset := v_tmp::uuid;
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_ASSET');
    END IF;
  END IF;

  -- A referenced asset must be a READY asset owned by the caller.
  IF v_asset IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.keychain_assets WHERE id = v_asset AND owner_id = v_uid AND status = 'ready'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ASSET_NOT_READY');
  END IF;
  IF v_design = 'custom' AND v_asset IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'CUSTOM_ASSET_REQUIRED');
  END IF;

  INSERT INTO public.profile_keychains (user_id, enabled, design_id, anchor, size, motion_enabled, custom_asset_id, updated_at)
  VALUES (v_uid, v_enabled, v_design, v_anchor, v_size, v_motion, v_asset, now())
  ON CONFLICT (user_id) DO UPDATE
    SET enabled = EXCLUDED.enabled, design_id = EXCLUDED.design_id, anchor = EXCLUDED.anchor, size = EXCLUDED.size,
        motion_enabled = EXCLUDED.motion_enabled, custom_asset_id = EXCLUDED.custom_asset_id, updated_at = now();

  RETURN jsonb_build_object('success', true, 'keychain', public.keychain_config_json(v_uid, false));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_profile_keychain(p_handle text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_owner uuid; v_en boolean;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  SELECT id INTO v_owner FROM public.profiles WHERE lower(handle) = lower(trim(p_handle));
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND'); END IF;
  SELECT enabled INTO v_en FROM public.profile_keychains WHERE user_id = v_owner;
  IF NOT COALESCE(v_en, false) THEN RETURN jsonb_build_object('success', true, 'keychain', NULL); END IF;
  RETURN jsonb_build_object('success', true, 'keychain', public.keychain_config_json(v_owner, true));
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_keychain() FROM anon, PUBLIC;
REVOKE ALL ON FUNCTION public.save_my_keychain(jsonb) FROM anon, PUBLIC;
REVOKE ALL ON FUNCTION public.get_profile_keychain(text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_keychain() TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_my_keychain(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_keychain(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Storage policies: read only. NO client INSERT/UPDATE/DELETE policy exists,
-- so uploads can only happen through server-issued signed upload tokens.
-- ---------------------------------------------------------------------------
-- Definer helper: profile_keychains is owner-only under RLS, so a visitor-side
-- policy subquery could never see it.
CREATE OR REPLACE FUNCTION public.keychain_art_visible(p_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.profile_keychains k
      JOIN public.keychain_assets a ON a.id = k.custom_asset_id AND a.owner_id = k.user_id
     WHERE k.enabled AND k.design_id = 'custom' AND a.status = 'ready'
       AND a.path = p_name AND split_part(p_name, '/', 1) = k.user_id::text
  );
$$;
REVOKE ALL ON FUNCTION public.keychain_art_visible(text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.keychain_art_visible(text) TO authenticated;

DROP POLICY IF EXISTS keychain_art_select ON storage.objects;
CREATE POLICY keychain_art_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'keychain-art'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR public.keychain_art_visible(name)
    )
  );

-- ---------------------------------------------------------------------------
-- Rollback (manual):
--   DROP POLICY IF EXISTS keychain_art_select ON storage.objects;
--   DROP FUNCTION IF EXISTS public.keychain_art_visible(text);
--   DROP FUNCTION IF EXISTS public.get_profile_keychain(text);
--   DROP FUNCTION IF EXISTS public.save_my_keychain(jsonb);
--   DROP FUNCTION IF EXISTS public.get_my_keychain();
--   DROP FUNCTION IF EXISTS public.keychain_config_json(uuid, boolean);
--   DROP TABLE IF EXISTS public.profile_keychains;
--   DROP TABLE IF EXISTS public.keychain_assets;
--   DROP FUNCTION IF EXISTS public.keychain_assets_quota_guard();
--   (delete objects in bucket keychain-art, then the bucket)
-- ---------------------------------------------------------------------------
