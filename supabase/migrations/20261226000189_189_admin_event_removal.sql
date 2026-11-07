-- Migration 189: admins can remove (hide), restore and permanently purge events, one or many at a time; plus a
-- TESTING-PHASE-ONLY wipe for iOS. Note: .claude/notes/54-admin-event-removal.md.
--
-- Why soft removal, never a plain DELETE (audited 2026-10-20): every FK to events is ON DELETE CASCADE apart from three,
-- so deleting an event that ever had bookings silently destroys bookings, payment_documents (12-month retention,
-- User Policy B7), the append-only payment_audit_log, refund_claims, refund_batch_items, dispute threads and
-- transcripts, check-ins and per-attendee tickets, and orphans every Storage object. A plain DELETE also FAILS for any
-- event ever shared as a story (stories.event_id ON DELETE SET NULL is an UPDATE that stories_edit_guard rejects).
--
-- PUBLIC VERSION (stays after launch), web + iOS:
--   admin_event_removal_check(ids)   per event: active bookings / unsettled refunds / open disputes / bookings ever,
--                                    and whether it can be removed and purged. Read-only.
--   admin_remove_events(ids, reason) status -> 'removed' (hidden everywhere, records kept), reason REQUIRED, host
--                                    notified. Refused per event while money is still in play (owner decision
--                                    2026-10-20: "block until the host refunds"): seat-holding bookings on an event
--                                    that hasn't ended, refund claims not settled (owed / host_marked_sent /
--                                    disputed), or an unresolved payment/refund dispute. The host must cancel and
--                                    refund first.
--   admin_restore_events(ids)        back to the status it had (live past its end time comes back as ended).
--   admin_purge_events(ids, reason)  PERMANENT, only for events that are already removed AND never had a single
--                                    booking (so nothing financial can exist). Deletes its event_share stories first.
--                                    Logged in admin_action_log, which survives the delete.
--
-- TESTING PHASE ONLY (remove before public release; iOS UI only):
--   admin_wipe_events_testing(ids)   PERMANENTLY erases ANY event and everything tied to it (bookings, payments,
--                                    refunds, disputes, chats, check-ins, stories), no reason. Works only while the
--                                    feature flag 'admin_event_wipe' is ON. Seeded OFF; a missing row also counts as
--                                    OFF here (unlike the client rule "missing = on"). Storage files are NOT deleted.
--   To remove: apply supabase/rollbacks/20261226000189_189b_drop_testing_event_wipe.sql and delete the iOS code marked
--   TESTING-PHASE.
--
-- Also fixed here:
--   * events_guard_removal: nobody can move an event into or out of 'removed', or touch the removal columns, except
--     these RPCs (owners can UPDATE their events directly under events_update_own, so a host could otherwise undo a
--     removal from the client).
--   * event_status_history.action CHECK never allowed 109's 'auto_withdraw_photo_count', so that auto-withdraw path
--     failed with a check violation. Widened, together with the new admin actions and 'cancel'.
--   * cancel_event(): refuses an event that is already cancelled (re-cancelling overwrote cancelled_at, which
--     get_event_ticket_holders matches bookings on) or removed; locks the row; records a history row; says "banbe"
--     instead of "host" when an admin who isn't the host cancels.
--
-- Requires 187 (app_feature_flags) and 188 (the 'removed' value).
-- Rollback: supabase/rollbacks/20261226000189_189_revert_admin_event_removal.sql (kept OUT of migrations/).

-- ---------------------------------------------------------------------------------------------------------------
-- 1. Removal bookkeeping on events, and an event column on the admin log (rows must outlive a purged event).
-- ---------------------------------------------------------------------------------------------------------------
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS removed_at timestamptz;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS removed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS removal_reason text NOT NULL DEFAULT '';
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS removed_from_status event_status;

ALTER TABLE public.admin_action_log ADD COLUMN IF NOT EXISTS target_event_id text;  -- no FK on purpose
ALTER TABLE public.admin_action_log ADD COLUMN IF NOT EXISTS meta jsonb NOT NULL DEFAULT '{}'::jsonb;
CREATE INDEX IF NOT EXISTS admin_action_log_event_idx ON public.admin_action_log (target_event_id, created_at DESC)
  WHERE target_event_id IS NOT NULL;

-- ---------------------------------------------------------------------------------------------------------------
-- 2. event_status_history: allow 109's auto-withdraw (latent bug) and the new actions.
-- ---------------------------------------------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT conname FROM pg_constraint
           WHERE conrelid = 'public.event_status_history'::regclass AND contype = 'c'
             AND pg_get_constraintdef(oid) ILIKE '%action%'
  LOOP
    EXECUTE format('ALTER TABLE public.event_status_history DROP CONSTRAINT %I', r.conname);
  END LOOP;
END $$;
ALTER TABLE public.event_status_history ADD CONSTRAINT event_status_history_action_check CHECK (action IN (
  'submit', 'approve', 'reject', 'withdraw', 'resubmit', 'auto_withdraw_photo_count',
  'cancel', 'admin_remove', 'admin_restore'
));

-- ---------------------------------------------------------------------------------------------------------------
-- 3. Only the removal RPCs may move an event into/out of 'removed' or touch the removal columns.
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.events_guard_removal()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF coalesce(current_setting('app.event_removal_allowed', true), '') = '1' THEN
    RETURN NEW;
  END IF;
  IF (OLD.status = 'removed' OR NEW.status = 'removed') AND OLD.status IS DISTINCT FROM NEW.status THEN
    RAISE EXCEPTION 'EVENT_REMOVAL_LOCKED' USING HINT = 'Only an admin can remove or restore an event.';
  END IF;
  IF NEW.removed_at IS DISTINCT FROM OLD.removed_at OR NEW.removed_by IS DISTINCT FROM OLD.removed_by
     OR NEW.removal_reason IS DISTINCT FROM OLD.removal_reason
     OR NEW.removed_from_status IS DISTINCT FROM OLD.removed_from_status THEN
    RAISE EXCEPTION 'EVENT_REMOVAL_LOCKED' USING HINT = 'Only an admin can remove or restore an event.';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS events_guard_removal ON public.events;
CREATE TRIGGER events_guard_removal BEFORE UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.events_guard_removal();
-- A brand-new event can't start out removed either.
CREATE OR REPLACE FUNCTION public.events_guard_removal_insert()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.status = 'removed' OR NEW.removed_at IS NOT NULL THEN
    RAISE EXCEPTION 'EVENT_REMOVAL_LOCKED';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS events_guard_removal_insert ON public.events;
CREATE TRIGGER events_guard_removal_insert BEFORE INSERT ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.events_guard_removal_insert();

-- ---------------------------------------------------------------------------------------------------------------
-- 4. What still ties an event to money or an open conversation. Internal (no grant); used by the RPCs below.
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.event_removal_blockers(p_event_id text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    -- Seat-holding reservations on an event that hasn't happened yet (an ended event's confirmed bookings are
    -- history, not obligations).
    'active_bookings', (
      SELECT count(*) FROM bookings b JOIN events e ON e.id = b.event_id
      WHERE b.event_id = p_event_id
        AND b.status IN ('pending', 'confirmed')
        AND public.booking_holds_seat(b.payment_state, b.hold_expires_at, b.status)
        AND e.status NOT IN ('ended')
        AND (e.starts_at IS NULL OR e.starts_at > now() - interval '12 hours')),
    'unsettled_refunds', (
      SELECT count(*) FROM refund_claims rc JOIN bookings b ON b.id = rc.booking_id
      WHERE b.event_id = p_event_id AND rc.status IN ('owed', 'host_marked_sent', 'disputed')),
    'open_disputes', (
      SELECT count(*) FROM dispute_threads dt WHERE dt.event_id = p_event_id AND dt.resolved_at IS NULL),
    'bookings_ever', (SELECT count(*) FROM bookings b WHERE b.event_id = p_event_id)
  );
$$;
REVOKE ALL ON FUNCTION public.event_removal_blockers(text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- 5. admin_event_removal_check(ids): the blockers for each event, so the apps can say why before anyone acts.
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_event_removal_check(p_event_ids text[])
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_out jsonb := '[]'::jsonb;
  v_ev events%ROWTYPE;
  v_b jsonb;
  v_id text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_event_ids IS NULL OR cardinality(p_event_ids) = 0 OR cardinality(p_event_ids) > 200 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  FOREACH v_id IN ARRAY p_event_ids LOOP
    SELECT * INTO v_ev FROM events WHERE id = v_id;
    IF NOT FOUND THEN
      v_out := v_out || jsonb_build_object('event_id', v_id, 'found', false);
      CONTINUE;
    END IF;
    v_b := public.event_removal_blockers(v_id);
    v_out := v_out || (v_b || jsonb_build_object(
      'event_id', v_id, 'found', true, 'status', v_ev.status,
      'removable', v_ev.status <> 'removed' AND (v_b->>'active_bookings')::int = 0
                   AND (v_b->>'unsettled_refunds')::int = 0 AND (v_b->>'open_disputes')::int = 0,
      'purgeable', v_ev.status = 'removed' AND (v_b->>'bookings_ever')::int = 0));
  END LOOP;
  RETURN jsonb_build_object('success', true, 'events', v_out);
END;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- 6. admin_remove_events(ids, reason): hide; records kept; host told. Per-event results, never all-or-nothing.
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_remove_events(p_event_ids text[], p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
  v_reason text := left(trim(coalesce(p_reason, '')), 500);
  v_results jsonb := '[]'::jsonb;
  v_removed int := 0;
  v_ev events%ROWTYPE;
  v_b jsonb;
  v_owner uuid;
  v_id text;
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_event_ids IS NULL OR cardinality(p_event_ids) = 0 OR cardinality(p_event_ids) > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  IF length(v_reason) < 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'REASON_REQUIRED');
  END IF;

  FOREACH v_id IN ARRAY (SELECT array_agg(DISTINCT x) FROM unnest(p_event_ids) x) LOOP
    SELECT * INTO v_ev FROM events WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN
      v_results := v_results || jsonb_build_object('event_id', v_id, 'ok', false, 'error', 'NOT_FOUND');
      CONTINUE;
    END IF;
    IF v_ev.status = 'removed' THEN
      v_results := v_results || jsonb_build_object('event_id', v_id, 'ok', false, 'error', 'ALREADY_REMOVED');
      CONTINUE;
    END IF;
    v_b := public.event_removal_blockers(v_id);
    IF (v_b->>'active_bookings')::int > 0 OR (v_b->>'unsettled_refunds')::int > 0 OR (v_b->>'open_disputes')::int > 0 THEN
      v_results := v_results || (v_b || jsonb_build_object('event_id', v_id, 'ok', false, 'error', 'HAS_OPEN_OBLIGATIONS'));
      CONTINUE;
    END IF;

    PERFORM set_config('app.event_removal_allowed', '1', true);
    UPDATE events SET status = 'removed', removed_from_status = v_ev.status, removed_at = now(),
                      removed_by = v_admin, removal_reason = v_reason
    WHERE id = v_id;
    PERFORM set_config('app.event_removal_allowed', '', true);

    INSERT INTO event_status_history (event_id, action, from_status, to_status, reason, actor_id)
    VALUES (v_id, 'admin_remove', v_ev.status, 'removed', v_reason, v_admin);
    INSERT INTO admin_action_log (actor_id, action, target_event_id, meta)
    VALUES (v_admin, 'event_removed', v_id, jsonb_build_object('reason', v_reason, 'from_status', v_ev.status, 'name', v_ev.name));

    SELECT coalesce(o.owner_id, o.user_id) INTO v_owner FROM organizers o WHERE o.id = v_ev.organizer_id;
    IF v_owner IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (v_owner, 'event_removed', 'Sự kiện đã bị gỡ',
              'Sự kiện "' || coalesce(v_ev.name, '') || '" đã bị banbe gỡ khỏi ứng dụng. Lý do: ' || v_reason,
              jsonb_build_object('event_id', v_id, 'reason', v_reason));
    END IF;

    v_removed := v_removed + 1;
    v_results := v_results || jsonb_build_object('event_id', v_id, 'ok', true);
  END LOOP;

  RETURN jsonb_build_object('success', true, 'removed', v_removed, 'results', v_results);
END;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- 7. admin_restore_events(ids): undo a removal.
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_restore_events(p_event_ids text[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
  v_results jsonb := '[]'::jsonb;
  v_restored int := 0;
  v_ev events%ROWTYPE;
  v_to event_status;
  v_owner uuid;
  v_id text;
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_event_ids IS NULL OR cardinality(p_event_ids) = 0 OR cardinality(p_event_ids) > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;

  FOREACH v_id IN ARRAY (SELECT array_agg(DISTINCT x) FROM unnest(p_event_ids) x) LOOP
    SELECT * INTO v_ev FROM events WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN
      v_results := v_results || jsonb_build_object('event_id', v_id, 'ok', false, 'error', 'NOT_FOUND');
      CONTINUE;
    END IF;
    IF v_ev.status <> 'removed' THEN
      v_results := v_results || jsonb_build_object('event_id', v_id, 'ok', false, 'error', 'NOT_REMOVED');
      CONTINUE;
    END IF;
    v_to := coalesce(v_ev.removed_from_status, 'draft');
    -- A live event whose time has passed while it was hidden comes back as ended (same 12h rule as migration 167).
    IF v_to = 'live' AND v_ev.starts_at IS NOT NULL AND v_ev.starts_at < now() - interval '12 hours' THEN
      v_to := 'ended';
    END IF;

    PERFORM set_config('app.event_removal_allowed', '1', true);
    UPDATE events SET status = v_to, removed_from_status = NULL, removed_at = NULL, removed_by = NULL, removal_reason = ''
    WHERE id = v_id;
    PERFORM set_config('app.event_removal_allowed', '', true);

    INSERT INTO event_status_history (event_id, action, from_status, to_status, reason, actor_id)
    VALUES (v_id, 'admin_restore', 'removed', v_to, '', v_admin);
    INSERT INTO admin_action_log (actor_id, action, target_event_id, meta)
    VALUES (v_admin, 'event_restored', v_id, jsonb_build_object('to_status', v_to, 'name', v_ev.name));

    SELECT coalesce(o.owner_id, o.user_id) INTO v_owner FROM organizers o WHERE o.id = v_ev.organizer_id;
    IF v_owner IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (v_owner, 'event_restored', 'Sự kiện đã được khôi phục',
              'Sự kiện "' || coalesce(v_ev.name, '') || '" đã được banbe khôi phục.',
              jsonb_build_object('event_id', v_id));
    END IF;

    v_restored := v_restored + 1;
    v_results := v_results || jsonb_build_object('event_id', v_id, 'ok', true, 'status', v_to);
  END LOOP;

  RETURN jsonb_build_object('success', true, 'restored', v_restored, 'results', v_results);
END;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- 8. admin_purge_events(ids, reason): PERMANENT, only removed events that never had a booking.
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_purge_events(p_event_ids text[], p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
  v_reason text := left(trim(coalesce(p_reason, '')), 500);
  v_results jsonb := '[]'::jsonb;
  v_purged int := 0;
  v_ev events%ROWTYPE;
  v_stories int;
  v_id text;
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_event_ids IS NULL OR cardinality(p_event_ids) = 0 OR cardinality(p_event_ids) > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  IF length(v_reason) < 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'REASON_REQUIRED');
  END IF;

  FOREACH v_id IN ARRAY (SELECT array_agg(DISTINCT x) FROM unnest(p_event_ids) x) LOOP
    SELECT * INTO v_ev FROM events WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN
      v_results := v_results || jsonb_build_object('event_id', v_id, 'ok', false, 'error', 'NOT_FOUND');
      CONTINUE;
    END IF;
    IF v_ev.status <> 'removed' THEN
      v_results := v_results || jsonb_build_object('event_id', v_id, 'ok', false, 'error', 'NOT_REMOVED');
      CONTINUE;
    END IF;
    IF EXISTS (SELECT 1 FROM bookings WHERE event_id = v_id) THEN
      v_results := v_results || jsonb_build_object('event_id', v_id, 'ok', false, 'error', 'HAS_BOOKING_HISTORY');
      CONTINUE;
    END IF;

    -- Shares of this event in stories would block the delete (stories_edit_guard) and point at nothing afterwards.
    DELETE FROM stories WHERE event_id = v_id;
    GET DIAGNOSTICS v_stories = ROW_COUNT;
    INSERT INTO admin_action_log (actor_id, action, target_event_id, meta)
    VALUES (v_admin, 'event_purged', v_id, jsonb_build_object(
      'reason', v_reason, 'name', v_ev.name, 'organizer_id', v_ev.organizer_id,
      'removal_reason', v_ev.removal_reason, 'removed_from_status', v_ev.removed_from_status,
      'stories_deleted', v_stories));
    DELETE FROM events WHERE id = v_id;

    v_purged := v_purged + 1;
    v_results := v_results || jsonb_build_object('event_id', v_id, 'ok', true);
  END LOOP;

  RETURN jsonb_build_object('success', true, 'purged', v_purged, 'results', v_results);
END;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- 9. TESTING PHASE ONLY: feature flag + admin_wipe_events_testing. Remove before public release (see header).
-- ---------------------------------------------------------------------------------------------------------------
ALTER TABLE public.app_feature_flags DROP CONSTRAINT IF EXISTS app_feature_flags_key_known;
ALTER TABLE public.app_feature_flags ADD CONSTRAINT app_feature_flags_key_known
  CHECK (key IN ('rewards', 'admin_event_wipe'));
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('admin_event_wipe', false)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_set_feature_flag(p_key text, p_enabled boolean)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF p_enabled IS NULL OR p_key IS NULL OR p_key NOT IN ('rewards', 'admin_event_wipe') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  INSERT INTO public.app_feature_flags (key, enabled, updated_by, updated_at)
  VALUES (p_key, p_enabled, v_admin, now())
  ON CONFLICT (key) DO UPDATE SET enabled = excluded.enabled, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  INSERT INTO public.app_feature_flags_audit (admin_id, key, enabled) VALUES (v_admin, p_key, p_enabled);
  RETURN jsonb_build_object('success', true, 'key', p_key, 'enabled', p_enabled);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_wipe_events_testing(p_event_ids text[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
  v_results jsonb := '[]'::jsonb;
  v_wiped int := 0;
  v_ev events%ROWTYPE;
  v_bookings int;
  v_stories int;
  v_id text;
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  -- Missing row = OFF for this one (a testing tool must never switch itself on).
  IF NOT coalesce((SELECT enabled FROM app_feature_flags WHERE key = 'admin_event_wipe'), false) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_ENABLED');
  END IF;
  IF p_event_ids IS NULL OR cardinality(p_event_ids) = 0 OR cardinality(p_event_ids) > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;

  FOREACH v_id IN ARRAY (SELECT array_agg(DISTINCT x) FROM unnest(p_event_ids) x) LOOP
    SELECT * INTO v_ev FROM events WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN
      v_results := v_results || jsonb_build_object('event_id', v_id, 'ok', false, 'error', 'NOT_FOUND');
      CONTINUE;
    END IF;
    SELECT count(*) INTO v_bookings FROM bookings WHERE event_id = v_id;
    DELETE FROM stories WHERE event_id = v_id;
    GET DIAGNOSTICS v_stories = ROW_COUNT;
    INSERT INTO admin_action_log (actor_id, action, target_event_id, meta)
    VALUES (v_admin, 'event_wiped_testing', v_id, jsonb_build_object(
      'name', v_ev.name, 'status', v_ev.status, 'organizer_id', v_ev.organizer_id,
      'bookings_deleted', v_bookings, 'stories_deleted', v_stories));
    DELETE FROM events WHERE id = v_id;  -- cascades to bookings and everything under them (see header)

    v_wiped := v_wiped + 1;
    v_results := v_results || jsonb_build_object('event_id', v_id, 'ok', true, 'bookings_deleted', v_bookings);
  END LOOP;

  RETURN jsonb_build_object('success', true, 'wiped', v_wiped, 'results', v_results);
END;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- 10. cancel_event(): status guard, row lock, history row, honest actor wording. Body otherwise = migration 150.
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cancel_event(p_event text, p_reason text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev events%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_thread_id uuid;
  v_count int := 0;
  v_had_payment boolean;
  v_clean_reason text := left(trim(COALESCE(p_reason, '')), 400);
  v_is_host boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_ev FROM events WHERE id = p_event OR slug = p_event OR key = p_event;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;
  SELECT * INTO v_ev FROM events WHERE id = v_ev.id FOR UPDATE;

  v_is_host := EXISTS (
    SELECT 1 FROM organizers o WHERE o.id = v_ev.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  );
  IF NOT v_is_host AND NOT EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_ev.status = 'cancelled' THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_CANCELLED', 'event_id', v_ev.id);
  END IF;
  IF v_ev.status = 'removed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_REMOVED', 'event_id', v_ev.id);
  END IF;

  UPDATE events
  SET status = 'cancelled',
      cancelled_at = now(),
      cancel_reason = COALESCE(p_reason, '')
  WHERE id = v_ev.id;

  INSERT INTO event_status_history (event_id, action, from_status, to_status, reason, actor_id)
  VALUES (v_ev.id, 'cancel', v_ev.status, 'cancelled', v_clean_reason, auth.uid());

  FOR v_booking IN SELECT * FROM bookings WHERE event_id = v_ev.id AND status IN ('pending', 'confirmed') LOOP
    UPDATE bookings
    SET status = 'cancelled',
        cancelled_at = now(),
        cancelled_by = auth.uid(),
        cancel_reason = COALESCE(p_reason, '')
    WHERE id = v_booking.id;

    v_had_payment := v_booking.status = 'confirmed' OR v_booking.paid_marked_at IS NOT NULL;
    IF v_had_payment THEN
      INSERT INTO refund_claims (booking_id, reservation_id, amount_vnd, reason, status, refund_due_at)
      VALUES (v_booking.id, v_booking.id, v_booking.total_vnd, 'host_cancelled', 'owed',
              goc_add_business_days(now(), 3));
    END IF;

    SELECT id INTO v_thread_id FROM threads WHERE event_id = v_ev.id AND guest_id = v_booking.user_id;
    IF v_thread_id IS NOT NULL THEN
      INSERT INTO messages (thread_id, sender_id, body, kind)
      VALUES (v_thread_id, auth.uid(),
              'Event was cancelled by ' || CASE WHEN v_is_host THEN 'host' ELSE 'banbe' END
              || '. Reason: ' || COALESCE(NULLIF(p_reason, ''), 'Cancelled by organizer') || '.', 'system');
    END IF;

    IF v_booking.user_id IS NOT NULL THEN
      INSERT INTO public.notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_booking.user_id,
        'booking_cancelled',
        'Vé của bạn đã bị huỷ',
        COALESCE(v_ev.name, 'Sự kiện') || ' đã huỷ vé của bạn.'
          || (CASE WHEN v_had_payment THEN ' Khoản bạn đã thanh toán sẽ được hoàn lại.' ELSE '' END)
          || (CASE WHEN v_clean_reason <> '' THEN ' Lý do: ' || v_clean_reason ELSE '' END),
        jsonb_build_object('event_id', v_ev.id, 'booking_id', v_booking.id, 'reason', v_clean_reason, 'had_payment', v_had_payment)
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'event_id', v_ev.id, 'bookings_cancelled', v_count);
END;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- 11. Notification text in the recipient's language (142's tables).
-- ---------------------------------------------------------------------------------------------------------------
INSERT INTO public.notification_i18n_titles (vi, en) VALUES
  ($q$Sự kiện đã bị gỡ$q$, $q$Event removed$q$),
  ($q$Sự kiện đã được khôi phục$q$, $q$Event restored$q$)
ON CONFLICT (vi) DO NOTHING;
INSERT INTO public.notification_i18n_body_rules (pos, vi_pattern, en_replacement) VALUES
  -- " Lý do: " itself is translated by 142's rule 48, which runs first; this rule only covers the sentence before it.
  (52, $q$^Sự kiện \"(.*)\" đã bị banbe gỡ khỏi ứng dụng\.$q$, $q$Your event "\1" was removed from banbe.$q$),
  (53, $q$^Sự kiện \"(.*)\" đã được banbe khôi phục\.$$q$, $q$Your event "\1" was restored by banbe.$q$)
ON CONFLICT (pos) DO NOTHING;

-- ---------------------------------------------------------------------------------------------------------------
-- 12. Grants.
-- ---------------------------------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.admin_event_removal_check(text[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_remove_events(text[], text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_restore_events(text[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_purge_events(text[], text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_wipe_events_testing(text[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_feature_flag(text, boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION cancel_event(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_event_removal_check(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_remove_events(text[], text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_restore_events(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_purge_events(text[], text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_wipe_events_testing(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_feature_flag(text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_event(text, text) TO authenticated;
