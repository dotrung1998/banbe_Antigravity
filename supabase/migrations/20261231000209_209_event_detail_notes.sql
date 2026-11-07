-- 209 — Host-written notes under Event Detail's "Good to know" rows, and an optional photo-ID reminder (note 75).
--
-- Event Detail V8 shows alcohol, each dietary choice and the minimum age as rows. Their sub-lines had no data (the
-- mockup invented them), so the owner decided (2026-11-02) that the HOST writes them, optionally:
--   alcohol_note  free text under the alcohol row, 1..120 characters (every type: alcohol is a common field)
--   dietary_note  free text under the first dietary row, 1..120 characters (supper only: the type with `dietary`)
--   id_required   'yes' = "Bring a photo ID" under the minimum-age row (every type); absent = no line
-- None is required. All live inside the existing events.details object, so every client already deployed keeps loading
-- events (they skip keys they do not know). Clients save them best-effort and retry without them while this migration
-- is not applied (src/state/BanBeContext.jsx, AppState+Data.swift: NOTE_DETAIL_KEYS).
--
-- Only event_details_fields (which keys a type may hold) and event_details_value_ok (the shape of each key) change.
-- validate_event_details (the table CHECK) and set_event_details keep their 203/207 definitions and pick these up.
--
-- LOCAL HARNESS ONLY until the owner says otherwise: never pushed to production by this pass.
-- Rollback: supabase/rollbacks/20261231000209_209_revert_event_detail_notes.sql (kept OUT of migrations/).

CREATE OR REPLACE FUNCTION public.event_details_fields(p_cat_key text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_cat_key
    WHEN 'supper'  THEN ARRAY['dietary', 'dietary_note', 'dress_code', 'alcohol', 'alcohol_note', 'min_age', 'id_required']
    WHEN 'music'   THEN ARRAY['lineup', 'genre', 'format', 'alcohol', 'alcohol_note', 'min_age', 'id_required']
    WHEN 'gallery' THEN ARRAY['artists', 'medium', 'alcohol', 'alcohol_note', 'min_age', 'id_required']
    WHEN 'fashion' THEN ARRAY['brands', 'experience', 'price_range', 'alcohol', 'alcohol_note', 'min_age', 'id_required']
    WHEN 'popup'   THEN ARRAY['brands', 'entry_mode', 'price_range', 'alcohol', 'alcohol_note', 'min_age', 'id_required']
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
    -- 209: host-written sub-lines for Event Detail's "Good to know" rows, and the optional photo-ID reminder.
    WHEN 'alcohol_note' THEN jsonb_typeof(p_value) = 'string' AND length(btrim(p_value #>> '{}')) BETWEEN 1 AND 120
    WHEN 'dietary_note' THEN jsonb_typeof(p_value) = 'string' AND length(btrim(p_value #>> '{}')) BETWEEN 1 AND 120
    WHEN 'id_required'  THEN jsonb_typeof(p_value) = 'string' AND p_value #>> '{}' = 'yes'
    ELSE false
  END;
$$;
