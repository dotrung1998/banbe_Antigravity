-- 106: Compatibility + trust fix for migration 105, applied the same day
-- it was written, BEFORE the new address-autocomplete frontend (web
-- CreateEvent.jsx/GocContext.jsx, iOS OnboardingViews.swift/AppState+Data.swift)
-- has actually shipped to production.
--
-- Confirmed root cause: `git log` shows every file touched by the
-- address-autocomplete pass (both frontends, this migration) as
-- uncommitted local changes only — the currently DEPLOYED web app (and
-- any shipped iOS build) predates all of it, and therefore never sends
-- `p_address_line`/`p_city`/`p_postal_code`/`p_address_verified` at all.
-- Migration 105 made a COMPLETE, VERIFIED address a hard requirement for
-- EVERY create_event_draft/resubmit_event_for_review call — for a caller
-- that omits those params entirely, Postgres uses their declared
-- defaults (`''`/`false`/`NULL`), which 105's own validation then always
-- rejects as `ADDRESS_NOT_VERIFIED`. Net effect, confirmed by reading the
-- deployed vs. local diff, not assumed: the CURRENTLY LIVE production
-- frontend can no longer create or edit ANY event, as of 105 landing,
-- until its own frontend deploy ships — a real, active breakage, not a
-- hypothetical one.
--
-- Fix: the completeness/plausibility check now only RUNS when the caller
-- actually CLAIMS a verified address (`p_address_verified = true`/
-- `COALESCE(..., existing row value) = true` for a resubmit that doesn't
-- re-touch it) — which only ever happens from the NEW frontend, which
-- always sends a complete address alongside that claim (client-side
-- validation there blocks submission otherwise — see CreateEvent.jsx/
-- OnboardingViews.swift). An old, not-yet-updated caller that never
-- claims `address_verified` at all falls through unchanged, exactly as
-- it behaved before 105 (only the pre-existing -90..90/-180..180 lat/lng
-- range check from migration 094 applies to it). This is a genuine,
-- deliberate relaxation of 105's OWN stated goal ("require a selected,
-- resolvable address... before publishing") — full enforcement for every
-- submission is deferred to a LATER migration, once the new frontend is
-- confirmed deployed and the currently-live one is no longer in the
-- traffic mix. Tracked here explicitly rather than silently: search this
-- migration's own filename before assuming address verification is
-- unconditionally enforced.
--
-- Also fixes the ticket's own explicit trust concern — "address_verified
-- cannot be trusted merely because a client sends true" — 105's own check
-- only confirmed the address FIELDS were non-empty and coordinates
-- non-null, never that the coordinates were remotely plausible; a client
-- could send `address_verified: true, lat: 0, lng: 0` (or any other
-- nonsense pair) and 105 would have accepted it at face value. Both RPCs
-- below now additionally require any non-null lat/lng (claimed-verified
-- or not — this part is NOT gated on address_verified, since a garbage
-- coordinate is equally wrong regardless of what the caller claims about
-- the address text) to fall within Vietnam's own rough bounding box
-- (8°N–24°N, 102°E–110°E — generously covers the whole country, not just
-- Ho Chi Minh City, so a real future event outside HCMC is never
-- rejected). This tightens migration 094's original global
-- -90..90/-180..180 check without replacing it.

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
  -- Compatibility/trust fix (migration 106) — plausibility check applies
  -- to ANY supplied coordinate pair, regardless of address_verified.
  IF p_lat IS NOT NULL AND p_lng IS NOT NULL
     AND (p_lat < 8 OR p_lat > 24 OR p_lng < 102 OR p_lng > 110) THEN
    RAISE EXCEPTION 'ADDRESS_NOT_PLAUSIBLE: Coordinates fall outside Vietnam';
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
  -- Compatibility fix (migration 106) — ONLY when the caller actually
  -- CLAIMS a verified address does completeness get enforced; an old
  -- caller that never sends p_address_verified at all (defaults to
  -- false) is no longer blocked — see this migration's own header.
  IF COALESCE(p_address_verified, false) THEN
    IF length(trim(COALESCE(p_address_line, ''))) = 0
       OR length(trim(COALESCE(p_location, ''))) = 0
       OR length(trim(COALESCE(p_city, ''))) = 0
       OR p_lat IS NULL OR p_lng IS NULL THEN
      RAISE EXCEPTION 'ADDRESS_NOT_VERIFIED: address_verified was true but the address is incomplete';
    END IF;
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
    trim(COALESCE(p_address_line, '')), trim(COALESCE(p_city, '')), trim(COALESCE(p_postal_code, '')),
    COALESCE(p_address_verified, false)
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
  IF p_lat IS NOT NULL AND p_lng IS NOT NULL
     AND (p_lat < 8 OR p_lat > 24 OR p_lng < 102 OR p_lng > 110) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADDRESS_NOT_PLAUSIBLE');
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

  v_final_lat := COALESCE(p_lat, v_event.lat);
  v_final_lng := COALESCE(p_lng, v_event.lng);
  v_final_address_line := trim(COALESCE(p_address_line, v_event.address_line));
  v_final_city := trim(COALESCE(p_city, v_event.city));
  v_final_postal_code := trim(COALESCE(p_postal_code, v_event.postal_code));
  v_final_address_verified := COALESCE(p_address_verified, v_event.address_verified);
  v_final_area := trim(COALESCE(p_location, v_event.area));

  -- Compatibility fix (migration 106) — completeness only enforced when
  -- the FINAL, resolved verified-flag is true (this event either already
  -- had a verified address, or this call explicitly supplies one) — an
  -- old caller resubmitting a legacy, never-verified event is no longer
  -- blocked. See this migration's own header comment.
  IF v_final_address_verified THEN
    IF length(v_final_address_line) = 0
       OR length(v_final_area) = 0
       OR length(v_final_city) = 0
       OR v_final_lat IS NULL OR v_final_lng IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'ADDRESS_NOT_VERIFIED');
    END IF;
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
