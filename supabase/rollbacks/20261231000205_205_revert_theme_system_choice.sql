-- Revert 205: map 'system' back to 'light', then restore the two-value CHECK from migration 018.
UPDATE public.profiles SET theme = 'light' WHERE theme = 'system';
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_theme_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_theme_check CHECK (theme IN ('light', 'dark'));
