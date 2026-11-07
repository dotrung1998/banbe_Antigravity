-- 215 — Event Project Hub: delegated refunds (note 76, phase 9c). Behind switch project_delegate_refunds (seeded OFF).
-- Needs 212 (event_money_audit, project_grant_end) and 214 (project_limits gains disputeGrantMaxDays here).
--
-- Who: an ACTIVE project member who is Finance & door or has cap_money, while event_project_hub and
-- project_delegate_refunds are on, the grant is live and the project is not read-only (project_refund_member_ok). Unlike
-- check-in and payments, a CANCELLED event still counts: cancelling is what creates most refunds. A removed event does not.
-- Past read-only, only a dispute grant (M5, below) can reach one claim.
--
-- How (N1): event_projects.refund_approval decides.
--   * 'host' (default): the delegate records the transfer with request_refund_send (note + optional receipt). The guest
--     is told nothing yet. The Host approves (approve_refund_send, which runs mark_refund_sent as the Host) or declines
--     with a reason (decline_refund_send). A delegate calling mark_refund_sent gets APPROVAL_REQUIRED.
--   * 'finance_alone': the delegate may call mark_refund_sent directly. Only the Host switches the mode
--     (project_set_refund_approval), and every switch is audited.
-- mark_refund_sent (128) keeps every original line; the delegate is only tried when its organizer check fails. The Host's
-- own path is unchanged. resend_refund_transfer_info, the batch runner and every dispute RPC stay Host-only.
--
-- Dispute grants (M5): project_extend_dispute_grant lets the Host give one money delegate refund rights on ONE claim
-- while that claim has an open dispute thread (dispute_threads.resolved_at IS NULL, 138), for up to disputeGrantMaxDays
-- per extension. The grant lives in its own table, so it outlives the project's read-only date and purge. It covers
-- request_refund_send (and mark_refund_sent under 'finance_alone') for that claim only, never dispute chat, check-in,
-- payments or proofs, and it is dead the moment the dispute is resolved.
--
-- What a delegate sees: get_event_refund_view lists the event's open claims with name, amount, due date and the guest's
-- refund account (bank, number, holder: needed to send the money). It never returns refund proofs, payment proofs or
-- invoices. A delegate may upload a transfer receipt under the claim's own refund-proof folder (refund_proof_delegate_insert).
--
-- Audit: one event_money_audit row per action: refund_request, refund_approve, refund_decline, refund_mark_sent,
-- set_refund_approval, extend_dispute_grant. The action list gains the two new names.
--
-- When team money access ends (every money delegate's grant is over), the daily purge_project_data tells the Host once,
-- listing how many refunds are back with them ('project_grants_expired').
--
-- LOCAL HARNESS ONLY until the owner says otherwise. Rollback: supabase/rollbacks/20261231000215_215_revert_delegated_refunds.sql
-- (puts 128's mark_refund_sent and 211's purge_project_data back verbatim).

-- ================================================================== audit action list
ALTER TABLE public.event_money_audit DROP CONSTRAINT IF EXISTS event_money_audit_action_check;
ALTER TABLE public.event_money_audit ADD CONSTRAINT event_money_audit_action_check CHECK (action IN (
  'checkin', 'undo_checkin', 'confirm_payment', 'reject_payment', 'proof_open', 'refund_request', 'refund_approve',
  'refund_mark_sent', 'set_refund_approval', 'extend_grants', 'refund_decline', 'extend_dispute_grant'));

-- ================================================================== tables
-- One row per "I sent this refund, please approve". At most one pending per claim. Kept with the claim, not the project.
CREATE TABLE IF NOT EXISTS public.event_refund_send_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  refund_claim_id uuid NOT NULL REFERENCES public.refund_claims(id) ON DELETE CASCADE,
  requested_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  note text CHECK (note IS NULL OR length(note) <= 280),
  proof_path text CHECK (proof_path IS NULL OR length(proof_path) <= 400),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'declined', 'closed')),
  decided_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  decided_at timestamptz,
  reason text CHECK (reason IS NULL OR length(reason) <= 140),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS event_refund_send_requests_one_pending
  ON public.event_refund_send_requests (refund_claim_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS event_refund_send_requests_event ON public.event_refund_send_requests (event_id, created_at DESC);
ALTER TABLE public.event_refund_send_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.event_refund_send_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.event_refund_send_requests TO service_role;

-- M5: refund rights on one disputed claim for one person, beyond the project's own dates.
CREATE TABLE IF NOT EXISTS public.event_dispute_refund_grants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  refund_claim_id uuid NOT NULL REFERENCES public.refund_claims(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  until timestamptz NOT NULL,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (refund_claim_id, user_id)
);
ALTER TABLE public.event_dispute_refund_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.event_dispute_refund_grants FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.event_dispute_refund_grants TO service_role;

ALTER TABLE public.event_projects ADD COLUMN IF NOT EXISTS grants_expired_notified_at timestamptz;

INSERT INTO public.notification_kind_policy (kind, promotional, note) VALUES
  ('project_refund_request', false, 'Event Project Hub: a team member recorded a refund for the Host to approve (note 76)'),
  ('project_refund_declined', false, 'Event Project Hub: the Host declined my refund record (note 76)'),
  ('project_grants_expired', false, 'Event Project Hub: team money access ended, open refunds are back with the Host (note 76)')
ON CONFLICT (kind) DO NOTHING;

-- disputeGrantMaxDays joins the limits (= src/data/projectLimits.json). Without it the dispute-grant cap would be NULL.
CREATE OR REPLACE FUNCTION public.project_limits()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'lanesMax', 10, 'laneNameMax', 24, 'changeWhyMax', 140, 'reasonMin', 3, 'reasonMax', 140,
    'taskTitleMin', 3, 'taskTitleMax', 60, 'postTitleMin', 3, 'postTitleMax', 80, 'postBodyMax', 280,
    'replyMax', 140, 'repliesMax', 10, 'proposalOptionsMin', 2, 'proposalOptionsMax', 4, 'proposalOptionMax', 40,
    'rosTitleMin', 2, 'rosTitleMax', 40, 'rosMinMinutes', 10, 'rosWindowBeforeStartHours', 12, 'rosWindowAfterStartHours', 24,
    'trashMax', 30, 'trashDays', 7, 'channelsMax', 5, 'channelLabelMax', 30, 'channelUrlMax', 300,
    'inviteHours', 48, 'inviteMaxUses', 20, 'grantDays', 7, 'readOnlyDays', 30, 'purgeDays', 90, 'digestHour', 18,
    'proofOpenMinutes', 5, 'disputeGrantMaxDays', 30);
$$;
REVOKE ALL ON FUNCTION public.project_limits() FROM PUBLIC, anon, authenticated;

-- ================================================================== helpers (server-only)
CREATE OR REPLACE FUNCTION public.refund_claim_event(p_claim_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT b.event_id FROM refund_claims rc JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id) WHERE rc.id = p_claim_id;
$$;

CREATE OR REPLACE FUNCTION public.project_refund_mode(p_event_id text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT coalesce((SELECT refund_approval FROM event_projects WHERE event_id = p_event_id), 'host');
$$;

-- A money delegate on this event with a live grant (no claim needed: the refund list).
CREATE OR REPLACE FUNCTION public.project_refund_member_ok(p_event_id text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m event_project_members%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_event_id IS NULL THEN RETURN false; END IF;
  IF NOT public.app_flag('event_project_hub', false) OR NOT public.app_flag('project_delegate_refunds', false) THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM events e WHERE e.id = p_event_id AND e.status::text = 'removed') THEN RETURN false; END IF;
  SELECT * INTO v_m FROM event_project_members m WHERE m.event_id = p_event_id AND m.user_id = auth.uid() AND m.status = 'active';
  IF NOT FOUND OR NOT (v_m.role = 'finance' OR v_m.cap_money) THEN RETURN false; END IF;
  RETURN now() < public.project_grant_end(p_event_id, v_m) AND now() < public.project_read_only_at(p_event_id);
END;
$$;

-- May the caller act as a refund delegate on this claim: a live member grant, or a dispute grant while the dispute is open.
CREATE OR REPLACE FUNCTION public.project_refund_delegate_ok(p_claim_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_event text := public.refund_claim_event(p_claim_id);
BEGIN
  IF auth.uid() IS NULL OR v_event IS NULL THEN RETURN false; END IF;
  IF public.project_refund_member_ok(v_event) THEN RETURN true; END IF;
  IF NOT public.app_flag('event_project_hub', false) OR NOT public.app_flag('project_delegate_refunds', false) THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM events e WHERE e.id = v_event AND e.status::text = 'removed') THEN RETURN false; END IF;
  -- Removing someone from the team ends their dispute grants too.
  IF EXISTS (SELECT 1 FROM event_project_members m WHERE m.event_id = v_event AND m.user_id = auth.uid() AND m.status <> 'active') THEN RETURN false; END IF;
  RETURN EXISTS (SELECT 1 FROM event_dispute_refund_grants g
                  WHERE g.refund_claim_id = p_claim_id AND g.user_id = auth.uid() AND g.until > now())
     AND EXISTS (SELECT 1 FROM dispute_threads t WHERE t.refund_claim_id = p_claim_id AND t.resolved_at IS NULL);
END;
$$;

-- The organizer accounts of the claim's event: the same line mark_refund_sent has used since 128 (never project_is_host).
CREATE OR REPLACE FUNCTION public.refund_claim_organizer_ok(p_claim_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
                  WHERE e.id = public.refund_claim_event(p_claim_id) AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()));
$$;

-- ================================================================== the refund list
CREATE OR REPLACE FUNCTION public.get_event_refund_view(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_org boolean; v_member boolean; v_claims jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  v_org := EXISTS (SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
                    WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()));
  v_member := public.project_refund_member_ok(p_event_id);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'claim_id', rc.id, 'booking_id', b.id,
      'name', coalesce(nullif(b.recipient_name, ''), nullif(pr.display_name, ''), '—'),
      'amount', rc.amount_vnd, 'status', rc.status, 'refund_due_at', rc.refund_due_at,
      'dispute_open', EXISTS (SELECT 1 FROM dispute_threads t WHERE t.refund_claim_id = rc.id AND t.resolved_at IS NULL),
      'account', CASE WHEN public.goc_refund_snapshot_valid(rc.recipient_snapshot) THEN jsonb_build_object(
          'bank_name', rc.recipient_snapshot->>'bank_name', 'account_number', rc.recipient_snapshot->>'account_number',
          'account_holder_name', rc.recipient_snapshot->>'account_holder_name') END,
      'request', (SELECT jsonb_build_object('id', q.id, 'by', coalesce(nullif(qp.display_name, ''), '—'), 'mine', q.requested_by = auth.uid(),
                                            'note', q.note, 'has_proof', q.proof_path IS NOT NULL, 'at', q.created_at)
                    FROM event_refund_send_requests q LEFT JOIN profiles qp ON qp.id = q.requested_by
                   WHERE q.refund_claim_id = rc.id AND q.status = 'pending'),
      'last_declined', (SELECT jsonb_build_object('reason', q.reason, 'at', q.decided_at)
                          FROM event_refund_send_requests q
                         WHERE q.refund_claim_id = rc.id AND q.status = 'declined' AND q.requested_by = auth.uid()
                         ORDER BY q.decided_at DESC LIMIT 1))
      ORDER BY rc.refund_due_at NULLS LAST, rc.created_at), '[]'::jsonb)
    INTO v_claims
    FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    LEFT JOIN profiles pr ON pr.id = b.user_id
   WHERE b.event_id = p_event_id AND rc.status::text IN ('owed', 'disputed')
     AND (v_org OR v_member OR public.project_refund_delegate_ok(rc.id));
  IF NOT v_org AND NOT v_member AND v_claims = '[]'::jsonb THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  RETURN jsonb_build_object('success', true, 'mode', public.project_refund_mode(p_event_id), 'host', v_org, 'claims', v_claims);
END;
$$;

-- ================================================================== delegate: record a transfer for the Host to approve
CREATE OR REPLACE FUNCTION public.request_refund_send(p_claim_id uuid, p_note text DEFAULT '', p_proof_path text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_event text;
  v_name text;
  v_note text := nullif(left(btrim(coalesce(p_note, '')), 280), '');
  v_proof text := nullif(left(btrim(coalesce(p_proof_path, '')), 400), '');
  v_id uuid;
  v_host uuid;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id FOR UPDATE;
  IF NOT FOUND OR NOT public.project_refund_delegate_ok(p_claim_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  v_event := public.refund_claim_event(p_claim_id);
  IF v_proof IS NOT NULL AND split_part(v_proof, '/', 1) <> p_claim_id::text THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_PROOF_PATH');
  END IF;
  IF v_claim.status::text NOT IN ('owed', 'disputed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;
  IF v_claim.amount_vnd IS NULL OR v_claim.amount_vnd <= 0 THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_AMOUNT'); END IF;
  IF v_claim.selected_destination_id IS NULL OR NOT goc_refund_snapshot_valid(v_claim.recipient_snapshot) THEN
    RETURN jsonb_build_object('success', false, 'error', 'REFUND_DESTINATION_REQUIRED');
  END IF;
  IF EXISTS (SELECT 1 FROM event_refund_send_requests WHERE refund_claim_id = p_claim_id AND status = 'pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_REQUESTED');
  END IF;

  INSERT INTO event_refund_send_requests (event_id, refund_claim_id, requested_by, note, proof_path)
  VALUES (v_event, p_claim_id, auth.uid(), v_note, v_proof) RETURNING id INTO v_id;
  PERFORM public.event_money_audit_add(v_event, COALESCE(v_claim.booking_id, v_claim.reservation_id), p_claim_id, 'refund_request', NULL);
  IF EXISTS (SELECT 1 FROM event_projects WHERE event_id = v_event) THEN
    PERFORM public.project_touch(v_event, 'refund.request', 'refund_claim', p_claim_id::text, jsonb_build_object('request_id', v_id));
  END IF;

  SELECT name INTO v_name FROM events WHERE id = v_event;
  FOREACH v_host IN ARRAY public.project_host_ids(v_event) LOOP
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (v_host, 'project_refund_request', 'Hoàn tiền chờ bạn duyệt',
            coalesce((SELECT nullif(display_name, '') FROM profiles WHERE id = auth.uid()), 'Một thành viên') || ' đã ghi nhận hoàn '
              || replace(to_char(v_claim.amount_vnd, 'FM999G999G999'), ',', '.') || '₫ ở ' || coalesce(v_name, 'sự kiện') || '.',
            jsonb_build_object('screen', 'event_project', 'event_id', v_event, 'tab', 'money', 'claim_id', p_claim_id));
  END LOOP;
  RETURN jsonb_build_object('success', true, 'request_id', v_id, 'status', 'pending');
END;
$$;

-- ================================================================== Host: approve (marks the refund sent) or decline
CREATE OR REPLACE FUNCTION public.approve_refund_send(p_claim_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_q event_refund_send_requests%ROWTYPE; v_res jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  -- The Host's decision does not depend on the delegate's grant: a request made before it expired stays approvable.
  IF NOT public.refund_claim_organizer_ok(p_claim_id) THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  SELECT * INTO v_q FROM event_refund_send_requests WHERE refund_claim_id = p_claim_id AND status = 'pending' FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'NO_REQUEST'); END IF;
  v_res := public.mark_refund_sent(p_claim_id, coalesce(v_q.note, ''), v_q.proof_path);
  IF coalesce((v_res->>'success')::boolean, false) IS NOT TRUE THEN RETURN v_res; END IF;
  UPDATE event_refund_send_requests SET status = 'approved', decided_by = auth.uid(), decided_at = now() WHERE id = v_q.id;
  PERFORM public.event_money_audit_add(v_q.event_id, (SELECT COALESCE(booking_id, reservation_id) FROM refund_claims WHERE id = p_claim_id),
                                       p_claim_id, 'refund_approve', NULL);
  IF EXISTS (SELECT 1 FROM event_projects WHERE event_id = v_q.event_id) THEN
    PERFORM public.project_touch(v_q.event_id, 'refund.approve', 'refund_claim', p_claim_id::text, jsonb_build_object('request_id', v_q.id));
  END IF;
  RETURN v_res || jsonb_build_object('request_id', v_q.id);
END;
$$;

CREATE OR REPLACE FUNCTION public.decline_refund_send(p_claim_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_q event_refund_send_requests%ROWTYPE; v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.refund_claim_organizer_ok(p_claim_id) THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  IF NOT public.project_reason_ok(v_reason) THEN RETURN jsonb_build_object('success', false, 'error', 'REASON_REQUIRED'); END IF;
  SELECT * INTO v_q FROM event_refund_send_requests WHERE refund_claim_id = p_claim_id AND status = 'pending' FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'NO_REQUEST'); END IF;
  UPDATE event_refund_send_requests SET status = 'declined', decided_by = auth.uid(), decided_at = now(), reason = v_reason WHERE id = v_q.id;
  PERFORM public.event_money_audit_add(v_q.event_id, (SELECT COALESCE(booking_id, reservation_id) FROM refund_claims WHERE id = p_claim_id),
                                       p_claim_id, 'refund_decline', v_reason);
  IF EXISTS (SELECT 1 FROM event_projects WHERE event_id = v_q.event_id) THEN
    PERFORM public.project_touch(v_q.event_id, 'refund.decline', 'refund_claim', p_claim_id::text, jsonb_build_object('request_id', v_q.id));
  END IF;
  IF v_q.requested_by IS NOT NULL THEN
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (v_q.requested_by, 'project_refund_declined', 'Hoàn tiền chưa được duyệt', v_reason,
            jsonb_build_object('screen', 'event_project', 'event_id', v_q.event_id, 'tab', 'money', 'claim_id', p_claim_id));
  END IF;
  RETURN jsonb_build_object('success', true, 'status', 'declined');
END;
$$;

-- ================================================================== Host: approval mode (N1)
CREATE OR REPLACE FUNCTION public.project_set_refund_approval(p_event_id text, p_mode text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_err text := public.project_guard(p_event_id, true); v_old text;
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF NOT public.project_is_host(p_event_id) THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  IF p_mode IS NULL OR p_mode NOT IN ('host', 'finance_alone') THEN RETURN public.project_err('INVALID_VALUE'); END IF;
  SELECT refund_approval INTO v_old FROM event_projects WHERE event_id = p_event_id FOR UPDATE;
  IF v_old = p_mode THEN RETURN jsonb_build_object('success', true, 'mode', p_mode, 'noop', true); END IF;
  UPDATE event_projects SET refund_approval = p_mode WHERE event_id = p_event_id;
  PERFORM public.event_money_audit_add(p_event_id, NULL, NULL, 'set_refund_approval', p_mode);
  PERFORM public.project_touch(p_event_id, 'refund.approval', 'project', p_event_id, jsonb_build_object('from', v_old, 'to', p_mode));
  RETURN jsonb_build_object('success', true, 'mode', p_mode);
END;
$$;

-- ================================================================== Host: dispute grant (M5)
CREATE OR REPLACE FUNCTION public.project_extend_dispute_grant(p_event_id text, p_user_id uuid, p_refund_claim_id uuid, p_until timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RETURN public.project_err('AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN public.project_err('ACCOUNT_GATE'); END IF;
  IF NOT public.app_flag('event_project_hub', false) OR NOT public.app_flag('project_delegate_refunds', false) THEN RETURN public.project_err('FEATURE_OFF'); END IF;
  IF NOT public.project_is_host(p_event_id) THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  IF p_refund_claim_id IS NULL OR public.refund_claim_event(p_refund_claim_id) IS DISTINCT FROM p_event_id THEN RETURN public.project_err('NOT_FOUND'); END IF;
  IF NOT EXISTS (SELECT 1 FROM dispute_threads t WHERE t.refund_claim_id = p_refund_claim_id AND t.resolved_at IS NULL) THEN
    RETURN public.project_err('NO_OPEN_DISPUTE');
  END IF;
  -- Only someone who holds (or held, through an earlier dispute grant) money access for this event.
  IF NOT EXISTS (SELECT 1 FROM event_project_members m WHERE m.event_id = p_event_id AND m.user_id = p_user_id AND m.status = 'active'
                                                          AND (m.role = 'finance' OR m.cap_money))
     AND NOT EXISTS (SELECT 1 FROM event_dispute_refund_grants g WHERE g.event_id = p_event_id AND g.user_id = p_user_id)
  THEN RETURN public.project_err('NOT_A_DELEGATE'); END IF;
  IF EXISTS (SELECT 1 FROM event_project_members m WHERE m.event_id = p_event_id AND m.user_id = p_user_id AND m.status <> 'active') THEN
    RETURN public.project_err('NOT_A_DELEGATE');
  END IF;
  IF p_until IS NULL OR p_until <= now() OR p_until > now() + make_interval(days => public.project_limit('disputeGrantMaxDays')) THEN
    RETURN public.project_err('INVALID_VALUE');
  END IF;
  INSERT INTO event_dispute_refund_grants (event_id, refund_claim_id, user_id, until, created_by)
  VALUES (p_event_id, p_refund_claim_id, p_user_id, p_until, auth.uid())
  ON CONFLICT (refund_claim_id, user_id) DO UPDATE SET until = EXCLUDED.until, created_by = EXCLUDED.created_by
  RETURNING id INTO v_id;
  PERFORM public.event_money_audit_add(p_event_id, (SELECT COALESCE(booking_id, reservation_id) FROM refund_claims WHERE id = p_refund_claim_id),
                                       p_refund_claim_id, 'extend_dispute_grant', to_char(p_until AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI"Z"'));
  RETURN jsonb_build_object('success', true, 'grant_id', v_id, 'until', p_until);
END;
$$;

-- ================================================================== transfer receipt upload by a delegate
CREATE OR REPLACE FUNCTION public.refund_proof_delegate_ok(p_object_name text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_folder text := split_part(coalesce(p_object_name, ''), '/', 1);
BEGIN
  IF v_folder !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN RETURN false; END IF;
  RETURN EXISTS (SELECT 1 FROM refund_claims rc WHERE rc.id = v_folder::uuid AND rc.status::text IN ('owed', 'disputed'))
     AND public.project_refund_delegate_ok(v_folder::uuid);
END;
$$;

DROP POLICY IF EXISTS "refund_proof_delegate_insert" ON storage.objects;
CREATE POLICY "refund_proof_delegate_insert" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'refund-proof' AND public.refund_proof_delegate_ok(name));

-- ================================================================== mark_refund_sent (128 + delegation)
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
  v_delegate boolean := false;
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
  -- 215 (note 76): a refund delegate, behind switch project_delegate_refunds, on TOP of the unchanged check above. Under
  -- the default approval mode ('host') the delegate records the transfer with request_refund_send instead.
  IF NOT v_is_host AND public.project_refund_delegate_ok(p_claim_id) THEN
    IF public.project_refund_mode(v_event.id) <> 'finance_alone' THEN
      RETURN jsonb_build_object('success', false, 'error', 'APPROVAL_REQUIRED');
    END IF;
    v_delegate := true;
    v_is_host := true;
  END IF;
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

  -- 215: the claim is settled, so any team request waiting on it is closed (approve_refund_send then marks it approved).
  UPDATE public.event_refund_send_requests SET status = 'closed', decided_by = auth.uid(), decided_at = now()
   WHERE refund_claim_id = p_claim_id AND status = 'pending';
  IF v_delegate THEN PERFORM public.event_money_audit_add(v_event.id, v_booking.id, p_claim_id, 'refund_mark_sent', NULL); END IF;

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

-- ================================================================== purge_project_data (211 + "team access ended" notice)
CREATE OR REPLACE FUNCTION public.purge_project_data(p_now timestamptz DEFAULT now())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_cut timestamptz := p_now - make_interval(days => public.project_limit('trashDays'));
  v_tasks int; v_posts int; v_ros int; v_lanes int; v_invites int; v_attempts int; v_digest int; v_projects int;
  v_p record; v_open int; v_host uuid;
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

  -- 215: once every money delegate's grant is over, tell the Host ONCE how many open refunds are back with them.
  -- Silent while nothing is open (a later claim still triggers it), and only while refund delegation is on.
  IF public.app_flag('event_project_hub', false) AND public.app_flag('project_delegate_refunds', false) THEN
    FOR v_p IN
      SELECT p.event_id, e.name FROM event_projects p JOIN events e ON e.id = p.event_id
       WHERE p.grants_expired_notified_at IS NULL
         AND EXISTS (SELECT 1 FROM event_project_members m WHERE m.event_id = p.event_id AND m.status = 'active' AND (m.role = 'finance' OR m.cap_money))
         AND NOT EXISTS (SELECT 1 FROM event_project_members m WHERE m.event_id = p.event_id AND m.status = 'active'
                                                                AND (m.role = 'finance' OR m.cap_money) AND p_now < public.project_grant_end(p.event_id, m))
    LOOP
      SELECT count(*) INTO v_open FROM refund_claims rc JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
       WHERE b.event_id = v_p.event_id AND rc.status::text IN ('owed', 'disputed');
      CONTINUE WHEN v_open = 0;
      FOREACH v_host IN ARRAY public.project_host_ids(v_p.event_id) LOOP
        INSERT INTO notifications (recipient_id, kind, title, body, data)
        VALUES (v_host, 'project_grants_expired', 'Quyền tiền của đội đã hết',
                'Đội không còn quyền tiền ở ' || coalesce(v_p.name, 'sự kiện') || '. ' || v_open || ' khoản hoàn tiền đã về lại với bạn.',
                jsonb_build_object('screen', 'event_project', 'event_id', v_p.event_id, 'tab', 'money', 'open_refunds', v_open));
      END LOOP;
      UPDATE event_projects SET grants_expired_notified_at = p_now WHERE event_id = v_p.event_id;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('projects', v_projects, 'tasks', v_tasks, 'posts', v_posts, 'ros', v_ros, 'lanes', v_lanes,
                            'invites', v_invites, 'attempts', v_attempts, 'digest_log', v_digest);
END;
$$;
REVOKE ALL ON FUNCTION public.purge_project_data(timestamptz) FROM PUBLIC, anon, authenticated;

-- ================================================================== switch + who may call what
UPDATE public.app_feature_flag_defs SET description = 'Event Project Hub: team members with money access may handle refunds (215)'
 WHERE key = 'project_delegate_refunds';
REVOKE ALL ON FUNCTION public.refund_claim_event(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.project_refund_mode(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.project_refund_member_ok(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.project_refund_delegate_ok(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refund_claim_organizer_ok(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_event_refund_view(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.request_refund_send(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_refund_send(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decline_refund_send(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.project_set_refund_approval(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.project_extend_dispute_grant(text, uuid, uuid, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.refund_proof_delegate_ok(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_event_refund_view(text), public.request_refund_send(uuid, text, text),
  public.approve_refund_send(uuid), public.decline_refund_send(uuid, text), public.project_set_refund_approval(text, text),
  public.project_extend_dispute_grant(text, uuid, uuid, timestamptz) TO authenticated;
-- The storage policy evaluates as the caller, so the yes/no helper must be callable; it returns a boolean only.
GRANT EXECUTE ON FUNCTION public.refund_proof_delegate_ok(text) TO authenticated;
