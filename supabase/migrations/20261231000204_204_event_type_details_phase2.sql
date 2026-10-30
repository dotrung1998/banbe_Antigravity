-- 204 — Event type details, phase 2 (note 66; phase 1 was 203, note 65).
--
-- Every type now has facts, and alcohol + minimum age are fields of EVERY type (required by the create form):
--   common   alcohol (none | included | paid | byo), min_age ('16' | '18' | '21'; banbe's minimum is 16, so no "all ages")
--   supper   dietary (multi), dress_code (text ≤80)          -- 203's supper `byo` is folded into alcohol = 'byo'
--   music    lineup (list), genre (multi), format (enum)
--   gallery  artists (list), medium (multi)
--   fashion  brands (list), experience (enum), price_range (enum)
--   popup    brands (list), entry_mode (enum), price_range (enum)
-- A list is a JSON array of 1..N distinct strings, each 1..60 characters after trimming (lineup ≤6, artists and
-- brands ≤8). Same shape the clients' cleanDetails / EventTypes.clean produce from src/data/eventTypeProfiles.json;
-- supabase/_localtest/28_event_details_assert.sql checks this file against it.
--
-- Only the two field functions change. validate_event_details (the table CHECK) and set_event_details (the only
-- writer, owner or admin, current type's fields only) keep their 203 definitions and pick these up. No event had
-- details when this was written (checked on production 2026-10-30: all {}), so dropping `byo` strands no row; the
-- guard below refuses to run if that is no longer true.
--
-- Rollback: supabase/rollbacks/20261231000204_204_revert_event_type_details_phase2.sql (kept OUT of migrations/).

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.events WHERE details ? 'byo') THEN
    RAISE EXCEPTION 'events with details.byo exist: map them to alcohol first';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.event_details_fields(p_cat_key text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_cat_key
    WHEN 'supper'  THEN ARRAY['dietary', 'dress_code', 'alcohol', 'min_age']
    WHEN 'music'   THEN ARRAY['lineup', 'genre', 'format', 'alcohol', 'min_age']
    WHEN 'gallery' THEN ARRAY['artists', 'medium', 'alcohol', 'min_age']
    WHEN 'fashion' THEN ARRAY['brands', 'experience', 'price_range', 'alcohol', 'min_age']
    WHEN 'popup'   THEN ARRAY['brands', 'entry_mode', 'price_range', 'alcohol', 'min_age']
    ELSE ARRAY[]::text[]
  END;
$$;

-- A multi choice: 1..p_max distinct ids from p_allowed.
CREATE OR REPLACE FUNCTION public.event_details_multi_ok(p_value jsonb, p_allowed text[], p_max int)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_typeof(p_value) = 'array'
    AND jsonb_array_length(p_value) BETWEEN 1 AND p_max
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p_value) e WHERE jsonb_typeof(e) <> 'string' OR NOT (e #>> '{}') = ANY (p_allowed))
    AND (SELECT count(DISTINCT e) FROM jsonb_array_elements(p_value) e) = jsonb_array_length(p_value);
$$;

-- A list of names: 1..p_max distinct strings, each already trimmed and 1..60 characters.
CREATE OR REPLACE FUNCTION public.event_details_list_ok(p_value jsonb, p_max int)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_typeof(p_value) = 'array'
    AND jsonb_array_length(p_value) BETWEEN 1 AND p_max
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_value) e
      WHERE jsonb_typeof(e) <> 'string' OR (e #>> '{}') <> btrim(e #>> '{}') OR length(e #>> '{}') NOT BETWEEN 1 AND 60)
    AND (SELECT count(DISTINCT e) FROM jsonb_array_elements(p_value) e) = jsonb_array_length(p_value);
$$;

-- One field's value, by field id (a field id means the same thing in every type that has it).
CREATE OR REPLACE FUNCTION public.event_details_value_ok(p_field text, p_value jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_field
    WHEN 'alcohol'     THEN jsonb_typeof(p_value) = 'string' AND p_value #>> '{}' IN ('none', 'included', 'paid', 'byo')
    WHEN 'min_age'     THEN jsonb_typeof(p_value) = 'string' AND p_value #>> '{}' IN ('16', '18', '21')
    WHEN 'dietary'     THEN public.event_details_multi_ok(p_value, ARRAY['vegetarian', 'vegan', 'pescatarian', 'halal', 'gluten_free', 'can_accommodate'], 6)
    WHEN 'dress_code'  THEN jsonb_typeof(p_value) = 'string' AND length(btrim(p_value #>> '{}')) BETWEEN 1 AND 80
    WHEN 'lineup'      THEN public.event_details_list_ok(p_value, 6)
    WHEN 'genre'       THEN public.event_details_multi_ok(p_value, ARRAY['jazz', 'acoustic', 'electronic', 'indie', 'classical', 'folk', 'experimental'], 7)
    WHEN 'format'      THEN jsonb_typeof(p_value) = 'string' AND p_value #>> '{}' IN ('seated', 'standing', 'mixed')
    WHEN 'artists'     THEN public.event_details_list_ok(p_value, 8)
    WHEN 'medium'      THEN public.event_details_multi_ok(p_value, ARRAY['photography', 'painting', 'lacquer', 'print', 'sculpture', 'installation'], 6)
    WHEN 'brands'      THEN public.event_details_list_ok(p_value, 8)
    WHEN 'experience'  THEN jsonb_typeof(p_value) = 'string' AND p_value #>> '{}' IN ('show', 'fitting', 'sale', 'talk')
    WHEN 'price_range' THEN jsonb_typeof(p_value) = 'string' AND p_value #>> '{}' IN ('budget', 'mid', 'premium')
    WHEN 'entry_mode'  THEN jsonb_typeof(p_value) = 'string' AND p_value #>> '{}' IN ('drop_in', 'timed')
    ELSE false
  END;
$$;
