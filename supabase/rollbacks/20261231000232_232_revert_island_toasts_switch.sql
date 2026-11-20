-- Revert 232: drop the island_toasts switch (clients treat a missing key as off).
DELETE FROM public.app_feature_flags WHERE key = 'island_toasts';
DELETE FROM public.app_feature_flag_defs WHERE key = 'island_toasts';
