-- 088: Stage B of the post-e661cfb "REAL event creation/discovery" follow-up.
--
-- Content-model correction: "Bao gồm" (events.included_items, migration 087)
-- already IS the max-3-short-labels-plus-tap-to-reveal-detail model the
-- ticket asks for — nothing to change there. What's missing is a SEPARATE
-- longer, host-written editorial description ("Giới thiệu sự kiện"),
-- distinct from both the short `description` field (used in the create
-- form's one-line "Mô tả") and `included_items` (never meant to double as
-- marketing copy). `events.description` itself is untouched and stays
-- readable exactly as before.
--
-- Also: update_event_media_and_details (087) validated included_items but
-- never validated a plain length cap on the new p_intro param the way the
-- two submission RPCs do — added here for the same reason 087 validated
-- included_items in all three places instead of just create_event_draft.

ALTER TABLE events ADD COLUMN IF NOT EXISTS intro text NOT NULL DEFAULT '';

COMMENT ON COLUMN events.intro IS
  'Long-form, host-written editorial description ("Giới thiệu sự kiện") — '
  'plain text with blank-line paragraph breaks, never HTML. Distinct from '
  'the short description field and from included_items ("Bao gồm").';

-- Each of these three RPCs is gaining a new trailing p_intro param. A plain
-- CREATE OR REPLACE with a different parameter list creates an OVERLOAD
-- instead of replacing the old signature — every existing call site (both
-- this migration's own web/iOS callers) then becomes ambiguous ("function
-- is not unique") because it matches both the old and new signature via
-- defaults. Dropping the exact old signature first avoids that.
DROP FUNCTION IF EXISTS create_event_draft(text, text, text, text, date, time, bigint, int, text, text, text, text, jsonb);
DROP FUNCTION IF EXISTS public.resubmit_event_for_review(text, text, text, text, text, date, time, bigint, int, text, jsonb);
DROP FUNCTION IF EXISTS public.update_event_media_and_details(text, text, jsonb);

CREATE OR REPLACE FUNCTION create_event_draft(
  p_name text, p_category text, p_description text, p_location text,
  p_event_date date, p_event_time time, p_price_vnd bigint, p_capacity int,
  p_organizer_name text, p_instagram text DEFAULT '', p_about text DEFAULT '',
  p_cover_image text DEFAULT '',
  p_included_items jsonb DEFAULT '[]'::jsonb,
  p_intro text DEFAULT ''
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
  IF p_intro IS NOT NULL AND length(p_intro) > 4000 THEN
    RAISE EXCEPTION 'INVALID_INTRO: Max 4000 characters';
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
    cover_image, included, included_items, intro
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
    COALESCE(p_included_items, '[]'::jsonb),
    COALESCE(p_intro, '')
  )
  RETURNING * INTO v_event;

  RETURN v_event;
END;
$$;

CREATE OR REPLACE FUNCTION public.resubmit_event_for_review(
  p_event_id text, p_name text, p_category text, p_description text, p_location text,
  p_event_date date, p_event_time time, p_price_vnd bigint, p_capacity int,
  p_cover_image text DEFAULT '',
  p_included_items jsonb DEFAULT '[]'::jsonb,
  p_intro text DEFAULT NULL
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
  IF p_intro IS NOT NULL AND length(p_intro) > 4000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_INTRO');
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
    intro = COALESCE(p_intro, intro),
    status = 'review', submitted_at = now(), reviewed_at = NULL, reviewed_by = NULL, rejection_reason = ''
  WHERE id = p_event_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_event_media_and_details(
  p_event_id text,
  p_cover_image text DEFAULT NULL,
  p_included_items jsonb DEFAULT NULL,
  p_intro text DEFAULT NULL
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
  IF p_intro IS NOT NULL AND length(p_intro) > 4000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_INTRO');
  END IF;

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
    included = COALESCE(v_included_text, included),
    intro = COALESCE(p_intro, intro)
  WHERE id = p_event_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.update_event_media_and_details(text, text, jsonb, text) TO authenticated;
