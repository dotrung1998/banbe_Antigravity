-- Revert 221: drop the unified_discovery switch (clients treat a missing key as off).
DELETE FROM public.app_feature_flags WHERE key = 'unified_discovery';
DELETE FROM public.app_feature_flag_defs WHERE key = 'unified_discovery';
