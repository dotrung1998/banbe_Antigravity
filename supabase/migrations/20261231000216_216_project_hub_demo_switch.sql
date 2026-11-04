-- Migration 216 (note 76): admin switch `project_hub_demo`, seeded OFF.
-- On = ADMIN accounts see a "Project hub demo" entry that opens the Event Project Hub on built-in sample data (the same
-- synthetic data the phases were tested with), to show the feature to colleagues. Everything stays on the device: no
-- project is created, no RPC writes, nothing reaches other users. Works while event_project_hub is off. Client-only
-- switch: no server behaviour depends on it.

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('project_hub_demo', 'Event Project Hub: admins can open a demo hub on sample data (nothing is saved)', '216')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('project_hub_demo', false)
ON CONFLICT (key) DO NOTHING;
