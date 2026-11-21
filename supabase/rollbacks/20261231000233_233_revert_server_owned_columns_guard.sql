-- Rollback for 233. Restores the pre-audit direct-write surface exactly:
-- table-wide UPDATE on messages, no client-write guards on profiles/organizers.

BEGIN;

DROP TRIGGER IF EXISTS messages_guard_client_insert ON public.messages;
DROP FUNCTION IF EXISTS public.messages_guard_client_insert();
REVOKE UPDATE ON public.messages FROM authenticated;
GRANT UPDATE ON public.messages TO anon, authenticated;

DROP TRIGGER IF EXISTS organizers_guard_client_write ON public.organizers;
DROP FUNCTION IF EXISTS public.organizers_guard_client_write();

DROP TRIGGER IF EXISTS profiles_guard_client_write ON public.profiles;
DROP FUNCTION IF EXISTS public.profiles_guard_client_write();

COMMIT;
