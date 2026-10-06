-- Published share card (merged host/member profile pass).
--
-- Until now the share-card design (colours / background photo) lived only on the
-- device that edited it (localStorage on web, UserDefaults on iOS), so a goer
-- sharing someone else's card could only ever get the default design, and an
-- editor's design never reached anyone else. A card is now PUBLISHED: the owner
-- edits a local draft and explicitly saves it, and everyone who opens that
-- profile's "Share" sees (and can share) the published design, read-only.
--
-- Style shape (same on web + iOS): { topHex, bottomHex, textHex, photo }
--   *Hex  = '#RRGGBB'
--   photo = optional 'data:image/(jpeg|png|webp);base64,...' (compressed
--           client-side; capped below), or absent/null for a plain gradient.
--
-- Stored as jsonb on the two owner rows and only reachable through the two
-- SECURITY DEFINER functions below, so no new table policy is opened.

ALTER TABLE public.profiles   ADD COLUMN IF NOT EXISTS share_card jsonb;
ALTER TABLE public.organizers ADD COLUMN IF NOT EXISTS share_card jsonb;

-- Validates + normalises a style object; returns NULL when it is not valid.
CREATE OR REPLACE FUNCTION public.bb_clean_share_card(p_style jsonb)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_top text := p_style->>'topHex';
  v_bottom text := p_style->>'bottomHex';
  v_text text := p_style->>'textHex';
  v_photo text := p_style->>'photo';
  v_out jsonb;
BEGIN
  IF p_style IS NULL OR jsonb_typeof(p_style) <> 'object' THEN RETURN NULL; END IF;
  IF v_top !~ '^#[0-9A-Fa-f]{6}$' OR v_bottom !~ '^#[0-9A-Fa-f]{6}$' OR v_text !~ '^#[0-9A-Fa-f]{6}$' THEN RETURN NULL; END IF;
  v_out := jsonb_build_object('topHex', upper(v_top), 'bottomHex', upper(v_bottom), 'textHex', upper(v_text));
  IF v_photo IS NOT NULL AND v_photo <> '' THEN
    IF v_photo !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' OR length(v_photo) > 400000 THEN RETURN NULL; END IF;
    v_out := v_out || jsonb_build_object('photo', v_photo);
  END IF;
  RETURN v_out;
END;
$$;

-- Read the published card. p_kind 'member' => p_id is the profile handle;
-- 'host' => p_id is the organizer id. NULL when nothing has been published.
CREATE OR REPLACE FUNCTION public.get_published_share_card(p_kind text, p_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_kind = 'member' THEN (SELECT share_card FROM public.profiles WHERE lower(handle) = lower(p_id) LIMIT 1)
    WHEN p_kind = 'host'   THEN (SELECT share_card FROM public.organizers WHERE id::text = p_id LIMIT 1)
  END;
$$;

-- Publish (or clear, with p_style = NULL) the caller's own card. 'member' always
-- targets the caller's own profile; 'host' requires owning that organizer.
CREATE OR REPLACE FUNCTION public.publish_share_card(p_kind text, p_id text, p_style jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_clean jsonb;
  v_rows int;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'not_authenticated'); END IF;
  IF p_style IS NULL OR p_style = 'null'::jsonb THEN
    v_clean := NULL;
  ELSE
    v_clean := public.bb_clean_share_card(p_style);
    IF v_clean IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'invalid_style'); END IF;
  END IF;

  IF p_kind = 'member' THEN
    UPDATE public.profiles SET share_card = v_clean WHERE id = v_uid;
  ELSIF p_kind = 'host' THEN
    UPDATE public.organizers SET share_card = v_clean
     WHERE id::text = p_id AND (owner_id = v_uid OR user_id = v_uid);
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'invalid_kind');
  END IF;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN RETURN jsonb_build_object('success', false, 'error', 'not_allowed'); END IF;
  RETURN jsonb_build_object('success', true, 'share_card', v_clean);
END;
$$;

REVOKE ALL ON FUNCTION public.get_published_share_card(text, text) FROM public;
REVOKE ALL ON FUNCTION public.publish_share_card(text, text, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.get_published_share_card(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_share_card(text, text, jsonb) TO authenticated;
