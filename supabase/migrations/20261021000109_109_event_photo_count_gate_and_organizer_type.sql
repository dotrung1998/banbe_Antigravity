-- Migration 109 — two additive, unrelated fixes bundled into one pass
-- (event-creation validation ticket): the 3-8 photo invariant in the
-- trusted write path, and a real (self-declared) individual/business
-- distinction for organizers, since neither existed before this.

-- ============================================================
-- 1. Photo-count invariant, enforced server-side.
-- ============================================================
-- create_event_draft/resubmit_event_for_review (migration 107) already set
-- status='review' the moment the event row itself is created — photos are
-- attached AFTERWARDS, client-side, in a separate per-file upload+insert
-- step (reconcileEventMedia) that isn't (and structurally can't be, since
-- storage upload can't happen inside a SQL function) part of that same
-- RPC's transaction. So "3-8 photos" can't be a gate INSIDE
-- create_event_draft itself — there's nothing to count yet when it runs.
--
-- Instead, this is a new RPC the client calls once photo reconciliation
-- finishes (the actual last step of submission): if the real, persisted
-- event_photos count for that event isn't within [3, 8], it withdraws the
-- event back to 'draft' with rejection_reason explaining why — reusing the
-- EXACT SAME 'review' -> 'draft' transition (and event_status_history
-- audit row) migration 107's own withdraw_event_submission already
-- established, rather than inventing a new status or a parallel mechanism.
-- A withdrawn-for-photo-count event surfaces exactly where every other
-- rejected/withdrawn event does — Dashboard's own "needs fix, resubmit"
-- section — so the host's existing "Sửa & gửi lại" flow (resubmit_event_
-- for_review) is the same, real path back to review once they fix it.
CREATE OR REPLACE FUNCTION public.finalize_event_photo_count(p_event_id text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_event events%ROWTYPE;
  v_count int;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM organizers o
    WHERE o.id = v_event.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- Only ever a gate on an event still actually pending review — calling
  -- this again on an already-decided event (live/cancelled/ended, or a
  -- draft already withdrawn for some other reason) is a harmless no-op,
  -- never a second, conflicting transition.
  IF v_event.status <> 'review' THEN
    RETURN jsonb_build_object('success', true, 'status', v_event.status, 'skipped', true);
  END IF;

  SELECT count(*) INTO v_count FROM event_photos WHERE event_id = p_event_id;

  IF v_count < 3 OR v_count > 8 THEN
    UPDATE events SET
      status = 'draft', reviewed_at = NULL, reviewed_by = NULL,
      rejection_reason = 'PHOTO_COUNT_INVALID: needs 3-8 photos, has ' || v_count
    WHERE id = p_event_id;
    INSERT INTO event_status_history(event_id, action, from_status, to_status, reason, actor_id)
    VALUES (p_event_id, 'auto_withdraw_photo_count', 'review', 'draft', 'PHOTO_COUNT_INVALID', auth.uid());
    RETURN jsonb_build_object('success', false, 'error', 'PHOTO_COUNT_INVALID', 'count', v_count);
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'review', 'count', v_count);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.finalize_event_photo_count(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.finalize_event_photo_count(text) TO authenticated;

-- ============================================================
-- 2. Organizer individual-vs-business — self-declared, additive.
-- ============================================================
-- Nothing in the schema distinguished this before. `verified` (migration
-- 001) is a dead column — never written by any migration's RPCs, so it
-- cannot honestly stand in for "verified business registration." `tax_code`
-- (migration 024) is free text with no format/registry check. Neither is
-- fabricated into meaning something it doesn't: this adds a genuinely new,
-- explicitly self-declared field, and admin review (see AdminEvents) must
-- keep showing it as self-declared, never as "verified," since no real
-- registry check exists anywhere in this system.
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS organizer_type text NOT NULL DEFAULT 'individual';
DO $$ BEGIN
  ALTER TABLE organizers ADD CONSTRAINT organizers_organizer_type_check CHECK (organizer_type IN ('individual', 'business'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.set_organizer_type(p_organizer text, p_organizer_type text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF p_organizer_type NOT IN ('individual', 'business') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_ORGANIZER_TYPE');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM organizers o
    WHERE o.id = p_organizer AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  UPDATE organizers SET organizer_type = p_organizer_type WHERE id = p_organizer;
  RETURN jsonb_build_object('success', true, 'organizer_type', p_organizer_type);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_organizer_type(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_organizer_type(text, text) TO authenticated;
