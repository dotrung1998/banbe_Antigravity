-- Revert 217: drop the ticket_demo switch (clients treat a missing key as off).
DELETE FROM public.app_feature_flags WHERE key = 'ticket_demo';
DELETE FROM public.app_feature_flag_defs WHERE key = 'ticket_demo';
