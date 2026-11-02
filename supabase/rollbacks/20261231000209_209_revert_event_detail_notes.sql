-- Rollback of 209 (event detail notes). Kept OUT of migrations/. Restores 204's field lists and 207's value shapes.
-- Refuses to run while any event still holds a 209 key (strip them first, or they would fail the table CHECK).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.events WHERE details ?| ARRAY['alcohol_note', 'dietary_note', 'id_required']) THEN
    RAISE EXCEPTION 'events hold 209 keys (alcohol_note / dietary_note / id_required): remove them first';
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
    -- 207
    WHEN 'cat2'        THEN jsonb_typeof(p_value) = 'string' AND p_value #>> '{}' IN ('supper', 'music', 'gallery', 'fashion', 'popup')
    WHEN 'intro_font'  THEN jsonb_typeof(p_value) = 'string' AND p_value #>> '{}' IN ('sans', 'serif', 'rounded', 'mono')
    WHEN 'intro_color' THEN jsonb_typeof(p_value) = 'string' AND p_value #>> '{}' IN ('ink', 'ink2', 'clay', 'honey', 'alert')
    ELSE false
  END;
$$;
