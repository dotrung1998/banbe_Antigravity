-- LOCAL TEST HARNESS ONLY — never deployed, never run against a real project.
-- Migration 195: per-event time zone + currency, restored 107 protections, paid-USD booking guard,
-- per-currency benchmarks. Run through 24_event_tz_currency_run.sh, which first inserts the shared
-- vectors from tests/fixtures/event-market.json into pg_temp.vec_* tables. Rolled back at the end.
\set ON_ERROR_STOP on

CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', coalesce(u::text, ''), true) $$;
-- create_event_draft with a verified address; returns the new row.
CREATE FUNCTION pg_temp.mk(name text, d date, t time, price bigint, country text, state text, tz text DEFAULT NULL)
RETURNS events LANGUAGE sql AS $$
  SELECT * FROM public.create_event_draft(
    p_name => name, p_category => 'music', p_description => 'd', p_location => 'Area',
    p_event_date => d, p_event_time => t, p_price_vnd => price, p_capacity => 20,
    p_organizer_name => 'Alpha Events', p_lat => 10.0, p_lng => 106.0,
    p_address_line => '1 Main St', p_city => 'City', p_address_verified => true,
    p_country_code => country, p_state_province => state, p_tz => tz) $$;
CREATE FUNCTION pg_temp.err(sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $$;

DO $t$
DECLARE
  host uuid := '7a000002-0000-4000-8000-000000000002';
  goer uuid := '7a000001-0000-4000-8000-000000000001';
  d date := current_date + 40;
  e events; e2 events; r jsonb; msg text; v record; i int;
BEGIN
  -- On a brand-new container auth.users' sign-up trigger creates the seeded profiles as participants first, so the
  -- seed's own role never lands (see note 58, suite 13 T15a). This suite needs a real organizer.
  UPDATE profiles SET role = 'organizer' WHERE id = host;
  -- ===== M0 shared vectors (tests/fixtures/event-market.json)
  FOR v IN SELECT * FROM pg_temp.vec_tz LOOP
    PERFORM pg_temp.ok(public.event_tz_for(v.country, v.state) IS NOT DISTINCT FROM v.tz, format('M0a tz %s/%s', v.country, v.state));
  END LOOP;
  FOR v IN SELECT * FROM pg_temp.vec_cur LOOP
    PERFORM pg_temp.ok(public.event_currency_for(v.country) IS NOT DISTINCT FROM v.currency, format('M0b currency %s', v.country));
  END LOOP;
  FOR v IN SELECT * FROM pg_temp.vec_resolved LOOP
    PERFORM pg_temp.ok(public.resolve_event_tz(v.country, v.state, v.client_tz) IS NOT DISTINCT FROM v.tz, format('M0c resolved %s/%s/%s', v.country, v.state, v.client_tz));
  END LOOP;
  FOR v IN SELECT * FROM pg_temp.vec_wall LOOP
    PERFORM pg_temp.ok((v.d + v.t) AT TIME ZONE v.tz = v.utc, format('M0d wall clock %s %s %s', v.d, v.t, v.tz));
  END LOOP;

  -- ===== M1 privileges + columns
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.event_tz_for(text,text)', 'EXECUTE')
                     AND NOT has_function_privilege('authenticated', 'public.resolve_event_tz(text,text,text)', 'EXECUTE'), 'M1a helpers internal');
  PERFORM pg_temp.ok(NOT has_function_privilege('anon', 'public.create_event_draft(text,text,text,text,date,time without time zone,bigint,integer,text,text,text,text,jsonb,text,double precision,double precision,text,text,text,boolean,text,text,text,text)', 'EXECUTE')
                     AND has_function_privilege('authenticated', 'public.create_event_draft(text,text,text,text,date,time without time zone,bigint,integer,text,text,text,text,jsonb,text,double precision,double precision,text,text,text,boolean,text,text,text,text)', 'EXECUTE'),
                     'M1b create: authenticated only (112 had left it to PUBLIC)');
  PERFORM pg_temp.ok((SELECT count(*) = 1 FROM pg_proc WHERE proname = 'create_event_draft')
                     AND (SELECT count(*) = 1 FROM pg_proc WHERE proname = 'resubmit_event_for_review')
                     AND (SELECT count(*) = 1 FROM pg_proc WHERE proname = 'get_host_benchmarks'), 'M1c exactly one overload of each');
  PERFORM pg_temp.ok((SELECT bool_and(tz = 'Asia/Ho_Chi_Minh' AND currency = 'VND') FROM events WHERE id IN ('test_evt_a', 'test_evt_b')),
                     'M1d existing rows: Asia/Ho_Chi_Minh + VND');

  -- ===== M2 create: zone + currency from the location
  PERFORM pg_temp.as_user(host);
  e := pg_temp.mk('VN Night', d, '19:00', 150000, 'VN', 'Hồ Chí Minh');
  PERFORM pg_temp.ok(e.tz = 'Asia/Ho_Chi_Minh' AND e.currency = 'VND' AND e.starts_at = (d + time '19:00') AT TIME ZONE 'Asia/Ho_Chi_Minh'
                     AND e.price_vnd = 150000 AND e.price_cents = 15000000, 'M2a VN event unchanged behaviour');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM event_status_history WHERE event_id = e.id AND action = 'submit'), 'M2b submit history row restored (107)');
  e := pg_temp.mk('LA Night', d, '19:00', 1250, 'us', 'California');
  PERFORM pg_temp.ok(e.tz = 'America/Los_Angeles' AND e.currency = 'USD' AND e.country_code = 'US'
                     AND e.starts_at = (d + time '19:00') AT TIME ZONE 'America/Los_Angeles'
                     AND to_char(e.starts_at AT TIME ZONE 'America/Los_Angeles', 'HH24:MI') = '19:00', 'M2c US host''s 19:00 is 19:00 at the venue');
  PERFORM pg_temp.ok(e.price_vnd = 1250 AND e.price_cents = 1250, 'M2d USD price stored in cents');
  e := pg_temp.mk('Boise Night', d, '18:00', 0, 'US', 'Idaho', 'America/Boise');
  PERFORM pg_temp.ok(e.tz = 'America/Boise', 'M2e a real US client zone wins (multi-zone state)');
  e := pg_temp.mk('Tokyo Spoof', d, '18:00', 0, 'US', 'Texas', 'Asia/Tokyo');
  PERFORM pg_temp.ok(e.tz = 'America/Chicago', 'M2f a non-US client zone is ignored');
  msg := pg_temp.err(format($q$SELECT pg_temp.mk('Nowhere', %L, '18:00', 0, 'US', 'Atlantis')$q$, d));
  PERFORM pg_temp.ok(msg LIKE 'TIMEZONE_UNKNOWN%', 'M2g unknown US state without a zone is refused');
  msg := pg_temp.err(format($q$SELECT pg_temp.mk('Paris', %L, '18:00', 0, 'FR', 'Île-de-France')$q$, d));
  PERFORM pg_temp.ok(msg LIKE 'UNSUPPORTED_COUNTRY%', 'M2h countries other than VN/US are refused');
  msg := pg_temp.err(format($q$SELECT pg_temp.mk('LA Night', %L, '20:00', 0, 'US', 'California')$q$, d));
  PERFORM pg_temp.ok(msg LIKE 'DUPLICATE_PENDING_EVENT%', 'M2i duplicate pending guard restored (107)');
  msg := pg_temp.err(format($q$SELECT pg_temp.mk('Past', %L, '18:00', 0, 'US', 'Hawaii')$q$, current_date - 1));
  PERFORM pg_temp.ok(msg LIKE 'PAST_EVENT_NOT_ALLOWED%', 'M2j past check runs in the venue zone');

  -- ===== M3 resubmit: limit, history, zone kept/re-derived
  e := pg_temp.mk('Resubmit Me', d, '19:00', 2000, 'US', 'New York');
  UPDATE events SET status = 'draft' WHERE id = e.id;
  r := public.resubmit_event_for_review(p_event_id => e.id, p_name => 'Resubmit Me', p_category => 'music', p_description => 'd',
         p_location => 'Area', p_event_date => d, p_event_time => '20:00', p_price_vnd => 2500, p_capacity => 20);
  SELECT * INTO e2 FROM events WHERE id = e.id;
  PERFORM pg_temp.ok((r->>'success')::boolean AND (r->>'remaining_attempts')::int = 1, 'M3a resubmit ok, 1 attempt left (107 restored)');
  PERFORM pg_temp.ok(e2.tz = 'America/New_York' AND e2.currency = 'USD' AND e2.starts_at = (d + time '20:00') AT TIME ZONE 'America/New_York'
                     AND e2.price_vnd = 2500, 'M3b untouched address keeps its zone; new time in that zone');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM event_status_history WHERE event_id = e.id AND action = 'resubmit'), 'M3c resubmit history row restored (107)');
  UPDATE events SET status = 'draft' WHERE id = e.id;
  r := public.resubmit_event_for_review(p_event_id => e.id, p_name => 'Resubmit Me', p_category => 'music', p_description => 'd',
         p_location => 'Area', p_event_date => d, p_event_time => '20:00', p_price_vnd => 2500, p_capacity => 20,
         p_country_code => 'US', p_state_province => 'Colorado');
  SELECT * INTO e2 FROM events WHERE id = e.id;
  PERFORM pg_temp.ok((r->>'success')::boolean AND e2.tz = 'America/Denver', 'M3d a new address re-derives the zone');
  UPDATE events SET status = 'draft' WHERE id = e.id;
  r := public.resubmit_event_for_review(p_event_id => e.id, p_name => 'Resubmit Me', p_category => 'music', p_description => 'd',
         p_location => 'Area', p_event_date => d, p_event_time => '20:00', p_price_vnd => 2500, p_capacity => 20);
  PERFORM pg_temp.ok(r->>'error' = 'RESUBMISSION_LIMIT_REACHED' AND r ? 'next_eligible_at', 'M3e third resubmit in 24h refused (107 restored)');

  -- ===== M4 paid USD booking guard
  e := pg_temp.mk('Paid USD', d, '19:00', 1500, 'US', 'California');
  e2 := pg_temp.mk('Free USD', d, '19:00', 0, 'US', 'California');
  UPDATE events SET status = 'live' WHERE id IN (e.id, e2.id);
  msg := pg_temp.err(format($q$INSERT INTO bookings (event_id, user_id, qty, total_vnd) VALUES (%L, %L, 1, 1500)$q$, e.id, goer));
  PERFORM pg_temp.ok(msg LIKE 'PAID_BOOKING_NOT_AVAILABLE%', 'M4a paid USD booking refused server-side');
  msg := pg_temp.err(format($q$INSERT INTO bookings (event_id, user_id, qty, total_vnd) VALUES (%L, %L, 1, 0)$q$, e2.id, goer));
  PERFORM pg_temp.ok(msg IS NULL, 'M4b free USD booking allowed');
  msg := pg_temp.err($q$INSERT INTO bookings (event_id, user_id, qty, total_vnd) VALUES ('test_evt_b', '7a000003-0000-4000-8000-000000000003', 1, 90000)$q$);
  PERFORM pg_temp.ok(msg IS NULL, 'M4c paid VND booking unchanged');

  -- ===== M5 benchmarks: one currency per pool, VND default for old callers
  INSERT INTO organizers (id, name, owner_id, user_id) SELECT 'bm_org_' || g, 'BM ' || g, NULL, NULL FROM generate_series(1, 3) g;
  INSERT INTO events (id, key, name, organizer_id, status, visibility, price_vnd, currency, tz, capacity, starts_at, cat_key, city)
  SELECT 'bm_vnd_' || g, 'bm_vnd_' || g, 'BM VND ' || g, 'bm_org_' || (g % 3 + 1), 'live', 'public', 100000 * g, 'VND', 'Asia/Ho_Chi_Minh', 20,
         now() + (g || ' days')::interval, 'jazzbm', 'bmcity'
  FROM generate_series(1, 6) g;
  INSERT INTO events (id, key, name, organizer_id, status, visibility, price_vnd, currency, tz, capacity, starts_at, cat_key, city)
  SELECT 'bm_usd_' || g, 'bm_usd_' || g, 'BM USD ' || g, 'bm_org_' || (g % 3 + 1), 'live', 'public', 1000 * g, 'USD', 'America/Chicago', 20,
         now() + (g || ' days')::interval, 'jazzbm', 'bmcity'
  FROM generate_series(1, 5) g;
  r := public.get_host_benchmarks(p_cat_key => 'jazzbm', p_city => 'bmcity');
  PERFORM pg_temp.ok(r->>'currency' = 'VND' AND r->>'level' = 'category_city' AND (r->>'n')::int = 6
                     AND (r->'price'->>'max')::int = 600000, 'M5a old 2-arg call: VND pool only');
  r := public.get_host_benchmarks(p_cat_key => 'jazzbm', p_city => 'bmcity', p_currency => 'USD');
  PERFORM pg_temp.ok(r->>'currency' = 'USD' AND r->>'level' = 'category_city' AND (r->>'n')::int = 5
                     AND (r->'price'->>'max')::int = 5000, 'M5b USD pool never mixes VND prices');
  r := public.get_host_benchmarks(p_cat_key => 'jazzbm', p_city => 'bmcity', p_currency => 'EUR');
  PERFORM pg_temp.ok(r->>'error' = 'INVALID_VALUE', 'M5c unknown currency refused');
  PERFORM pg_temp.ok(public.benchmark_slot(timestamptz '2027-03-07T03:00:00Z', 'America/Los_Angeles') = 'evening'
                     AND public.benchmark_slot(timestamptz '2027-03-07T03:00:00Z', 'Asia/Ho_Chi_Minh') = 'afternoon', 'M5d slots in the event''s own zone');

  RAISE NOTICE 'US RESULT: ALL PASS';
END $t$;

ROLLBACK;
