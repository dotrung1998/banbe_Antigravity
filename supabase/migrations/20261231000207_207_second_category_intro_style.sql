-- 207 — Two categories shape one event, and the introduction can be styled (note 69).
--
-- Until now the first picked category was the only one with facts: set_event_details accepted that type's fields
-- only, and a second category was saved as a plain keyword. Now:
--   cat2         the second category (one of the five types, never the same as events.cat_key). Its fields are
--                accepted too, so a supper club + music night can list dietary options AND a lineup. Shared fields
--                (alcohol, min_age) exist once.
--   intro_font   the introduction's font: sans | serif | rounded | mono
--   intro_color  the introduction's colour, a theme token so it reads in light and dark: ink | ink2 | clay | honey | alert
--
-- All three live inside the existing events.details object as plain strings, so every client already deployed keeps
-- loading events (they skip keys they do not know, and the event query is unchanged).
--
-- Only event_details_value_ok (the shape of each key) and set_event_details (which keys this event may hold) change.
-- validate_event_details (the table CHECK) and every grant keep their 203/204 definitions.
--
-- Rollback: supabase/rollbacks/20261231000207_207_revert_second_category_intro_style.sql (kept OUT of migrations/).

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

CREATE OR REPLACE FUNCTION public.set_event_details(p_event_id text, p_details jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cat text;
  v_cat2 text;
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

  v_cat2 := v_details ->> 'cat2';
  IF v_cat2 IS NOT NULL AND v_cat2 = v_cat THEN
    RETURN jsonb_build_object('success', false, 'error', 'SAME_CATEGORY');
  END IF;

  -- The event's own type, the second type (when picked), and the three 207 keys every event may hold.
  v_allowed := public.event_details_fields(v_cat)
            || CASE WHEN v_cat2 IS NULL THEN ARRAY[]::text[] ELSE public.event_details_fields(v_cat2) END
            || ARRAY['cat2', 'intro_font', 'intro_color'];
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(v_details) k WHERE k <> 'v' AND NOT k = ANY (v_allowed)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'FIELD_NOT_FOR_TYPE');
  END IF;

  UPDATE events SET details = v_details WHERE id = p_event_id;
  RETURN jsonb_build_object('success', true, 'details', v_details);
END;
$$;

-- CREATE OR REPLACE keeps the 203 grants; restated so the file is self-describing.
REVOKE EXECUTE ON FUNCTION public.set_event_details(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_event_details(text, jsonb) TO authenticated;
