-- 201 — Onboarding demo version switch (note 63).
--
-- `onboarding_v2` picks which public onboarding everyone sees:
--   OFF (or missing) = Version 1: still Welcome screen + the 4 text pages of "How banbe works".
--   ON               = Version 2: animated Welcome entrance + swipeable demo screens per "How banbe works" section.
-- Read signed out through get_feature_flags() (187), so the Welcome screen can follow it. Client-only switch: no server
-- function checks it. Seeded OFF so nothing changes until an admin flips it in Account > Admin > Feature switches.
--
-- Rollback: supabase/rollbacks/20261231000201_201_revert_onboarding_v2_switch.sql (kept OUT of migrations/).

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('onboarding_v2', 'Onboarding demo: off = Version 1 (text story), on = Version 2 (animated welcome + swipeable demos)', '201')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('onboarding_v2', false)
ON CONFLICT (key) DO NOTHING;
