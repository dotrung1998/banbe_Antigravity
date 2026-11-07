-- Revert 215: delegated refunds off for good. Puts mark_refund_sent back exactly as 128 defined it, purge_project_data
-- exactly as 211 did and project_limits as 214 did, drops the refund list, request/approve/decline, the approval-mode setter, dispute grants, the delegate
-- receipt upload policy and the helpers. event_money_audit rows are kept (they follow the booking), and so is its widened
-- action list (rows with the two new action names may exist). The request and dispute-grant tables are dropped: they hold
-- no money state (the claim itself does), and every action on them is in event_money_audit.
DROP POLICY IF EXISTS "refund_proof_delegate_insert" ON storage.objects;
DROP FUNCTION IF EXISTS public.refund_proof_delegate_ok(text);
DROP FUNCTION IF EXISTS public.get_event_refund_view(text);
DROP FUNCTION IF EXISTS public.request_refund_send(uuid, text, text);
DROP FUNCTION IF EXISTS public.approve_refund_send(uuid);
DROP FUNCTION IF EXISTS public.decline_refund_send(uuid, text);
DROP FUNCTION IF EXISTS public.project_set_refund_approval(text, text);
DROP FUNCTION IF EXISTS public.project_extend_dispute_grant(text, uuid, uuid, timestamptz);

CREATE OR REPLACE FUNCTION public.mark_refund_sent(p_claim_id uuid, p_note text DEFAULT '', p_proof_path text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_host boolean;
  v_note text := trim(p_note);
  v_proof text := NULLIF(left(trim(COALESCE(p_proof_path, '')), 400), '');
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  SELECT EXISTS(
    SELECT 1 FROM organizers o
    WHERE o.id = v_event.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) INTO v_is_host;
  IF NOT v_is_host THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- The proof object must live under this claim's own folder (the storage
  -- policy enforces the same on upload).
  IF v_proof IS NOT NULL AND split_part(v_proof, '/', 1) <> p_claim_id::text THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_PROOF_PATH');
  END IF;

  IF v_claim.status = 'host_marked_sent' THEN
    RETURN jsonb_build_object('success', true, 'status', v_claim.status, 'already', true, 'claim', to_jsonb(v_claim));
  END IF;
  IF v_claim.status NOT IN ('owed', 'disputed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;
  IF v_claim.amount_vnd IS NULL OR v_claim.amount_vnd <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_AMOUNT');
  END IF;

  -- Never allow this transition without a real, persisted recipient
  -- snapshot — a bare selected_destination_id with no valid snapshot
  -- content is treated the same as having none at all.
  IF v_claim.selected_destination_id IS NULL OR NOT goc_refund_snapshot_valid(v_claim.recipient_snapshot) THEN
    RETURN jsonb_build_object('success', false, 'error', 'REFUND_DESTINATION_REQUIRED');
  END IF;

  UPDATE refund_claims
  SET status = 'host_marked_sent',
      host_marked_at = now(),
      proof_path = COALESCE(v_proof, proof_path),
      note = CASE WHEN v_note <> ''
                  THEN COALESCE(note || E'\n', '') || 'Host note: ' || v_note
                  ELSE note END
  WHERE id = p_claim_id
  RETURNING * INTO v_claim;

  IF v_booking.user_id IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_booking.user_id, 'refund_marked_sent',
      'Người tổ chức đã báo hoàn tiền',
      COALESCE(v_event.name, 'Sự kiện') || ' báo đã hoàn '
        || replace(to_char(v_claim.amount_vnd, 'FM999G999G999'), ',', '.') || '₫ cho bạn.',
      jsonb_build_object('claim_id', v_claim.id, 'booking_id', v_booking.id, 'event_id', v_event.id, 'amount_vnd', v_claim.amount_vnd, 'has_proof', v_claim.proof_path IS NOT NULL)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'host_marked_sent', 'claim', to_jsonb(v_claim));
END;
$$;
REVOKE EXECUTE ON FUNCTION public.mark_refund_sent(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_refund_sent(uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.purge_project_data(p_now timestamptz DEFAULT now())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_cut timestamptz := p_now - make_interval(days => public.project_limit('trashDays'));
  v_tasks int; v_posts int; v_ros int; v_lanes int; v_invites int; v_attempts int; v_digest int; v_projects int;
BEGIN
  -- Whole projects first (everything below cascades with them).
  DELETE FROM event_projects p
   WHERE public.project_event_end(p.event_id) + make_interval(days => public.project_limit('purgeDays')) <= p_now;
  GET DIAGNOSTICS v_projects = ROW_COUNT;

  DELETE FROM event_project_tasks WHERE deleted_at IS NOT NULL AND deleted_at <= v_cut;
  GET DIAGNOSTICS v_tasks = ROW_COUNT;
  DELETE FROM event_project_posts WHERE deleted_at IS NOT NULL AND deleted_at <= v_cut;
  GET DIAGNOSTICS v_posts = ROW_COUNT;
  DELETE FROM event_project_ros_items WHERE deleted_at IS NOT NULL AND deleted_at <= v_cut;
  GET DIAGNOSTICS v_ros = ROW_COUNT;
  DELETE FROM event_project_lanes WHERE archived_at IS NOT NULL AND archived_at <= v_cut;
  GET DIAGNOSTICS v_lanes = ROW_COUNT;

  DELETE FROM event_project_invites
   WHERE expires_at <= p_now - interval '1 day' OR (revoked_at IS NOT NULL AND revoked_at <= p_now - interval '1 day');
  GET DIAGNOSTICS v_invites = ROW_COUNT;
  DELETE FROM event_project_invite_attempts WHERE at <= p_now - interval '1 day';
  GET DIAGNOSTICS v_attempts = ROW_COUNT;
  DELETE FROM event_project_digest_log WHERE local_day <= (p_now - interval '14 days')::date;
  GET DIAGNOSTICS v_digest = ROW_COUNT;

  RETURN jsonb_build_object('projects', v_projects, 'tasks', v_tasks, 'posts', v_posts, 'ros', v_ros, 'lanes', v_lanes,
                            'invites', v_invites, 'attempts', v_attempts, 'digest_log', v_digest);
END;
$$;
REVOKE ALL ON FUNCTION public.purge_project_data(timestamptz) FROM PUBLIC, anon, authenticated;

-- 214's limits, verbatim.
-- proofOpenMinutes joins the limits (= src/data/projectLimits.json).
CREATE OR REPLACE FUNCTION public.project_limits()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'lanesMax', 10, 'laneNameMax', 24, 'changeWhyMax', 140, 'reasonMin', 3, 'reasonMax', 140,
    'taskTitleMin', 3, 'taskTitleMax', 60, 'postTitleMin', 3, 'postTitleMax', 80, 'postBodyMax', 280,
    'replyMax', 140, 'repliesMax', 10, 'proposalOptionsMin', 2, 'proposalOptionsMax', 4, 'proposalOptionMax', 40,
    'rosTitleMin', 2, 'rosTitleMax', 40, 'rosMinMinutes', 10, 'rosWindowBeforeStartHours', 12, 'rosWindowAfterStartHours', 24,
    'trashMax', 30, 'trashDays', 7, 'channelsMax', 5, 'channelLabelMax', 30, 'channelUrlMax', 300,
    'inviteHours', 48, 'inviteMaxUses', 20, 'grantDays', 7, 'readOnlyDays', 30, 'purgeDays', 90, 'digestHour', 18,
    'proofOpenMinutes', 5);
$$;
REVOKE ALL ON FUNCTION public.project_limits() FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public.refund_claim_organizer_ok(uuid);
DROP FUNCTION IF EXISTS public.project_refund_delegate_ok(uuid);
DROP FUNCTION IF EXISTS public.project_refund_member_ok(text);
DROP FUNCTION IF EXISTS public.project_refund_mode(text);
DROP FUNCTION IF EXISTS public.refund_claim_event(uuid);
DROP TABLE IF EXISTS public.event_dispute_refund_grants;
DROP TABLE IF EXISTS public.event_refund_send_requests;
DO $$ BEGIN
  IF to_regclass('public.event_projects') IS NOT NULL THEN
    ALTER TABLE public.event_projects DROP COLUMN IF EXISTS grants_expired_notified_at;
  END IF;
END $$;
DELETE FROM public.notification_kind_policy WHERE kind IN ('project_refund_request', 'project_refund_declined', 'project_grants_expired');
UPDATE public.app_feature_flag_defs SET description = 'Event Project Hub: team members with money access may handle refunds (needs 214)'
 WHERE key = 'project_delegate_refunds';
