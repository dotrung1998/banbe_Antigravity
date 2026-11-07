-- Rollback for migration 204 (event type details, phase 2). NOT in the migration chain.
-- Restores 203's field functions (supper only: dietary, byo, dress_code). Phase-2 details already stored would then
-- fail the table CHECK on their next write, so clear them first (take a dump of public.events before this).
BEGIN;
UPDATE public.events SET details = '{}'::jsonb WHERE details <> '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.event_details_fields(p_cat_key text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_cat_key
    WHEN 'supper' THEN ARRAY['dietary', 'byo', 'dress_code']
    ELSE ARRAY[]::text[]
  END;
$$;

CREATE OR REPLACE FUNCTION public.event_details_value_ok(p_field text, p_value jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_field
    WHEN 'dietary' THEN
      jsonb_typeof(p_value) = 'array'
      AND jsonb_array_length(p_value) BETWEEN 1 AND 6
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_value) e
        WHERE jsonb_typeof(e) <> 'string'
           OR e #>> '{}' NOT IN ('vegetarian', 'vegan', 'pescatarian', 'halal', 'gluten_free', 'can_accommodate'))
      AND (SELECT count(DISTINCT e) FROM jsonb_array_elements(p_value) e) = jsonb_array_length(p_value)
    WHEN 'byo' THEN
      jsonb_typeof(p_value) = 'string' AND p_value #>> '{}' IN ('no', 'wine', 'any')
    WHEN 'dress_code' THEN
      jsonb_typeof(p_value) = 'string' AND length(btrim(p_value #>> '{}')) BETWEEN 1 AND 80
    ELSE false
  END;
$$;

DROP FUNCTION IF EXISTS public.event_details_multi_ok(jsonb, text[], int);
DROP FUNCTION IF EXISTS public.event_details_list_ok(jsonb, int);
COMMIT;
