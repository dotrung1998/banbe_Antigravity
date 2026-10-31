-- Migration 208 (note 70, Calm Pass phase 3): admin switch `polaroid_cards`, seeded OFF.
-- On = Home's event cards (cards view) are drawn as polaroids: the photo inset in a
-- paper mat with the caption below. Off = the current cards, unchanged. Client-only
-- switch: no server behaviour depends on it.

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('polaroid_cards', 'Calm Pass: Home event cards drawn as polaroids (photo inset in a mat, caption below)', '208')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('polaroid_cards', false)
ON CONFLICT (key) DO NOTHING;
