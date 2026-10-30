-- 203 — Event type details (note 64).
--
-- Each kind of event can publish a few typed facts (a supper club: dietary options, BYO, dress code) instead of
-- one shape for every event. They live in ONE versioned JSONB column, not a column per attribute:
--   events.details = {}                          nothing published (every existing event, and every type with no fields)
--   events.details = {"v":1, "<field>": <value>} only fields the event type lists, values from fixed option ids
-- The field list per type is src/data/eventTypeProfiles.json (`detailFields`), which web and iOS both read;
-- supabase/_localtest/28_event_details_assert.sql checks this file against it.
--
-- The table CHECK validates the shape against EVERY type's fields, so changing an event's category (resubmit)
-- can never fail on details left over from the old type. set_event_details() is the only writer and also
-- requires every key to belong to the event's CURRENT type; clients call it after create/resubmit (same as
-- set_event_keywords, 108) and only show the current type's facts.
--
-- Also: switch `event_type_profiles` (seeded OFF; client-only, nothing changes until an admin turns it on) and the
-- analytics names create_event_type_selected{type} / create_event_still_needed_tapped{field} (196 whitelist; the
-- shared contract is tests/fixtures/app-events.json).
--
-- Rollback: supabase/rollbacks/20261231000203_203_revert_event_type_details.sql (kept OUT of migrations/).

-- ---------------------------------------------------------------------------
-- 1. The field list per type (keep in step with src/data/eventTypeProfiles.json)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.event_details_fields(p_cat_key text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_cat_key
    WHEN 'supper' THEN ARRAY['dietary', 'byo', 'dress_code']
    ELSE ARRAY[]::text[]
  END;
$$;

-- One field's value, by field id (field ids are unique across types).
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

-- {} or {"v":1, ...known fields of ANY type with valid values}.
CREATE OR REPLACE FUNCTION public.validate_event_details(p jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT p IS NOT NULL AND jsonb_typeof(p) = 'object' AND (
    p = '{}'::jsonb
    OR (
      p -> 'v' = '1'::jsonb
      AND (SELECT count(*) FROM jsonb_object_keys(p)) > 1
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_each(p) kv
        WHERE kv.key <> 'v' AND NOT public.event_details_value_ok(kv.key, kv.value))
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- 2. events.details
-- ---------------------------------------------------------------------------
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS details jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_details_valid;
ALTER TABLE public.events ADD CONSTRAINT events_details_valid CHECK (public.validate_event_details(details));

-- ---------------------------------------------------------------------------
-- 3. The writer: owner (or a platform admin), current type's fields only
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 4. Switch + analytics names
-- ---------------------------------------------------------------------------
INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('event_type_profiles', 'Event types: the create form, Event Detail and Home adapt to the kind of event (supper club first)', '203')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('event_type_profiles', false)
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.app_event_names (name, props, added_in) VALUES
  ('create_event_type_selected', ARRAY['type'], '203'),
  ('create_event_still_needed_tapped', ARRAY['field'], '203')
ON CONFLICT (name) DO NOTHING;
