-- 105: Create Event address-autocomplete pass — verified, structured
-- address on submit.
--
-- Ground truth (confirmed by reading the current schema/RPCs, not
-- guessed): `events.area` has held a single free-text location string
-- since migration 001 (no street/house-number/ward/district/city/postal
-- decomposition ever existed), and migration 094's p_lat/p_lng validation
-- is only a global -90..90/-180..180 range check with zero connection to
-- the address text — an unresolved free-text string could always publish
-- alongside a completely unrelated (or absent) coordinate pair.
--
-- This adds the minimum structured columns needed to (a) require a real,
-- selected/resolvable address before an event can be submitted, and (b)
-- let the create/edit form re-show and re-select a previously confirmed
-- address instead of re-geocoding from scratch every edit. `area` is
-- UNCHANGED in shape (still one text column) but its MEANING narrows here
-- from "whatever the host typed" to "the resolved district only" — the
-- exact string Event Detail's concise location line already shows
-- (`event.where`/`ev.where`, both `real.area`) — since the new picker
-- flow (web/iOS, this same pass) now writes the geocoder's own resolved
-- district into `p_location`/`area` instead of raw free text.
--
-- `address_line`/`city`/`postal_code` are genuinely new. `address_verified`
-- is the write-time trust flag: true only when the client's own
-- pick-a-suggestion-then-confirm-the-pin flow actually completed (the
-- direct extension of `createLocConfirmed`/`s.createLocConfirmed`, which
-- already gates whether `p_lat`/`p_lng` are ever non-null) — Postgres has
-- no way to independently re-verify a geocode result, so this is the same
-- trust model migration 094 already established for coordinates, just
-- extended to the rest of the address.

ALTER TABLE events ADD COLUMN IF NOT EXISTS address_line text DEFAULT '';
ALTER TABLE events ADD COLUMN IF NOT EXISTS city text DEFAULT '';
ALTER TABLE events ADD COLUMN IF NOT EXISTS postal_code text DEFAULT '';
ALTER TABLE events ADD COLUMN IF NOT EXISTS address_verified boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN events.address_line IS
  'Street + house/building number ("12 Nguyễn Văn Đậu"), OR a verified '
  'named venue/POI''s own name when a conventional house number genuinely '
  'does not exist for that place. Never a district/city name alone — that '
  'is what `area` (the district) and `city` are for.';
COMMENT ON COLUMN events.city IS 'Resolved city/province from the address picker, e.g. "Hồ Chí Minh".';
COMMENT ON COLUMN events.postal_code IS 'Optional — empty when the geocoding provider does not return one, never invented.';
COMMENT ON COLUMN events.address_verified IS
  'True only once the host picked a real suggestion from the address '
  'autocomplete AND explicitly confirmed the resulting pin/venue — the '
  'same trust gate `createLocConfirmed` already applies to lat/lng '
  '(migration 094), extended to the rest of the structured address. An '
  'unresolved free-text string can never set this true.';

-- Older rows (created before this pass, or via the old free-text-only
-- flow) legitimately have address_verified = false and empty
-- address_line/city — handled honestly on read (Stage 1 of this same
-- ticket already made Event Detail/Map treat missing lat/lng as "no pin"
-- rather than inventing one), and on write below (an EDIT to an old event
-- that never re-touches its address is still allowed to resubmit, see
-- the COALESCE pattern in resubmit_event_for_review).

DROP FUNCTION IF EXISTS create_event_draft(text, text, text, text, date, time, bigint, int, text, text, text, text, jsonb, text, double precision, double precision);
DROP FUNCTION IF EXISTS public.resubmit_event_for_review(text, text, text, text, text, date, time, bigint, int, text, jsonb, text, double precision, double precision);

CREATE OR REPLACE FUNCTION create_event_draft(
  p_name text, p_category text, p_description text, p_location text,
  p_event_date date, p_event_time time, p_price_vnd bigint, p_capacity int,
  p_organizer_name text, p_instagram text DEFAULT '', p_about text DEFAULT '',
  p_cover_image text DEFAULT '',
  p_included_items jsonb DEFAULT '[]'::jsonb,
  p_intro text DEFAULT '',
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_address_line text DEFAULT '',
  p_city text DEFAULT '',
  p_postal_code text DEFAULT '',
  p_address_verified boolean DEFAULT false
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
  IF (p_lat IS NOT NULL AND (p_lat < -90 OR p_lat > 90)) OR (p_lng IS NOT NULL AND (p_lng < -180 OR p_lng > 180)) THEN
    RAISE EXCEPTION 'INVALID_COORDINATES';
  END IF;
  IF length(COALESCE(p_address_line, '')) > 200 THEN
    RAISE EXCEPTION 'INVALID_ADDRESS_LINE: Max 200 characters';
  END IF;
  IF length(COALESCE(p_city, '')) > 100 THEN
    RAISE EXCEPTION 'INVALID_CITY: Max 100 characters';
  END IF;
  IF length(COALESCE(p_postal_code, '')) > 20 THEN
    RAISE EXCEPTION 'INVALID_POSTAL_CODE: Max 20 characters';
  END IF;
  -- A brand-new event has nothing to fall back to — the picked-and-
  -- confirmed address must be complete right now. (resubmit_event_for_review
  -- below is the one that allows an unchanged, already-verified older
  -- address to carry over untouched.)
  IF NOT COALESCE(p_address_verified, false)
     OR length(trim(COALESCE(p_address_line, ''))) = 0
     OR length(trim(COALESCE(p_location, ''))) = 0
     OR length(trim(COALESCE(p_city, ''))) = 0
     OR p_lat IS NULL OR p_lng IS NULL THEN
    RAISE EXCEPTION 'ADDRESS_NOT_VERIFIED: Select a suggested address and confirm its pin before publishing.';
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
    cover_image, included, included_items, intro, lat, lng,
    address_line, city, postal_code, address_verified
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
    COALESCE(p_intro, ''),
    p_lat, p_lng,
    trim(COALESCE(p_address_line, '')), trim(COALESCE(p_city, '')), trim(COALESCE(p_postal_code, '')), true
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
  p_intro text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_address_line text DEFAULT NULL,
  p_city text DEFAULT NULL,
  p_postal_code text DEFAULT NULL,
  -- NULL (not false) means "this resubmit didn't touch the address at
  -- all" — distinct from an explicit `false`, which would mean the
  -- client actively cleared a previously-confirmed address (the edit
  -- form's own `createLocType` reset, mirrored client-side). Only NULL
  -- falls through to the row's OWN existing address_verified below.
  p_address_verified boolean DEFAULT NULL
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
  v_final_address_line text;
  v_final_city text;
  v_final_postal_code text;
  v_final_address_verified boolean;
  v_final_lat double precision;
  v_final_lng double precision;
  v_final_area text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 OR p_capacity IS NULL OR p_capacity < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_EVENT');
  END IF;
  IF p_intro IS NOT NULL AND length(p_intro) > 4000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_INTRO');
  END IF;
  IF (p_lat IS NOT NULL AND (p_lat < -90 OR p_lat > 90)) OR (p_lng IS NOT NULL AND (p_lng < -180 OR p_lng > 180)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_COORDINATES');
  END IF;
  IF p_address_line IS NOT NULL AND length(p_address_line) > 200 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_ADDRESS_LINE');
  END IF;
  IF p_city IS NOT NULL AND length(p_city) > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_CITY');
  END IF;
  IF p_postal_code IS NOT NULL AND length(p_postal_code) > 20 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_POSTAL_CODE');
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

  -- Same COALESCE-preserving pattern migration 094 already established for
  -- lat/lng: a resubmit that doesn't re-touch the address (edited only
  -- price/description, say) keeps the row's own already-verified address
  -- exactly as it was, rather than forcing a re-geocode on every edit.
  v_final_lat := COALESCE(p_lat, v_event.lat);
  v_final_lng := COALESCE(p_lng, v_event.lng);
  v_final_address_line := trim(COALESCE(p_address_line, v_event.address_line));
  v_final_city := trim(COALESCE(p_city, v_event.city));
  v_final_postal_code := trim(COALESCE(p_postal_code, v_event.postal_code));
  v_final_address_verified := COALESCE(p_address_verified, v_event.address_verified);
  v_final_area := trim(COALESCE(p_location, v_event.area));

  IF NOT v_final_address_verified
     OR length(v_final_address_line) = 0
     OR length(v_final_area) = 0
     OR length(v_final_city) = 0
     OR v_final_lat IS NULL OR v_final_lng IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADDRESS_NOT_VERIFIED');
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
    description = COALESCE(p_description, ''), area = v_final_area,
    event_date = p_event_date, event_time = p_event_time, starts_at = v_starts_at,
    price_vnd = COALESCE(p_price_vnd, 0), price_cents = COALESCE(p_price_vnd, 0) * 100,
    capacity = p_capacity, seats_remaining = p_capacity,
    cover_image = CASE WHEN length(trim(COALESCE(p_cover_image, ''))) > 0 THEN trim(p_cover_image) ELSE cover_image END,
    included = CASE WHEN length(v_included_text) > 0 THEN v_included_text ELSE included END,
    included_items = COALESCE(p_included_items, included_items),
    intro = COALESCE(p_intro, intro),
    lat = v_final_lat, lng = v_final_lng,
    address_line = v_final_address_line, city = v_final_city, postal_code = v_final_postal_code,
    address_verified = v_final_address_verified,
    status = 'review', submitted_at = now(), reviewed_at = NULL, reviewed_by = NULL, rejection_reason = ''
  WHERE id = p_event_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
