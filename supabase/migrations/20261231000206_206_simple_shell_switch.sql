-- Migration 206 (note 66, Simple Shell): admin switch `simple_shell`, seeded OFF.
-- On = the simplified Home (always-visible Going out | Hosting switch, one main
-- block at the top, map as a Home view) and the 5-slot dock with a centre "+"
-- for everyone. Off = the current Home and dock, unchanged. Client-only switch:
-- no server behaviour depends on it.

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('simple_shell', 'Simple Shell: simplified Home with a Going out | Hosting switch, map as a Home view, 5-slot dock with a centre "+"', '206')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('simple_shell', false)
ON CONFLICT (key) DO NOTHING;
