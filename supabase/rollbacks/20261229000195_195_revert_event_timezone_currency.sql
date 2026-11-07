-- Rollback for 195 (event time zone + currency). NOT a migration; run by hand only if 195 must be undone.
-- Restores the function bodies exactly as 112 (create/resubmit) and 186 (benchmarks) defined them — which
-- also re-drops 107's resubmission limit/history/duplicate guard, as production had before 195.
-- WARNING: run this only while no USD event exists: dropping `currency` would make a USD price (cents) read
-- as dong. Check first:  select count(*) from events where currency <> 'VND';

DROP TRIGGER IF EXISTS bookings_currency_guard ON public.bookings;
DROP FUNCTION IF EXISTS public.bookings_currency_guard();

DROP FUNCTION IF EXISTS public.get_host_benchmarks(text, text, text);
DROP FUNCTION IF EXISTS public.benchmark_slot(timestamptz, text);
CREATE OR REPLACE FUNCTION public.get_host_benchmarks(p_cat_key text, p_city text)
RETURNS jsonb
-- VOLATILE (not STABLE): it fills a session temp table. It writes nothing persistent.
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  k_events constant int := 5;
  k_orgs   constant int := 3;
  v_cat  text := lower(trim(COALESCE(p_cat_key, '')));
  v_city text := lower(trim(COALESCE(p_city, '')));
  v_level text;
  v_out jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  -- Base pool: public, not cancelled, started in the last 180 days or starting in the next 60.
  CREATE TEMP TABLE IF NOT EXISTS _bm_pool (
    id text, organizer_id text, cat_key text, city text, price_vnd int, capacity int,
    starts_at timestamptz, submitted_at timestamptz, started boolean, booked int,
    fill numeric, photos int, has_intro boolean, has_included boolean, keywords text[]
  ) ON COMMIT DROP;
  TRUNCATE _bm_pool;

  INSERT INTO _bm_pool
  SELECT e.id, e.organizer_id, lower(COALESCE(e.cat_key, '')), lower(trim(COALESCE(e.city, ''))),
         e.price_vnd, e.capacity, e.starts_at, e.submitted_at, e.starts_at < now(),
         f.booked,
         CASE WHEN e.capacity > 0 THEN LEAST(f.booked::numeric / e.capacity, 1) END,
         (SELECT count(*)::int FROM event_photos p WHERE p.event_id = e.id),
         length(trim(COALESCE(e.intro, ''))) > 0,
         jsonb_typeof(e.included_items) = 'array' AND jsonb_array_length(e.included_items) > 0,
         COALESCE(e.keywords, '{}')
  FROM events e
  CROSS JOIN LATERAL (
    SELECT COALESCE(SUM(b.qty), 0)::int AS booked FROM bookings b
    WHERE b.event_id = e.id AND booking_holds_seat(b.payment_state, b.hold_expires_at, b.status)
  ) f
  WHERE e.visibility = 'public'
    AND e.status IN ('live', 'ended')
    AND e.cancelled_at IS NULL
    AND e.organizer_id IS NOT NULL
    AND e.starts_at IS NOT NULL
    AND e.starts_at BETWEEN now() - interval '180 days' AND now() + interval '60 days';

  -- Fallback cascade: category+city -> category -> everything. First level that clears k wins.
  IF v_cat <> '' AND v_city <> '' AND (
       SELECT count(*) >= k_events AND count(DISTINCT organizer_id) >= k_orgs
       FROM _bm_pool WHERE cat_key = v_cat AND city = v_city) THEN
    v_level := 'category_city';
  ELSIF v_cat <> '' AND (
       SELECT count(*) >= k_events AND count(DISTINCT organizer_id) >= k_orgs
       FROM _bm_pool WHERE cat_key = v_cat) THEN
    v_level := 'category';
  ELSIF (SELECT count(*) >= k_events AND count(DISTINCT organizer_id) >= k_orgs FROM _bm_pool) THEN
    v_level := 'all';
  ELSE
    RETURN jsonb_build_object('success', true, 'level', NULL, 'n', 0);
  END IF;

  DELETE FROM _bm_pool
  WHERE NOT (CASE v_level
    WHEN 'category_city' THEN cat_key = v_cat AND city = v_city
    WHEN 'category' THEN cat_key = v_cat
    ELSE true END);

  WITH paid AS (SELECT price_vnd FROM _bm_pool WHERE price_vnd > 0),
  paid_stats AS (
    SELECT count(*) AS n, count(DISTINCT p.organizer_id) AS orgs,
           percentile_cont(0.25) WITHIN GROUP (ORDER BY p.price_vnd) AS p25,
           percentile_cont(0.5)  WITHIN GROUP (ORDER BY p.price_vnd) AS p50,
           percentile_cont(0.75) WITHIN GROUP (ORDER BY p.price_vnd) AS p75,
           min(p.price_vnd) AS lo, max(p.price_vnd) AS hi
    FROM _bm_pool p WHERE p.price_vnd > 0
  ),
  hist AS (
    SELECT CASE WHEN s.hi > s.lo THEN LEAST(width_bucket(p.price_vnd::numeric, s.lo::numeric, (s.hi + 1)::numeric, 10), 10) ELSE 1 END AS bucket,
           count(*) AS c
    FROM paid p CROSS JOIN paid_stats s
    GROUP BY 1
  ),
  started AS (SELECT * FROM _bm_pool WHERE started AND fill IS NOT NULL),
  started_stats AS (
    SELECT count(*) AS n, count(DISTINCT organizer_id) AS orgs,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY fill) AS fill_p50,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY capacity) AS cap_p50,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY booked) AS booked_p50
    FROM started
  ),
  cells AS (
    SELECT extract(isodow FROM starts_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::int AS dow,
           benchmark_slot(starts_at) AS slot,
           count(*) AS n, count(DISTINCT organizer_id) AS orgs,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY fill) AS fill_p50
    FROM started GROUP BY 1, 2
  ),
  groups AS (
    SELECT (fill >= 0.8) AS well_filled,
           count(*) AS n, count(DISTINCT organizer_id) AS orgs,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY photos) AS photos_p50,
           avg(has_intro::int) AS intro_share,
           avg(has_included::int) AS included_share,
           percentile_cont(0.5) WITHIN GROUP (
             ORDER BY extract(epoch FROM (starts_at - submitted_at)) / 86400.0
           ) FILTER (WHERE submitted_at IS NOT NULL AND submitted_at < starts_at) AS lead_days_p50,
           count(*) FILTER (WHERE submitted_at IS NOT NULL AND submitted_at < starts_at) AS lead_n
    FROM started GROUP BY 1
  ),
  kw AS (
    SELECT lower(trim(k)) AS keyword, count(DISTINCT p.id) AS events, count(DISTINCT p.organizer_id) AS orgs
    FROM _bm_pool p CROSS JOIN LATERAL unnest(p.keywords) AS k
    WHERE length(trim(k)) > 0
    GROUP BY 1
  )
  SELECT jsonb_build_object(
    'success', true,
    'level', v_level,
    'n', (SELECT count(*) FROM _bm_pool),
    'free_share', (SELECT round(avg((price_vnd = 0)::int)::numeric, 3) FROM _bm_pool),
    'price', (
      SELECT CASE WHEN s.n >= k_events AND s.orgs >= k_orgs THEN jsonb_build_object(
        'n', s.n, 'p25', round(s.p25), 'median', round(s.p50), 'p75', round(s.p75),
        'min', s.lo, 'max', s.hi,
        'histogram', (SELECT jsonb_agg(COALESCE(h.c, 0) ORDER BY g.b)
                      FROM generate_series(1, 10) AS g(b) LEFT JOIN hist h ON h.bucket = g.b)
      ) END FROM paid_stats s
    ),
    'fill', (
      SELECT CASE WHEN s.n >= k_events AND s.orgs >= k_orgs THEN jsonb_build_object(
        'n', s.n, 'median_fill', round(s.fill_p50::numeric, 3),
        'median_capacity', round(s.cap_p50), 'median_booked', round(s.booked_p50)
      ) END FROM started_stats s
    ),
    'slots', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('dow', c.dow, 'slot', c.slot, 'n', c.n,
                                          'median_fill', round(c.fill_p50::numeric, 3))
                       ORDER BY c.dow, c.slot)
      FROM cells c WHERE c.n >= k_events AND c.orgs >= k_orgs
    ), '[]'::jsonb),
    'well_filled', (
      SELECT CASE WHEN g.n >= k_events AND g.orgs >= k_orgs THEN jsonb_build_object(
        'n', g.n, 'median_photos', round(g.photos_p50::numeric, 1),
        'intro_share', round(g.intro_share::numeric, 3), 'included_share', round(g.included_share::numeric, 3),
        'median_lead_days', CASE WHEN g.lead_n >= k_events THEN round(g.lead_days_p50::numeric, 1) END
      ) END FROM groups g WHERE g.well_filled
    ),
    'others', (
      SELECT CASE WHEN g.n >= k_events AND g.orgs >= k_orgs THEN jsonb_build_object(
        'n', g.n, 'median_photos', round(g.photos_p50::numeric, 1),
        'intro_share', round(g.intro_share::numeric, 3), 'included_share', round(g.included_share::numeric, 3),
        'median_lead_days', CASE WHEN g.lead_n >= k_events THEN round(g.lead_days_p50::numeric, 1) END
      ) END FROM groups g WHERE NOT g.well_filled
    ),
    'keywords', COALESCE((
      SELECT jsonb_agg(t.keyword ORDER BY t.events DESC, t.keyword)
      FROM (SELECT * FROM kw WHERE orgs >= 2 ORDER BY events DESC, keyword LIMIT 10) t
    ), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION public.get_host_benchmarks(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_host_benchmarks(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_host_benchmarks(text, text) TO authenticated;

DROP FUNCTION IF EXISTS public.create_event_draft(text, text, text, text, date, time, bigint, int, text, text, text, text, jsonb, text, double precision, double precision, text, text, text, boolean, text, text, text, text);
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
  p_address_verified boolean DEFAULT false,
  p_country_code text DEFAULT NULL,
  p_state_province text DEFAULT NULL,
  p_neighborhood text DEFAULT NULL
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
  IF p_country_code IS NOT NULL AND length(p_country_code) > 2 THEN
    RAISE EXCEPTION 'INVALID_COUNTRY_CODE: Max 2 characters';
  END IF;
  IF p_state_province IS NOT NULL AND length(p_state_province) > 100 THEN
    RAISE EXCEPTION 'INVALID_STATE_PROVINCE: Max 100 characters';
  END IF;
  IF p_neighborhood IS NOT NULL AND length(p_neighborhood) > 100 THEN
    RAISE EXCEPTION 'INVALID_NEIGHBORHOOD: Max 100 characters';
  END IF;
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
    address_line, city, postal_code, address_verified,
    country_code, state_province, neighborhood
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
    trim(COALESCE(p_address_line, '')), trim(COALESCE(p_city, '')), trim(COALESCE(p_postal_code, '')), true,
    NULLIF(trim(COALESCE(p_country_code, '')), ''), NULLIF(trim(COALESCE(p_state_province, '')), ''), NULLIF(trim(COALESCE(p_neighborhood, '')), '')
  )
  RETURNING * INTO v_event;

  RETURN v_event;
END;
$$;


DROP FUNCTION IF EXISTS public.resubmit_event_for_review(text, text, text, text, text, date, time, bigint, int, text, jsonb, text, double precision, double precision, text, text, text, boolean, text, text, text, text);
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
  p_address_verified boolean DEFAULT NULL,
  p_country_code text DEFAULT NULL,
  p_state_province text DEFAULT NULL,
  p_neighborhood text DEFAULT NULL
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
  v_final_country_code text;
  v_final_state_province text;
  v_final_neighborhood text;
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
  IF p_country_code IS NOT NULL AND length(p_country_code) > 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_COUNTRY_CODE');
  END IF;
  IF p_state_province IS NOT NULL AND length(p_state_province) > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE_PROVINCE');
  END IF;
  IF p_neighborhood IS NOT NULL AND length(p_neighborhood) > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_NEIGHBORHOOD');
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
  -- Same COALESCE-preserving pattern as the address fields above: a
  -- resubmit that doesn't re-touch the address keeps whatever the row
  -- already had (including whatever the backfill script wrote).
  v_final_country_code := NULLIF(trim(COALESCE(p_country_code, v_event.country_code, '')), '');
  v_final_state_province := NULLIF(trim(COALESCE(p_state_province, v_event.state_province, '')), '');
  v_final_neighborhood := NULLIF(trim(COALESCE(p_neighborhood, v_event.neighborhood, '')), '');

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
    country_code = v_final_country_code, state_province = v_final_state_province, neighborhood = v_final_neighborhood,
    status = 'review', submitted_at = now(), reviewed_at = NULL, reviewed_by = NULL, rejection_reason = ''
  WHERE id = p_event_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- US rows' starts_at stays at the corrected instant (the right one); only the zone column goes.
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_currency_check;
ALTER TABLE public.events DROP COLUMN IF EXISTS tz, DROP COLUMN IF EXISTS currency;
DROP FUNCTION IF EXISTS public.resolve_event_tz(text, text, text);
DROP FUNCTION IF EXISTS public.event_currency_for(text);
DROP FUNCTION IF EXISTS public.event_tz_for(text, text);
