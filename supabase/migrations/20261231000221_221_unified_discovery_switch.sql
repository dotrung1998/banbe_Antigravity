-- Migration 221: admin switch `unified_discovery`, seeded OFF (note 99).
-- On = Home and Map share ONE search, type, time, price and sort (docs/prototype/unified-home-map-prototype-v2.html):
-- the Home tabs are the shared time, Browse by type filters Home in place (5 busiest types + an "All types" tile with
-- its own search), the Search overlay links to Filters, and the Map gets the time chip + popover, area bubbles with
-- category glyphs, a card carousel with a preview card and a compact zoom capsule. Builds on home_v23 (+ simple_shell).
-- Client-only switch: no data changes. Rollback: supabase/rollbacks/20261231000221_221_revert_unified_discovery_switch.sql

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('unified_discovery', 'Layout: Home and Map share one search, type, time and filters (needs home_v23)', '221')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('unified_discovery', false)
ON CONFLICT (key) DO NOTHING;
