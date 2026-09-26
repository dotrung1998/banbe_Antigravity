-- Migration 087: Real event discovery, media (cover + gallery), and structured "Bao gồm" (inclusions).
--
-- 1. Schema additions on `events`:
--    - cover_image: stable selected cover reference (storage path or URL).
--    - included_items: structured array of up to 3 items [{ label, detail }].
-- 2. Storage policies for event-photos: allow authenticated hosts to update/delete
--    their own event photos to prevent orphaned objects on partial upload failures.
-- 3. Canonical category normalization helper.
-- 4. Server-side validations:
--    - Past dates rejected when submitting upcoming events.
--    - "Bao gồm" items length and count validated (max 3 items, label <= 60, detail <= 300).
-- 5. Updated create_event_draft and resubmit_event_for_review.
-- 6. update_event_media_and_details RPC for post-submission edits on owned events.
-- 7. One-time forward normalization of existing real event rows (including test-s-ki-n-8444c8).

-- 1. Schema additions
ALTER TABLE events ADD COLUMN IF NOT EXISTS cover_image text DEFAULT '';
ALTER TABLE events ADD COLUMN IF NOT EXISTS included_items jsonb DEFAULT '[]'::jsonb;

-- 2. Storage object policies for event-photos (bucket is already public for read, host for insert)
DROP POLICY IF EXISTS "event_photos_host_delete" ON storage.objects;
CREATE POLICY "event_photos_host_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'event-photos' AND
  EXISTS (
    SELECT 1 FROM organizers o
    WHERE o.owner_id = auth.uid() OR o.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "event_photos_host_update" ON storage.objects;
CREATE POLICY "event_photos_host_update"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'event-photos' AND
  EXISTS (
    SELECT 1 FROM organizers o
    WHERE o.owner_id = auth.uid() OR o.user_id = auth.uid()
  )
);

-- 3. Canonical category normalization
CREATE OR REPLACE FUNCTION public.normalize_event_category(p_cat text)
RETURNS TABLE(cat_key text, cat_label text, category text) LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_raw text := lower(trim(COALESCE(p_cat, '')));
BEGIN
  IF v_raw IN ('supper', 'supper club', 'supper_club', 'ẩm thực', 'am thuc', 'food') THEN
    RETURN QUERY SELECT 'supper'::text, 'Supper club'::text, 'Supper club'::text;
  ELSIF v_raw IN ('fashion', 'thời trang', 'thoi trang') THEN
    RETURN QUERY SELECT 'fashion'::text, 'Thời trang'::text, 'Thời trang'::text;
  ELSIF v_raw IN ('gallery', 'phòng tranh', 'phong tranh', 'triển lãm', 'trien lam', 'art') THEN
    RETURN QUERY SELECT 'gallery'::text, 'Phòng tranh'::text, 'Phòng tranh'::text;
  ELSIF v_raw IN ('music', 'nhạc', 'nhac', 'âm nhạc', 'am nhac') THEN
    RETURN QUERY SELECT 'music'::text, 'Nhạc'::text, 'Nhạc'::text;
  ELSIF v_raw IN ('popup', 'pop-up', 'pop up') THEN
    RETURN QUERY SELECT 'popup'::text, 'Pop-up'::text, 'Pop-up'::text;
  ELSE
    RETURN QUERY SELECT COALESCE(NULLIF(v_raw, ''), 'all')::text,
                        COALESCE(NULLIF(trim(p_cat), ''), 'All')::text,
                        COALESCE(NULLIF(trim(p_cat), ''), 'All')::text;
  END IF;
END;
$$;

-- 4. Update create_event_draft
CREATE OR REPLACE FUNCTION create_event_draft(
  p_name text, p_category text, p_description text, p_location text,
  p_event_date date, p_event_time time, p_price_vnd bigint, p_capacity int,
  p_organizer_name text, p_instagram text DEFAULT '', p_about text DEFAULT '',
  p_cover_image text DEFAULT '',
  p_included_items jsonb DEFAULT '[]'::jsonb
) RETURNS events LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer organizers%ROWTYPE;
  v_event events%ROWTYPE;
  v_org_id text;
  v_event_id text;
  v_role text;
  v_starts_at timestamptz;
  v_cat_key text;
  v_cat_label text;
  v_category text;
  v_item jsonb;
  v_label text;
  v_detail text;
  v_included_labels text[] := ARRAY[]::text[];
  v_included_text text := '';
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 OR p_capacity IS NULL OR p_capacity < 1 THEN
    RAISE EXCEPTION 'INVALID_EVENT';
  END IF;

  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role IS NULL OR v_role NOT IN ('organizer', 'admin') THEN
    RAISE EXCEPTION 'FORBIDDEN: Only organizers can create events.';
  END IF;

  SELECT * INTO v_organizer FROM organizers WHERE owner_id = auth.uid() OR user_id = auth.uid() ORDER BY created_at LIMIT 1;
  IF NOT FOUND THEN
    v_org_id := 'org_' || substr(md5(gen_random_uuid()::text), 1, 8);
    INSERT INTO organizers(id, owner_id, user_id, name, ig_handle, instagram, bio, about)
    VALUES (v_org_id, auth.uid(), auth.uid(), COALESCE(NULLIF(trim(p_organizer_name), ''), 'Organizer'), p_instagram, p_instagram, p_about, p_about)
    RETURNING * INTO v_organizer;
  ELSE
    UPDATE organizers SET
      name = COALESCE(NULLIF(trim(p_organizer_name), ''), name),
      instagram = COALESCE(p_instagram, instagram),
      about = COALESCE(p_about, about)
    WHERE id = v_organizer.id;
  END IF;

  v_event_id := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(md5(gen_random_uuid()::text), 1, 6);

  v_starts_at := CASE WHEN p_event_date IS NOT NULL AND p_event_time IS NOT NULL
                       THEN (p_event_date + p_event_time) AT TIME ZONE 'Asia/Ho_Chi_Minh'
                       ELSE NULL END;

  IF v_starts_at IS NOT NULL AND v_starts_at < (now() - interval '5 minutes') THEN
    RAISE EXCEPTION 'PAST_EVENT_NOT_ALLOWED';
  END IF;

  SELECT cat_key, cat_label, category INTO v_cat_key, v_cat_label, v_category
  FROM public.normalize_event_category(p_category);

  -- Validate structured inclusions (max 3 items, label <= 60, detail <= 300)
  IF p_included_items IS NOT NULL AND jsonb_typeof(p_included_items) = 'array' THEN
    IF jsonb_array_length(p_included_items) > 3 THEN
      RAISE EXCEPTION 'INVALID_INCLUDED_ITEMS: Maximum 3 items allowed';
    END IF;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_included_items) LOOP
      v_label := trim(COALESCE(v_item->>'label', ''));
      v_detail := trim(COALESCE(v_item->>'detail', ''));
      IF length(v_label) = 0 OR length(v_label) > 60 THEN
        RAISE EXCEPTION 'INVALID_INCLUDED_LABEL: Label must be between 1 and 60 characters';
      END IF;
      IF length(v_detail) > 300 THEN
        RAISE EXCEPTION 'INVALID_INCLUDED_DETAIL: Detail must be under 300 characters';
      END IF;
      v_included_labels := array_append(v_included_labels, v_label);
    END LOOP;
    v_included_text := array_to_string(v_included_labels, ' ▪︎ ');
  END IF;

  INSERT INTO events(
    id, key, slug, organizer_id, name, category, cat_key, cat_label,
    description, price_vnd, price_cents, capacity, seats_remaining, area,
    event_date, event_time, starts_at, status, approval, visibility, submitted_at,
    cover_image, included, included_items
  )
  VALUES (
    v_event_id, v_event_id, v_event_id, v_organizer.id,
    trim(p_name), v_category, v_cat_key, v_cat_label,
    COALESCE(p_description, ''),
    COALESCE(p_price_vnd, 0), COALESCE(p_price_vnd, 0) * 100,
    p_capacity, p_capacity,
    COALESCE(p_location, ''),
    p_event_date, p_event_time, v_starts_at,
    'review', 'host_approves', 'public', now(),
    COALESCE(trim(p_cover_image), ''),
    v_included_text,
    COALESCE(p_included_items, '[]'::jsonb)
  )
  RETURNING * INTO v_event;

  RETURN v_event;
END;
$$;

-- 5. Update resubmit_event_for_review
CREATE OR REPLACE FUNCTION public.resubmit_event_for_review(
  p_event_id text, p_name text, p_category text, p_description text, p_location text,
  p_event_date date, p_event_time time, p_price_vnd bigint, p_capacity int,
  p_cover_image text DEFAULT '',
  p_included_items jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_event events%ROWTYPE;
  v_starts_at timestamptz;
  v_cat_key text;
  v_cat_label text;
  v_category text;
  v_item jsonb;
  v_label text;
  v_detail text;
  v_included_labels text[] := ARRAY[]::text[];
  v_included_text text := '';
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 OR p_capacity IS NULL OR p_capacity < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_EVENT');
  END IF;

  SELECT e.* INTO v_event FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;
  IF v_event.status <> 'draft' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_EDITABLE', 'status', v_event.status);
  END IF;

  v_starts_at := CASE WHEN p_event_date IS NOT NULL AND p_event_time IS NOT NULL
                       THEN (p_event_date + p_event_time) AT TIME ZONE 'Asia/Ho_Chi_Minh'
                       ELSE NULL END;

  IF v_starts_at IS NOT NULL AND v_starts_at < (now() - interval '5 minutes') THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAST_EVENT_NOT_ALLOWED');
  END IF;

  SELECT cat_key, cat_label, category INTO v_cat_key, v_cat_label, v_category
  FROM public.normalize_event_category(p_category);

  IF p_included_items IS NOT NULL AND jsonb_typeof(p_included_items) = 'array' THEN
    IF jsonb_array_length(p_included_items) > 3 THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_INCLUDED_ITEMS: Max 3 items');
    END IF;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_included_items) LOOP
      v_label := trim(COALESCE(v_item->>'label', ''));
      v_detail := trim(COALESCE(v_item->>'detail', ''));
      IF length(v_label) = 0 OR length(v_label) > 60 THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_INCLUDED_LABEL');
      END IF;
      IF length(v_detail) > 300 THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_INCLUDED_DETAIL');
      END IF;
      v_included_labels := array_append(v_included_labels, v_label);
    END LOOP;
    v_included_text := array_to_string(v_included_labels, ' ▪︎ ');
  END IF;

  UPDATE events SET
    name = trim(p_name), category = v_category, cat_key = v_cat_key, cat_label = v_cat_label,
    description = COALESCE(p_description, ''), area = COALESCE(p_location, ''),
    event_date = p_event_date, event_time = p_event_time, starts_at = v_starts_at,
    price_vnd = COALESCE(p_price_vnd, 0), price_cents = COALESCE(p_price_vnd, 0) * 100,
    capacity = p_capacity, seats_remaining = p_capacity,
    cover_image = CASE WHEN length(trim(COALESCE(p_cover_image, ''))) > 0 THEN trim(p_cover_image) ELSE cover_image END,
    included = CASE WHEN length(v_included_text) > 0 THEN v_included_text ELSE included END,
    included_items = COALESCE(p_included_items, included_items),
    status = 'review', submitted_at = now(), reviewed_at = NULL, reviewed_by = NULL, rejection_reason = ''
  WHERE id = p_event_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 6. RPC to update media and inclusions for owned events afterward
CREATE OR REPLACE FUNCTION public.update_event_media_and_details(
  p_event_id text,
  p_cover_image text DEFAULT NULL,
  p_included_items jsonb DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_event events%ROWTYPE;
  v_item jsonb;
  v_label text;
  v_detail text;
  v_included_labels text[] := ARRAY[]::text[];
  v_included_text text := NULL;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;

  SELECT e.* INTO v_event FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid() OR public.is_platform_admin())
    FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;

  IF p_included_items IS NOT NULL AND jsonb_typeof(p_included_items) = 'array' THEN
    IF jsonb_array_length(p_included_items) > 3 THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_INCLUDED_ITEMS');
    END IF;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_included_items) LOOP
      v_label := trim(COALESCE(v_item->>'label', ''));
      v_detail := trim(COALESCE(v_item->>'detail', ''));
      IF length(v_label) = 0 OR length(v_label) > 60 THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_INCLUDED_LABEL');
      END IF;
      IF length(v_detail) > 300 THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_INCLUDED_DETAIL');
      END IF;
      v_included_labels := array_append(v_included_labels, v_label);
    END LOOP;
    v_included_text := array_to_string(v_included_labels, ' ▪︎ ');
  END IF;

  UPDATE events SET
    cover_image = COALESCE(p_cover_image, cover_image),
    included_items = COALESCE(p_included_items, included_items),
    included = COALESCE(v_included_text, included)
  WHERE id = p_event_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.update_event_media_and_details(text, text, jsonb) TO authenticated;

-- 7. One-time forward normalization for existing rows
-- Normalize Supper club category for test-s-ki-n-8444c8 and others
UPDATE events
SET cat_key = 'supper', cat_label = 'Supper club', category = 'Supper club'
WHERE (cat_key = 'supper' OR category ILIKE '%supper%') AND (cat_label = 'supper' OR cat_label IS NULL);

-- Backfill cover_image from event_photos if empty
UPDATE events e
SET cover_image = p.storage_path
FROM (
  SELECT DISTINCT ON (event_id) event_id, storage_path
  FROM event_photos
  ORDER BY event_id, sort_order ASC
) p
WHERE e.id = p.event_id AND (e.cover_image IS NULL OR e.cover_image = '');
