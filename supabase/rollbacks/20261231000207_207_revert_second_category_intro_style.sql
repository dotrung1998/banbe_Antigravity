-- Rollback for migration 207 (second category + introduction style). NOT in the migration chain.
-- Restores 204's event_details_value_ok and 203's set_event_details. Details holding the 207 keys (cat2, intro_font,
-- intro_color) or the second type's fields would fail the table CHECK / the writer afterwards, so strip the 207 keys
-- first and drop any field that is not the event's own type (take a dump of public.events before this).
BEGIN;
UPDATE public.events e
SET details = CASE
      WHEN (SELECT count(*) FROM jsonb_object_keys(d.kept)) <= 1 THEN '{}'::jsonb  -- only "v" left
      ELSE d.kept END
FROM (
  SELECT id, (SELECT COALESCE(jsonb_object_agg(k, v), '{}'::jsonb)
              FROM jsonb_each(ev.details) AS x(k, v)
              WHERE k = 'v' OR k = ANY (public.event_details_fields(ev.cat_key))) AS kept
  FROM public.events ev
  WHERE ev.details ?| ARRAY['cat2', 'intro_font', 'intro_color']
) d
WHERE e.id = d.id;

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

CREATE OR REPLACE FUNCTION public.set_event_details(p_event_id text, p_details jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cat text;
  v_allowed text[];
  v_details jsonb := COALESCE(p_details, '{}'::jsonb);
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;

  SELECT e.cat_key INTO v_cat
  FROM events e JOIN organizers o ON o.id = e.organizer_id
  WHERE e.id = p_event_id
    AND (o.owner_id = auth.uid() OR o.user_id = auth.uid() OR public.is_platform_admin());
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND'); END IF;

  IF NOT public.validate_event_details(v_details) THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_DETAILS');
  END IF;
  v_allowed := public.event_details_fields(v_cat);
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(v_details) k WHERE k <> 'v' AND NOT k = ANY (v_allowed)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'FIELD_NOT_FOR_TYPE');
  END IF;

  UPDATE events SET details = v_details WHERE id = p_event_id;
  RETURN jsonb_build_object('success', true, 'details', v_details);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_event_details(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_event_details(text, jsonb) TO authenticated;
COMMIT;
