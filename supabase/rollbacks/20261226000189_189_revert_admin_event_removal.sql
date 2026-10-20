-- Full rollback of migration 189 (note 54). Kept OUT of migrations/. The 'removed' enum value from 188 can't be
-- dropped in Postgres; it stays, unused. Removed events go back to the status they had before removal.
-- cancel_event goes back to migration 150's body (re-apply 20261130000150_*.sql after this).

-- 1. Put removed events back (the guard is still present here, so allow it first).
SELECT set_config('app.event_removal_allowed', '1', true);
UPDATE public.events
SET status = coalesce(removed_from_status, 'draft'), removed_from_status = NULL, removed_at = NULL, removed_by = NULL,
    removal_reason = ''
WHERE status = 'removed';

-- 2. Triggers and functions.
DROP TRIGGER IF EXISTS events_guard_removal ON public.events;
DROP TRIGGER IF EXISTS events_guard_removal_insert ON public.events;
DROP FUNCTION IF EXISTS public.events_guard_removal();
DROP FUNCTION IF EXISTS public.events_guard_removal_insert();
DROP FUNCTION IF EXISTS public.admin_event_removal_check(text[]);
DROP FUNCTION IF EXISTS public.admin_remove_events(text[], text);
DROP FUNCTION IF EXISTS public.admin_restore_events(text[]);
DROP FUNCTION IF EXISTS public.admin_purge_events(text[], text);
DROP FUNCTION IF EXISTS public.event_removal_blockers(text);

-- 3. Testing wipe + its switch (same as 189b).
\ir 20261226000189_189b_drop_testing_event_wipe.sql

-- 4. Columns (history rows written with the new actions are deleted so the old CHECK can come back).
ALTER TABLE public.events DROP COLUMN IF EXISTS removed_at;
ALTER TABLE public.events DROP COLUMN IF EXISTS removed_by;
ALTER TABLE public.events DROP COLUMN IF EXISTS removal_reason;
ALTER TABLE public.events DROP COLUMN IF EXISTS removed_from_status;
DELETE FROM public.event_status_history WHERE action IN ('cancel', 'admin_remove', 'admin_restore');
ALTER TABLE public.event_status_history DROP CONSTRAINT IF EXISTS event_status_history_action_check;
ALTER TABLE public.event_status_history ADD CONSTRAINT event_status_history_action_check CHECK (action IN (
  'submit', 'approve', 'reject', 'withdraw', 'resubmit', 'auto_withdraw_photo_count'));
DROP INDEX IF EXISTS public.admin_action_log_event_idx;
ALTER TABLE public.admin_action_log DROP COLUMN IF EXISTS target_event_id;
ALTER TABLE public.admin_action_log DROP COLUMN IF EXISTS meta;

-- 5. Notification text rows.
DELETE FROM public.notification_i18n_titles WHERE vi IN ('Sự kiện đã bị gỡ', 'Sự kiện đã được khôi phục');
DELETE FROM public.notification_i18n_body_rules WHERE pos IN (52, 53);
