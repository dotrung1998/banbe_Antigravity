-- Rollback for migration 203 (event type details). NOT in the migration chain.
-- Clients treat a missing `details` column as {} and a missing `event_type_profiles` switch as off.
-- Published details are lost: take a dump of public.events first if any event has details <> '{}'.
BEGIN;
DROP FUNCTION IF EXISTS public.set_event_details(text, jsonb);
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_details_valid;
ALTER TABLE public.events DROP COLUMN IF EXISTS details;
DROP FUNCTION IF EXISTS public.validate_event_details(jsonb);
DROP FUNCTION IF EXISTS public.event_details_value_ok(text, jsonb);
DROP FUNCTION IF EXISTS public.event_details_fields(text);
DELETE FROM public.app_events WHERE name IN ('create_event_type_selected', 'create_event_still_needed_tapped');
DELETE FROM public.app_event_names WHERE name IN ('create_event_type_selected', 'create_event_still_needed_tapped');
DELETE FROM public.app_feature_flags WHERE key = 'event_type_profiles';
DELETE FROM public.app_feature_flag_defs WHERE key = 'event_type_profiles';
COMMIT;
