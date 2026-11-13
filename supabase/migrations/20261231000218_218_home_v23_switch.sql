-- Migration 218: admin switch `home_v23`, seeded OFF (note 81).
-- On = the web Home, the Browse by type / See all screen and Event Detail use the v2.3 design (paged Shortlist with
-- end cards, host deck, live line sheet, compact reserve bar with the 4+ stepper). Builds on simple_shell.
-- Client-only switch: no data changes. Web only for now, iOS knows the key but ignores it.

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('home_v23', 'Layout: web Home, Browse by type and Event Detail use the v2.3 design (needs simple_shell)', '218')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('home_v23', false)
ON CONFLICT (key) DO NOTHING;
