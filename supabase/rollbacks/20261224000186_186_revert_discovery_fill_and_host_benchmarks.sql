-- Revert 186. Run by hand only. Drops the host-goal side table (its answers are lost).
BEGIN;
DROP FUNCTION IF EXISTS public.get_event_host_goal(text);
DROP FUNCTION IF EXISTS public.set_event_host_goal(text, text);
DROP TABLE IF EXISTS public.event_host_meta;
DROP FUNCTION IF EXISTS public.get_audience_demand(text);
DROP FUNCTION IF EXISTS public.get_host_benchmarks(text, text);
DROP FUNCTION IF EXISTS public.benchmark_slot(timestamptz);
DROP FUNCTION IF EXISTS public.get_public_event_fill(text[]);
COMMIT;
