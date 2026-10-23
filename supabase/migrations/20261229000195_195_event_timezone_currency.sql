-- 195 — US readiness: every event carries its own IANA time zone and its currency.
--
-- Before: create_event_draft / resubmit_event_for_review turned the host's wall-clock date+time into
-- starts_at with AT TIME ZONE 'Asia/Ho_Chi_Minh' for EVERY event, so a US host's 19:00 was stored as
-- 12:00 UTC (05:00 in California). Prices were VND only.
--
-- Now:
--  * events.tz (IANA). The server derives it from the event's own location (VN → Asia/Ho_Chi_Minh,
--    US → by state), or takes the client's p_tz when it is a real US zone (MapKit knows the exact zone
--    of multi-zone states). starts_at = (event_date + event_time) AT TIME ZONE events.tz.
--  * events.currency ('VND' | 'USD'), derived from the country on create/resubmit. The price columns
--    keep their names: `price_vnd` now means "price in the minor unit of `currency`" (đồng for VND,
--    cents for USD); `price_cents` stays the legacy ×100 copy for VND and equals the cents for USD.
--  * Paid USD bookings are NOT available yet (owner decision 2026-10-22: free + USD display first).
--    A bookings trigger refuses them server-side; clients show a clear disabled state instead.
--  * get_host_benchmarks compares like with like: one currency per pool, slots in each event's zone.
--  * Restores what 112 silently dropped from 107 (112 was written from 106): the per-event
--    resubmission limit (2 per rolling 24h) + its bookkeeping, the duplicate-pending-event guard,
--    event_status_history rows for submit/resubmit, the withdrawal reset, and the anon REVOKEs.
--    107's "coordinates must be inside Vietnam" check stays removed (US events need it gone).
--
-- Existing rows: tz derived from country/state; US rows with a wall-clock date+time get starts_at
-- recomputed in their real zone. currency stays 'VND' for every existing row (their prices were
-- entered as VND); a US event becomes USD the next time its host resubmits it.
--
-- Rollback: supabase/rollbacks/20261229000195_195_revert_event_timezone_currency.sql (kept OUT of migrations/).

-- ---------------------------------------------------------------- helpers
CREATE OR REPLACE FUNCTION public.event_tz_for(p_country_code text, p_state_province text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  -- Keep in sync with src/lib/eventMarket.js and apps/ios/BanbeApp/Lib/EventMarket.swift
  -- (shared vectors: tests/fixtures/event-market.json). NULL = unknown.
  SELECT CASE upper(coalesce(nullif(trim(p_country_code), ''), 'VN'))
    WHEN 'VN' THEN 'Asia/Ho_Chi_Minh'
    WHEN 'US' THEN (
      SELECT z.zone FROM (VALUES
        ('America/New_York', ARRAY['ct','connecticut','de','delaware','dc','district of columbia','fl','florida','ga','georgia','me','maine','md','maryland','ma','massachusetts','nh','new hampshire','nj','new jersey','ny','new york','nc','north carolina','oh','ohio','pa','pennsylvania','ri','rhode island','sc','south carolina','vt','vermont','va','virginia','wv','west virginia','mi','michigan','in','indiana','ky','kentucky']),
        ('America/Chicago', ARRAY['al','alabama','ar','arkansas','il','illinois','ia','iowa','la','louisiana','mn','minnesota','ms','mississippi','mo','missouri','ok','oklahoma','tx','texas','wi','wisconsin','ks','kansas','ne','nebraska','sd','south dakota','nd','north dakota','tn','tennessee']),
        ('America/Denver', ARRAY['co','colorado','mt','montana','nm','new mexico','ut','utah','wy','wyoming','id','idaho']),
        ('America/Phoenix', ARRAY['az','arizona']),
        ('America/Los_Angeles', ARRAY['ca','california','nv','nevada','or','oregon','wa','washington']),
        ('America/Anchorage', ARRAY['ak','alaska']),
        ('Pacific/Honolulu', ARRAY['hi','hawaii'])
      ) AS z(zone, states)
      WHERE lower(trim(coalesce(p_state_province, ''))) = ANY (z.states)
      LIMIT 1)
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public.event_currency_for(p_country_code text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE upper(coalesce(nullif(trim(p_country_code), ''), 'VN'))
    WHEN 'VN' THEN 'VND' WHEN 'US' THEN 'USD' ELSE NULL END;
$$;

-- The zone actually used: VN is always Asia/Ho_Chi_Minh; for US a client-supplied zone wins when it
-- is a real US zone (America/* or Pacific/Honolulu), else the state map. NULL = cannot place it.
CREATE OR REPLACE FUNCTION public.resolve_event_tz(p_country_code text, p_state_province text, p_tz text)
RETURNS text LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE
  v_country text := upper(coalesce(nullif(trim(p_country_code), ''), 'VN'));
  v_tz text := nullif(trim(coalesce(p_tz, '')), '');
BEGIN
  IF v_country = 'US' AND v_tz IS NOT NULL
     AND (v_tz LIKE 'America/%' OR v_tz = 'Pacific/Honolulu')
     AND EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = v_tz) THEN
    RETURN v_tz;
  END IF;
  RETURN public.event_tz_for(v_country, p_state_province);
END;
$$;

REVOKE ALL ON FUNCTION public.event_tz_for(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.event_currency_for(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.resolve_event_tz(text, text, text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- columns + backfill
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS tz text NOT NULL DEFAULT 'Asia/Ho_Chi_Minh';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'VND';
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_currency_check;
ALTER TABLE public.events ADD CONSTRAINT events_currency_check CHECK (currency IN ('VND', 'USD'));
COMMENT ON COLUMN public.events.tz IS
  'IANA time zone of the venue (migration 195). starts_at = (event_date + event_time) AT TIME ZONE tz.';
COMMENT ON COLUMN public.events.currency IS
  'Currency of price_vnd (migration 195): VND (đồng) or USD (price_vnd holds CENTS). Paid USD booking is not available yet.';
COMMENT ON COLUMN public.events.price_vnd IS
  'Price in the minor unit of events.currency (đồng for VND, cents for USD). Name kept for compatibility (migration 195).';

UPDATE public.events e
   SET tz = coalesce(public.event_tz_for(e.country_code, e.state_province), 'Asia/Ho_Chi_Minh')
 WHERE e.tz IS DISTINCT FROM coalesce(public.event_tz_for(e.country_code, e.state_province), 'Asia/Ho_Chi_Minh');

UPDATE public.events e
   SET starts_at = (e.event_date + e.event_time) AT TIME ZONE e.tz
 WHERE upper(coalesce(e.country_code, '')) = 'US'
   AND e.event_date IS NOT NULL AND e.event_time IS NOT NULL
   AND e.starts_at IS DISTINCT FROM ((e.event_date + e.event_time) AT TIME ZONE e.tz);

-- ---------------------------------------------------------------- paid USD booking guard
CREATE OR REPLACE FUNCTION public.bookings_currency_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM events e WHERE e.id = NEW.event_id AND e.currency <> 'VND' AND e.price_vnd > 0) THEN
    RAISE EXCEPTION 'PAID_BOOKING_NOT_AVAILABLE: Paid booking for events priced in this currency is not available yet.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.bookings_currency_guard() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS bookings_currency_guard ON public.bookings;
CREATE TRIGGER bookings_currency_guard
  BEFORE INSERT ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.bookings_currency_guard();

-- ---------------------------------------------------------------- create_event_draft
DROP FUNCTION IF EXISTS public.create_event_draft(text, text, text, text, date, time, bigint, int, text, text, text, text, jsonb, text, double precision, double precision, text, text, text, boolean, text, text, text);

CREATE OR REPLACE FUNCTION public.create_event_draft(
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
  p_neighborhood text DEFAULT NULL,
  p_tz text DEFAULT NULL
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
  v_dup_id text;
  v_country text;
  v_tz text;
  v_currency text;
  v_price bigint := greatest(COALESCE(p_price_vnd, 0), 0);
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

  -- 195: the venue's own zone and currency.
  v_country := upper(NULLIF(trim(COALESCE(p_country_code, '')), ''));
  v_currency := public.event_currency_for(v_country);
  IF v_currency IS NULL THEN
    RAISE EXCEPTION 'UNSUPPORTED_COUNTRY: banbe events can be in Vietnam or the United States.';
  END IF;
  v_tz := public.resolve_event_tz(v_country, p_state_province, p_tz);
  IF v_tz IS NULL THEN
    RAISE EXCEPTION 'TIMEZONE_UNKNOWN: Could not tell the time zone of this address. Pick the address again.';
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

    -- Duplicate-pending-event guard (107, restored by 195): the same logical event can't be
    -- recreated as a new row to get around the per-event resubmission limit.
    SELECT e.id INTO v_dup_id FROM events e
      WHERE e.organizer_id = v_organizer.id
        AND e.status IN ('review', 'draft')
        AND lower(trim(e.name)) = lower(trim(p_name))
        AND e.event_date IS NOT DISTINCT FROM p_event_date
        AND e.submitted_at > now() - interval '24 hours'
      LIMIT 1;
    IF v_dup_id IS NOT NULL THEN
      RAISE EXCEPTION 'DUPLICATE_PENDING_EVENT: An event with this name and date is already pending — edit and resubmit it instead of creating a new one (id=%).', v_dup_id;
    END IF;
  END IF;

  v_event_id := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(md5(gen_random_uuid()::text), 1, 6);

  v_starts_at := CASE WHEN p_event_date IS NOT NULL AND p_event_time IS NOT NULL
                       THEN (p_event_date + p_event_time) AT TIME ZONE v_tz
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
    description, price_vnd, price_cents, currency, capacity, seats_remaining, area,
    event_date, event_time, starts_at, tz, status, approval, visibility, submitted_at,
    cover_image, included, included_items, intro, lat, lng,
    address_line, city, postal_code, address_verified,
    country_code, state_province, neighborhood
  )
  VALUES (
    v_event_id, v_event_id, v_event_id, v_organizer.id,
    trim(p_name), v_category, v_cat_key, v_cat_label,
    COALESCE(p_description, ''),
    v_price, CASE WHEN v_currency = 'USD' THEN v_price ELSE v_price * 100 END, v_currency,
    p_capacity, p_capacity,
    COALESCE(p_location, ''),
    p_event_date, p_event_time, v_starts_at, v_tz,
    'review', 'host_approves', 'public', now(),
    COALESCE(trim(p_cover_image), ''),
    v_included_text,
    COALESCE(p_included_items, '[]'::jsonb),
    COALESCE(p_intro, ''),
    p_lat, p_lng,
    trim(COALESCE(p_address_line, '')), trim(COALESCE(p_city, '')), trim(COALESCE(p_postal_code, '')), true,
    v_country, NULLIF(trim(COALESCE(p_state_province, '')), ''), NULLIF(trim(COALESCE(p_neighborhood, '')), '')
  )
  RETURNING * INTO v_event;

  INSERT INTO event_status_history(event_id, action, from_status, to_status, reason, actor_id)
  VALUES (v_event_id, 'submit', NULL, 'review', '', auth.uid());

  RETURN v_event;
END;
$$;
REVOKE ALL ON FUNCTION public.create_event_draft(text, text, text, text, date, time, bigint, int, text, text, text, text, jsonb, text, double precision, double precision, text, text, text, boolean, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_event_draft(text, text, text, text, date, time, bigint, int, text, text, text, text, jsonb, text, double precision, double precision, text, text, text, boolean, text, text, text, text) TO authenticated;

-- ---------------------------------------------------------------- resubmit_event_for_review
DROP FUNCTION IF EXISTS public.resubmit_event_for_review(text, text, text, text, text, date, time, bigint, int, text, jsonb, text, double precision, double precision, text, text, text, boolean, text, text, text);

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
  p_neighborhood text DEFAULT NULL,
  p_tz text DEFAULT NULL
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
  v_window_start timestamptz;
  v_count int;
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
  v_tz text;
  v_currency text;
  v_price bigint := greatest(COALESCE(p_price_vnd, 0), 0);
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

  -- Row lock FIRST, before any counter logic (107): makes the check-and-increment atomic.
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

  -- Rolling-24h resubmission limit (107, restored by 195): 2 successful resubmissions per event.
  IF v_event.resubmission_window_start IS NULL
     OR now() - v_event.resubmission_window_start >= interval '24 hours' THEN
    v_window_start := now();
    v_count := 0;
  ELSE
    v_window_start := v_event.resubmission_window_start;
    v_count := v_event.resubmission_count;
  END IF;
  IF v_count >= 2 THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'RESUBMISSION_LIMIT_REACHED',
      'remaining_attempts', 0, 'next_eligible_at', v_window_start + interval '24 hours'
    );
  END IF;

  v_final_lat := COALESCE(p_lat, v_event.lat);
  v_final_lng := COALESCE(p_lng, v_event.lng);
  v_final_address_line := trim(COALESCE(p_address_line, v_event.address_line));
  v_final_city := trim(COALESCE(p_city, v_event.city));
  v_final_postal_code := trim(COALESCE(p_postal_code, v_event.postal_code));
  v_final_address_verified := COALESCE(p_address_verified, v_event.address_verified);
  v_final_area := trim(COALESCE(p_location, v_event.area));
  v_final_country_code := upper(NULLIF(trim(COALESCE(p_country_code, v_event.country_code, '')), ''));
  v_final_state_province := NULLIF(trim(COALESCE(p_state_province, v_event.state_province, '')), '');
  v_final_neighborhood := NULLIF(trim(COALESCE(p_neighborhood, v_event.neighborhood, '')), '');

  IF NOT v_final_address_verified
     OR length(v_final_address_line) = 0
     OR length(v_final_area) = 0
     OR length(v_final_city) = 0
     OR v_final_lat IS NULL OR v_final_lng IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADDRESS_NOT_VERIFIED');
  END IF;

  v_currency := public.event_currency_for(v_final_country_code);
  IF v_currency IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNSUPPORTED_COUNTRY');
  END IF;
  -- An untouched address keeps the zone it already had; a new address (or a new p_tz) re-derives it.
  v_tz := public.resolve_event_tz(v_final_country_code, v_final_state_province,
                                  COALESCE(p_tz, CASE WHEN p_country_code IS NULL AND p_state_province IS NULL THEN v_event.tz END));
  IF v_tz IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'TIMEZONE_UNKNOWN');
  END IF;

  v_starts_at := CASE WHEN p_event_date IS NOT NULL AND p_event_time IS NOT NULL
                       THEN (p_event_date + p_event_time) AT TIME ZONE v_tz
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
    event_date = p_event_date, event_time = p_event_time, starts_at = v_starts_at, tz = v_tz,
    price_vnd = v_price, price_cents = CASE WHEN v_currency = 'USD' THEN v_price ELSE v_price * 100 END,
    currency = v_currency,
    capacity = p_capacity, seats_remaining = p_capacity,
    cover_image = CASE WHEN length(trim(COALESCE(p_cover_image, ''))) > 0 THEN trim(p_cover_image) ELSE cover_image END,
    included = CASE WHEN length(v_included_text) > 0 THEN v_included_text ELSE included END,
    included_items = COALESCE(p_included_items, included_items),
    intro = COALESCE(p_intro, intro),
    lat = v_final_lat, lng = v_final_lng,
    address_line = v_final_address_line, city = v_final_city, postal_code = v_final_postal_code,
    address_verified = v_final_address_verified,
    country_code = v_final_country_code, state_province = v_final_state_province, neighborhood = v_final_neighborhood,
    status = 'review', submitted_at = now(), reviewed_at = NULL, reviewed_by = NULL, rejection_reason = '',
    withdrawal_reason = '', withdrawn_at = NULL,
    resubmission_count = v_count + 1, resubmission_window_start = v_window_start
  WHERE id = p_event_id;

  INSERT INTO event_status_history(event_id, action, from_status, to_status, reason, actor_id)
  VALUES (p_event_id, 'resubmit', v_event.status, 'review', '', auth.uid());

  RETURN jsonb_build_object(
    'success', true,
    'remaining_attempts', 2 - (v_count + 1),
    'next_eligible_at', CASE WHEN (v_count + 1) >= 2 THEN v_window_start + interval '24 hours' ELSE NULL END
  );
END;
$$;
REVOKE ALL ON FUNCTION public.resubmit_event_for_review(text, text, text, text, text, date, time, bigint, int, text, jsonb, text, double precision, double precision, text, text, text, boolean, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resubmit_event_for_review(text, text, text, text, text, date, time, bigint, int, text, jsonb, text, double precision, double precision, text, text, text, boolean, text, text, text, text) TO authenticated;

-- ---------------------------------------------------------------- host benchmarks (186) per currency + zone
-- Same k-anonymity rules as 186. New: one currency per pool (a USD price never mixes into VND
-- percentiles) and day/slot cells in each event's own zone. Old callers (two named args) get VND.
CREATE OR REPLACE FUNCTION public.benchmark_slot(p_starts_at timestamptz, p_tz text)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN extract(hour FROM p_starts_at AT TIME ZONE coalesce(p_tz, 'Asia/Ho_Chi_Minh')) < 17 THEN 'afternoon'
    WHEN extract(hour FROM p_starts_at AT TIME ZONE coalesce(p_tz, 'Asia/Ho_Chi_Minh')) < 21 THEN 'evening'
    ELSE 'late'
  END;
$$;

DROP FUNCTION IF EXISTS public.get_host_benchmarks(text, text);
CREATE OR REPLACE FUNCTION public.get_host_benchmarks(p_cat_key text, p_city text, p_currency text DEFAULT 'VND')
RETURNS jsonb
-- VOLATILE (not STABLE): it fills a session temp table. It writes nothing persistent.
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  k_events constant int := 5;
  k_orgs   constant int := 3;
  v_cat  text := lower(trim(COALESCE(p_cat_key, '')));
  v_city text := lower(trim(COALESCE(p_city, '')));
  v_currency text := upper(trim(COALESCE(p_currency, 'VND')));
  v_level text;
  v_out jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF v_currency NOT IN ('VND', 'USD') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;

  -- Base pool: public, not cancelled, started in the last 180 days or starting in the next 60.
  CREATE TEMP TABLE IF NOT EXISTS _bm_pool2 (
    id text, organizer_id text, cat_key text, city text, price_vnd int, capacity int,
    starts_at timestamptz, submitted_at timestamptz, started boolean, booked int,
    fill numeric, photos int, has_intro boolean, has_included boolean, keywords text[], tz text
  ) ON COMMIT DROP;
  TRUNCATE _bm_pool2;

  INSERT INTO _bm_pool2
  SELECT e.id, e.organizer_id, lower(COALESCE(e.cat_key, '')), lower(trim(COALESCE(e.city, ''))),
         e.price_vnd, e.capacity, e.starts_at, e.submitted_at, e.starts_at < now(),
         f.booked,
         CASE WHEN e.capacity > 0 THEN LEAST(f.booked::numeric / e.capacity, 1) END,
         (SELECT count(*)::int FROM event_photos p WHERE p.event_id = e.id),
         length(trim(COALESCE(e.intro, ''))) > 0,
         jsonb_typeof(e.included_items) = 'array' AND jsonb_array_length(e.included_items) > 0,
         COALESCE(e.keywords, '{}'), e.tz
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
    AND e.starts_at BETWEEN now() - interval '180 days' AND now() + interval '60 days'
    AND e.currency = v_currency;

  -- Fallback cascade: category+city -> category -> everything. First level that clears k wins.
  IF v_cat <> '' AND v_city <> '' AND (
       SELECT count(*) >= k_events AND count(DISTINCT organizer_id) >= k_orgs
       FROM _bm_pool2 WHERE cat_key = v_cat AND city = v_city) THEN
    v_level := 'category_city';
  ELSIF v_cat <> '' AND (
       SELECT count(*) >= k_events AND count(DISTINCT organizer_id) >= k_orgs
       FROM _bm_pool2 WHERE cat_key = v_cat) THEN
    v_level := 'category';
  ELSIF (SELECT count(*) >= k_events AND count(DISTINCT organizer_id) >= k_orgs FROM _bm_pool2) THEN
    v_level := 'all';
  ELSE
    RETURN jsonb_build_object('success', true, 'level', NULL, 'n', 0, 'currency', v_currency);
  END IF;

  DELETE FROM _bm_pool2
  WHERE NOT (CASE v_level
    WHEN 'category_city' THEN cat_key = v_cat AND city = v_city
    WHEN 'category' THEN cat_key = v_cat
    ELSE true END);

  WITH paid AS (SELECT price_vnd FROM _bm_pool2 WHERE price_vnd > 0),
  paid_stats AS (
    SELECT count(*) AS n, count(DISTINCT p.organizer_id) AS orgs,
           percentile_cont(0.25) WITHIN GROUP (ORDER BY p.price_vnd) AS p25,
           percentile_cont(0.5)  WITHIN GROUP (ORDER BY p.price_vnd) AS p50,
           percentile_cont(0.75) WITHIN GROUP (ORDER BY p.price_vnd) AS p75,
           min(p.price_vnd) AS lo, max(p.price_vnd) AS hi
    FROM _bm_pool2 p WHERE p.price_vnd > 0
  ),
  hist AS (
    SELECT CASE WHEN s.hi > s.lo THEN LEAST(width_bucket(p.price_vnd::numeric, s.lo::numeric, (s.hi + 1)::numeric, 10), 10) ELSE 1 END AS bucket,
           count(*) AS c
    FROM paid p CROSS JOIN paid_stats s
    GROUP BY 1
  ),
  started AS (SELECT * FROM _bm_pool2 WHERE started AND fill IS NOT NULL),
  started_stats AS (
    SELECT count(*) AS n, count(DISTINCT organizer_id) AS orgs,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY fill) AS fill_p50,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY capacity) AS cap_p50,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY booked) AS booked_p50
    FROM started
  ),
  cells AS (
    SELECT extract(isodow FROM starts_at AT TIME ZONE tz)::int AS dow,
           benchmark_slot(starts_at, tz) AS slot,
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
    FROM _bm_pool2 p CROSS JOIN LATERAL unnest(p.keywords) AS k
    WHERE length(trim(k)) > 0
    GROUP BY 1
  )
  SELECT jsonb_build_object(
    'success', true,
    'level', v_level,
    'currency', v_currency,
    'n', (SELECT count(*) FROM _bm_pool2),
    'free_share', (SELECT round(avg((price_vnd = 0)::int)::numeric, 3) FROM _bm_pool2),
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
REVOKE ALL ON FUNCTION public.get_host_benchmarks(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_host_benchmarks(text, text, text) TO authenticated;
