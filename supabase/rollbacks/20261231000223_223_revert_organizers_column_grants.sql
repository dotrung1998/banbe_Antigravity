BEGIN;

DROP VIEW IF EXISTS public.organizer_payouts;
REVOKE SELECT ON public.organizers FROM authenticated;
GRANT SELECT ON public.organizers TO authenticated;

COMMIT;
