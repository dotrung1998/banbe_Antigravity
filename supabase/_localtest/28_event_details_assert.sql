-- LOCAL TEST HARNESS ONLY — never deployed, never run against a real project.
-- Migration 203: events.details (event type profiles). Needs the vectors the runner builds from
-- src/data/eventTypeProfiles.json + tests/fixtures/event-types.json (temp tables vec_fields, vec_clean).
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', coalesce(u::text, ''), true) $$;

DO $t$
DECLARE
  host uuid := '7a000002-0000-4000-8000-000000000002';
  goer uuid := '7a000001-0000-4000-8000-000000000001';
  r jsonb; v record;
BEGIN
  -- E0: the server's field list per type is exactly the shared profile file's.
  FOR v IN SELECT type_key, fields FROM vec_fields LOOP
    PERFORM pg_temp.ok((SELECT array_agg(f ORDER BY f) FROM unnest(public.event_details_fields(v.type_key)) f) IS NOT DISTINCT FROM
                       (SELECT array_agg(f ORDER BY f) FROM unnest(v.fields) f), 'E0 fields of ' || v.type_key);
  END LOOP;
  PERFORM pg_temp.ok((SELECT enabled FROM app_feature_flags WHERE key = 'event_type_profiles') = false, 'E0b switch seeded OFF');
  PERFORM pg_temp.ok((SELECT count(*) FROM app_event_names WHERE name IN ('create_event_type_selected', 'create_event_still_needed_tapped')) = 2, 'E0c analytics names');
  PERFORM pg_temp.ok(NOT has_function_privilege('anon', 'public.set_event_details(text, jsonb)', 'EXECUTE')
                     AND has_function_privilege('authenticated', 'public.set_event_details(text, jsonb)', 'EXECUTE'), 'E0d privileges');

  -- E1: every client-cleaned value is accepted as-is (the client never sends what the server rejects).
  FOR v IN SELECT label, details FROM vec_clean LOOP
    PERFORM pg_temp.ok(public.validate_event_details(v.details), 'E1 client output valid: ' || v.label);
  END LOOP;

  -- E2: invalid shapes.
  PERFORM pg_temp.ok(NOT public.validate_event_details('{"dietary":["vegan"]}'), 'E2a version required');
  PERFORM pg_temp.ok(NOT public.validate_event_details('{"v":1}'), 'E2b version alone is not a value');
  PERFORM pg_temp.ok(NOT public.validate_event_details('{"v":2,"byo":"no"}'), 'E2c unknown version');
  PERFORM pg_temp.ok(NOT public.validate_event_details('{"v":1,"byo":"beer"}'), 'E2d unknown option');
  PERFORM pg_temp.ok(NOT public.validate_event_details('{"v":1,"dietary":["vegan","vegan"]}'), 'E2e duplicate option');
  PERFORM pg_temp.ok(NOT public.validate_event_details('{"v":1,"dietary":[]}'), 'E2f empty list');
  PERFORM pg_temp.ok(NOT public.validate_event_details(jsonb_build_object('v', 1, 'dress_code', repeat('x', 81))), 'E2g text too long');
  PERFORM pg_temp.ok(NOT public.validate_event_details('{"v":1,"spicy":true}'), 'E2h unknown field');
  PERFORM pg_temp.ok(NOT public.validate_event_details('[]'), 'E2i not an object');
  PERFORM pg_temp.ok(public.validate_event_details('{}'), 'E2j empty is valid');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM events WHERE details <> '{}'::jsonb), 'E2k existing events stay {}');

  -- E3: the writer.
  UPDATE events SET cat_key = 'supper' WHERE id = 'test_evt_a';
  UPDATE events SET cat_key = 'music' WHERE id = 'test_evt_b';
  PERFORM pg_temp.as_user(NULL);
  r := public.set_event_details('test_evt_a', '{"v":1,"byo":"wine"}');
  PERFORM pg_temp.ok(r->>'error' = 'AUTH_REQUIRED', 'E3a signed out');
  PERFORM pg_temp.as_user(goer);
  r := public.set_event_details('test_evt_a', '{"v":1,"byo":"wine"}');
  PERFORM pg_temp.ok(r->>'error' = 'EVENT_NOT_FOUND', 'E3b not the host');
  PERFORM pg_temp.as_user(host);
  r := public.set_event_details('test_evt_a', '{"v":1,"byo":"wine","dietary":["vegan"]}');
  PERFORM pg_temp.ok((r->>'success')::boolean AND (SELECT details->>'byo' FROM events WHERE id = 'test_evt_a') = 'wine', 'E3c host writes');
  r := public.set_event_details('test_evt_a', '{"v":1,"byo":"beer"}');
  PERFORM pg_temp.ok(r->>'error' = 'INVALID_DETAILS' AND (SELECT details->>'byo' FROM events WHERE id = 'test_evt_a') = 'wine', 'E3d invalid rejected, old kept');
  r := public.set_event_details('test_evt_b', '{"v":1,"byo":"wine"}');
  PERFORM pg_temp.ok(r->>'error' = 'FIELD_NOT_FOR_TYPE', 'E3e a supper field on a music event');
  r := public.set_event_details('test_evt_a', '{}');
  PERFORM pg_temp.ok((r->>'success')::boolean AND (SELECT details FROM events WHERE id = 'test_evt_a') = '{}'::jsonb, 'E3f clear');

  -- E4: changing the category never fails on details left over from the old type.
  PERFORM public.set_event_details('test_evt_a', '{"v":1,"byo":"any"}');
  UPDATE events SET cat_key = 'music' WHERE id = 'test_evt_a';
  PERFORM pg_temp.ok((SELECT cat_key FROM events WHERE id = 'test_evt_a') = 'music', 'E4a category change with old details');
  r := public.set_event_details('test_evt_a', '{}');
  PERFORM pg_temp.ok((r->>'success')::boolean, 'E4b the new type clears them');

  -- E5: a direct write cannot bypass the CHECK.
  PERFORM pg_temp.ok((SELECT count(*) FROM pg_constraint WHERE conname = 'events_details_valid') = 1, 'E5 CHECK present');
  RAISE NOTICE 'DETAILS RESULT: ALL PASS';
END $t$;
ROLLBACK;
