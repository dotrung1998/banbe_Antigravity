BEGIN;

DROP TRIGGER IF EXISTS bookings_guard_event_over ON public.bookings;
DROP FUNCTION IF EXISTS public.bookings_guard_event_over();
DROP FUNCTION IF EXISTS public.event_ends_at(timestamptz, time, boolean, text);

COMMIT;
