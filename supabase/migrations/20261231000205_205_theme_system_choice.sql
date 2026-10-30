-- Migration 205 (note 66, Simple Shell): profiles.theme may also be 'system'.
-- 'system' means "follow the device's light/dark setting". New installs start
-- on it (web + iOS); accounts that already saved 'light' or 'dark' keep it.
-- The column default stays 'light' so nothing changes for existing rows.
-- The inline CHECK from migration 018 has the generated name profiles_theme_check.

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_theme_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_theme_check CHECK (theme IN ('light', 'dark', 'system'));
