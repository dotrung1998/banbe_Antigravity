BEGIN;

DROP TRIGGER IF EXISTS events_guard_client_write ON public.events;
DROP FUNCTION IF EXISTS public.events_guard_client_write();

COMMIT;
