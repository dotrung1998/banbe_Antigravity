-- Revert 206: drop the simple_shell switch (clients treat a missing key as off).
DELETE FROM public.app_feature_flags WHERE key = 'simple_shell';
DELETE FROM public.app_feature_flag_defs WHERE key = 'simple_shell';
