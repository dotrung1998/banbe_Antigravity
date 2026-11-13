-- Rollback of migration 220: drops the end-time columns (clients treat missing columns as "not stated").
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_end_one_mode;
ALTER TABLE public.events DROP COLUMN IF EXISTS end_open;
ALTER TABLE public.events DROP COLUMN IF EXISTS end_time;
