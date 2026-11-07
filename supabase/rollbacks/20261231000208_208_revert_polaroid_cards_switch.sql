-- Revert 208: drop the polaroid_cards switch (clients treat a missing key as off).
DELETE FROM public.app_feature_flags WHERE key = 'polaroid_cards';
DELETE FROM public.app_feature_flag_defs WHERE key = 'polaroid_cards';
