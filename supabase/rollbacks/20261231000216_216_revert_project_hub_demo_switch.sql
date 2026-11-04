-- Revert 216: drop the project_hub_demo switch (clients treat a missing key as off).
DELETE FROM public.app_feature_flags WHERE key = 'project_hub_demo';
DELETE FROM public.app_feature_flag_defs WHERE key = 'project_hub_demo';
