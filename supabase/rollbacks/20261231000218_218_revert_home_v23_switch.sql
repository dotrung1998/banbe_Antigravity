-- Revert 218: drop the home_v23 switch (clients treat a missing key as off).
DELETE FROM public.app_feature_flags WHERE key = 'home_v23';
DELETE FROM public.app_feature_flag_defs WHERE key = 'home_v23';
