-- 212 — Event Project Hub: delegated check-in (note 76, phase 9a). Behind switch project_delegate_checkin (seeded OFF).
--
-- Who: an ACTIVE project member whose role is Finance & door (always holds check-in) or whom the Host gave check-in
-- access (cap_checkin), while event_project_hub and project_delegate_checkin are both on, their grant has not expired
-- (grant_expires_at, default event end + 7 days) and the project is not read-only. The Host and admins keep exactly the
-- rights they have today: check_in_guest's own owner_id-or-user_id check is copied verbatim from 151 and delegation is
-- only tried when it fails (never project_is_host; see note 76). Cancelling the event, the payout account, undoing a
-- check-in and rejecting a pending guest are NOT delegated.
--
-- What a delegate sees: names and check-in state only. get_event_checkin_names has no amounts, codes, tokens, proofs or
-- dates of birth; project_checkin_lookup (the scanner path for delegates) answers name + "meets the minimum age" instead of
-- the date of birth that the Host-only get_checkin_guest_info returns. That minimal-disclosure choice is recorded in note 76
-- for the owner's review.
--
-- Audit: every delegated check-in writes ONE event_money_audit row (actor, booking, action, time). Rows are kept with the
-- booking (FK ON DELETE CASCADE), never with the project, and nobody can UPDATE or DELETE them.
--
-- LOCAL HARNESS ONLY until the owner says otherwise. Rollback: supabase/rollbacks/20261231000212_212_revert_delegated_checkin.sql
-- (puts 151's check_in_guest back verbatim).

-- ================================================================== audit (shared with 213/214)
CREATE TABLE IF NOT EXISTS public.event_money_audit (
  id bigserial PRIMARY KEY,
  event_id text NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  booking_id uuid REFERENCES public.bookings(id) ON DELETE CASCADE,
  refund_claim_id uuid,
  actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  action text NOT NULL CHECK (action IN ('checkin', 'undo_checkin', 'confirm_payment', 'reject_payment', 'proof_open', 'refund_request',
                                         'refund_approve', 'refund_mark_sent', 'set_refund_approval', 'extend_grants')),
  reason text CHECK (reason IS NULL OR length(reason) <= 140),
  at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS event_money_audit_event ON public.event_money_audit (event_id, at DESC);
CREATE INDEX IF NOT EXISTS event_money_audit_booking ON public.event_money_audit (booking_id) WHERE booking_id IS NOT NULL;
ALTER TABLE public.event_money_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.event_money_audit FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.event_money_audit TO authenticated;
GRANT SELECT, INSERT ON public.event_money_audit TO service_role;
-- The organizer accounts of the event (the existing money check) and admins read it; nobody writes from a client.
DROP POLICY IF EXISTS event_money_audit_select ON public.event_money_audit;
CREATE POLICY event_money_audit_select ON public.event_money_audit FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.events e JOIN public.organizers o ON o.id = e.organizer_id
           WHERE e.id = event_money_audit.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin'));

CREATE OR REPLACE FUNCTION public.event_money_audit_add(p_event_id text, p_booking_id uuid, p_claim_id uuid, p_action text, p_reason text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  INSERT INTO event_money_audit (event_id, booking_id, refund_claim_id, actor_id, action, reason)
  VALUES (p_event_id, p_booking_id, p_claim_id, auth.uid(), p_action, nullif(left(btrim(coalesce(p_reason, '')), 140), ''));
$$;

-- ================================================================== who is a delegate
-- The member's grant end: the stored one, or event end + grantDays.
CREATE OR REPLACE FUNCTION public.project_grant_end(p_event_id text, p_member public.event_project_members)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT coalesce(p_member.grant_expires_at, public.project_event_end(p_event_id) + make_interval(days => public.project_limit('grantDays')));
$$;

-- The delegate half only (the caller is NOT checked as Host here). cap: 'checkin' (212); 'money' arrives with 213.
CREATE OR REPLACE FUNCTION public.project_delegate_ok(p_event_id text, p_cap text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m event_project_members%ROWTYPE; v_flag text;
BEGIN
  IF auth.uid() IS NULL OR p_event_id IS NULL THEN RETURN false; END IF;
  v_flag := CASE p_cap WHEN 'checkin' THEN 'project_delegate_checkin' WHEN 'money' THEN 'project_delegate_payments' END;
  IF v_flag IS NULL OR NOT public.app_flag('event_project_hub', false) OR NOT public.app_flag(v_flag, false) THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM events e WHERE e.id = p_event_id AND e.status::text IN ('cancelled', 'removed')) THEN RETURN false; END IF;
  SELECT * INTO v_m FROM event_project_members m WHERE m.event_id = p_event_id AND m.user_id = auth.uid() AND m.status = 'active';
  IF NOT FOUND THEN RETURN false; END IF;
  IF NOT (v_m.role = 'finance' OR (p_cap = 'checkin' AND v_m.cap_checkin) OR (p_cap = 'money' AND v_m.cap_money)) THEN RETURN false; END IF;
  RETURN now() < public.project_grant_end(p_event_id, v_m) AND now() < public.project_read_only_at(p_event_id);
END;
$$;

-- The whole rule the delegated RPCs use: the EXISTING check (either organizer account, or an admin) or a live delegate.
CREATE OR REPLACE FUNCTION public.can_event_capability(p_event_id text, p_cap text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
                  WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
      OR EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
      OR public.project_delegate_ok(p_event_id, p_cap);
$$;

-- ================================================================== the door list (names only)
-- One row per named attendee (or one per booking when it has none): booking id, attendee id, name, party size,
-- checked in. No amounts, ticket codes, admission tokens, proofs or dates of birth.
CREATE OR REPLACE FUNCTION public.get_event_checkin_names(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.can_event_capability(p_event_id, 'checkin') THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  RETURN jsonb_build_object('success', true, 'guests', coalesce((SELECT jsonb_agg(g ORDER BY g->>'name', g->>'booking_id') FROM (
      SELECT jsonb_build_object('booking_id', b.id, 'attendee_id', a.id, 'name', a.name, 'party', 1, 'checked_in', a.checked_in_at IS NOT NULL) g
        FROM bookings b JOIN booking_attendees a ON a.booking_id = b.id
       WHERE b.event_id = p_event_id AND b.status IN ('confirmed', 'attended')
      UNION ALL
      SELECT jsonb_build_object('booking_id', b.id, 'attendee_id', NULL,
               'name', coalesce(nullif(b.recipient_name, ''), nullif(pr.display_name, ''), '—'), 'party', b.qty, 'checked_in', b.status = 'attended')
        FROM bookings b LEFT JOIN profiles pr ON pr.id = b.user_id
       WHERE b.event_id = p_event_id AND b.status IN ('confirmed', 'attended')
         AND NOT EXISTS (SELECT 1 FROM booking_attendees a WHERE a.booking_id = b.id)) t), '[]'::jsonb));
END;
$$;

-- The scanner path for delegates: what a ticket QR points at, as name + check-in state + whether the guest meets the
-- event's minimum age (null when the event sets none). Never the date of birth, never an amount.
CREATE OR REPLACE FUNCTION public.project_checkin_lookup(p_code uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_att booking_attendees%ROWTYPE; v_b bookings%ROWTYPE; v_name text; v_dob date; v_min int; v_age int;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT * INTO v_att FROM booking_attendees WHERE admission_token = p_code;
  IF FOUND THEN SELECT * INTO v_b FROM bookings WHERE id = v_att.booking_id;
  ELSE SELECT * INTO v_b FROM bookings WHERE id = p_code OR admission_token = p_code; END IF;
  IF v_b.id IS NULL OR NOT public.can_event_capability(v_b.event_id, 'checkin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;
  IF v_att.id IS NULL AND v_b.recipient_name IS NOT NULL AND v_b.admission_token IS NOT NULL AND p_code <> v_b.admission_token THEN
    RETURN jsonb_build_object('success', false, 'error', 'CREDENTIAL_INVALIDATED');
  END IF;
  IF v_b.status NOT IN ('confirmed', 'attended') THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_ELIGIBLE'); END IF;
  IF v_att.id IS NOT NULL THEN v_name := v_att.name; v_dob := v_att.date_of_birth;
  ELSIF v_b.recipient_name IS NOT NULL THEN v_name := v_b.recipient_name; v_dob := v_b.recipient_dob;
  ELSE
    SELECT nullif(p.display_name, '') INTO v_name FROM profiles p WHERE p.id = v_b.user_id;
    SELECT d.date_of_birth INTO v_dob FROM user_private_dob d WHERE d.user_id = v_b.user_id;
  END IF;
  SELECT nullif(e.details ->> 'min_age', '')::int INTO v_min FROM events e WHERE e.id = v_b.event_id;
  v_age := CASE WHEN v_dob IS NULL THEN NULL ELSE extract(year FROM age(current_date, v_dob))::int END;
  RETURN jsonb_build_object('success', true, 'booking_id', v_b.id, 'attendee_id', v_att.id, 'name', coalesce(v_name, ''),
    'already_checked_in', CASE WHEN v_att.id IS NOT NULL THEN v_att.checked_in_at IS NOT NULL ELSE v_b.status = 'attended' END,
    'min_age', v_min, 'meets_min_age', CASE WHEN v_min IS NULL THEN NULL WHEN v_age IS NULL THEN false ELSE v_age >= v_min END);
END;
$$;

-- ================================================================== grants (Host)
-- Extend every delegate's grant (p_member_id NULL) or one member's, up to read_only_at at most (M5: longer only
-- through a refund-dispute grant, phase 9c). One audit row per extension.
CREATE OR REPLACE FUNCTION public.project_extend_grants(p_event_id text, p_until timestamptz, p_member_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_err text := public.project_guard(p_event_id, true); v_n int;
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF NOT public.project_is_host(p_event_id) THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  IF p_until IS NULL OR p_until <= now() OR p_until > public.project_read_only_at(p_event_id) THEN RETURN public.project_err('INVALID_VALUE'); END IF;
  UPDATE event_project_members SET grant_expires_at = p_until
   WHERE event_id = p_event_id AND status = 'active' AND (p_member_id IS NULL OR id = p_member_id)
     AND (role = 'finance' OR cap_money OR cap_checkin);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RETURN public.project_err('NOT_FOUND'); END IF;
  PERFORM public.event_money_audit_add(p_event_id, NULL, NULL, 'extend_grants', to_char(p_until AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI"Z"'));
  PERFORM public.project_touch(p_event_id, 'grants.extend', 'member', coalesce(p_member_id::text, 'all'), jsonb_build_object('until', p_until, 'members', v_n));
  RETURN jsonb_build_object('success', true, 'members', v_n, 'until', p_until);
END;
$$;

-- ================================================================== check_in_guest (151 + delegation)
CREATE OR REPLACE FUNCTION public.check_in_guest(p_reservation_id uuid, p_source text DEFAULT 'manual')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_host boolean;
  v_is_admin boolean;
  v_checkin_id uuid;
  v_attendee uuid;
  v_att booking_attendees%ROWTYPE;
  v_has_attendees boolean;
  v_delegate boolean := false;
BEGIN
  -- An attendee's own QR resolves to that attendee (migration 151).
  SELECT * INTO v_att FROM booking_attendees WHERE admission_token = p_reservation_id;
  IF FOUND THEN
    SELECT * INTO v_booking FROM bookings WHERE id = v_att.booking_id;
  ELSE
    -- Match either primary ID or admission_token
    SELECT * INTO v_booking FROM bookings
    WHERE id = p_reservation_id OR admission_token = p_reservation_id;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
  END IF;

  -- Superseded-QR rejection (scan only). gifting a single seat rotates that
  -- seat's admission_token, so a screenshot of the ticket taken beforehand no
  -- longer resolves to it.
  IF v_att.id IS NULL
     AND coalesce(p_source, 'manual') = 'scan'
     AND v_booking.recipient_name IS NOT NULL
     AND v_booking.admission_token IS NOT NULL
     AND p_reservation_id != v_booking.admission_token THEN
    RETURN jsonb_build_object('success', false, 'error', 'Credential invalidated');
  END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  SELECT EXISTS(
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_booking.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) INTO v_is_host;

  SELECT EXISTS(
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ) INTO v_is_admin;

  -- 212 (note 76): a project team member with check-in access, behind switch project_delegate_checkin, on TOP of the
  -- unchanged check above. With the switch off this adds nothing.
  IF NOT v_is_host AND NOT v_is_admin THEN
    v_delegate := public.project_delegate_ok(v_booking.event_id, 'checkin');
    IF NOT v_delegate THEN
      RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
    END IF;
  END IF;

  IF v_booking.status NOT IN ('confirmed', 'attended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking is not eligible for check-in');
  END IF;

  SELECT EXISTS (SELECT 1 FROM booking_attendees WHERE booking_id = v_booking.id) INTO v_has_attendees;

  IF v_att.id IS NOT NULL THEN
    -- Per-attendee admission: this one person, once.
    IF v_att.checked_in_at IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Guest already checked in');
    END IF;
    UPDATE booking_attendees SET checked_in_at = now(), checked_in_by = auth.uid()
    WHERE id = v_att.id;
  ELSIF v_has_attendees THEN
    -- A booking-level credential on a booking that has named attendees. A
    -- scanned booking id must never admit a whole party; only a host tapping
    -- their own guest list ('manual') may, and that admits everyone not yet in.
    IF coalesce(p_source, 'manual') = 'scan' THEN
      RETURN jsonb_build_object('success', false, 'error', 'Scan each attendee''s own QR');
    END IF;
    UPDATE booking_attendees SET checked_in_at = now(), checked_in_by = auth.uid()
    WHERE booking_id = v_booking.id AND checked_in_at IS NULL;
  END IF;

  -- The booking-level record is written ONCE, on the first person through.
  INSERT INTO check_ins (booking_id, reservation_id, event_id, checked_in_by)
  VALUES (v_booking.id, v_booking.id, v_booking.event_id, auth.uid())
  ON CONFLICT (booking_id) DO NOTHING
  RETURNING id INTO v_checkin_id;

  IF v_checkin_id IS NULL THEN
    IF v_att.id IS NOT NULL THEN
      -- Not the first attendee: admitted, nothing else to stamp or notify.
      IF v_delegate THEN PERFORM public.event_money_audit_add(v_booking.event_id, v_booking.id, NULL, 'checkin', NULL); END IF;
      RETURN jsonb_build_object('success', true, 'booking_id', v_booking.id, 'name', v_att.name);
    END IF;
    RETURN jsonb_build_object('success', false, 'error', 'Guest already checked in');
  END IF;

  UPDATE bookings SET status = 'attended' WHERE id = v_booking.id;

  -- Attendance counts for the person who actually walked through the door:
  -- the claiming recipient once they have imported it, otherwise whoever the
  -- account on the row is. Purchaser's attended_count must not rise for a
  -- seat they handed over.
  v_attendee := coalesce(v_booking.claimed_by_user_id, v_booking.user_id);
  IF v_attendee IS NOT NULL AND v_attendee <> v_booking.purchaser_id THEN
    UPDATE profiles SET attended_count = COALESCE(attended_count, 0) + 1 WHERE id = v_attendee;
  END IF;

  IF v_attendee IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_attendee,
      'checked_in',
      'Bạn đã được điểm danh',
      COALESCE(v_event.name, 'Sự kiện') || ' vừa xác nhận bạn đã có mặt.',
      jsonb_build_object('event_id', v_booking.event_id, 'booking_id', v_booking.id)
    );
  END IF;

  IF v_delegate THEN PERFORM public.event_money_audit_add(v_booking.event_id, v_booking.id, NULL, 'checkin', NULL); END IF;

  RETURN jsonb_build_object(
    'success', true,
    'booking_id', v_booking.id,
    'name', COALESCE(v_att.name, v_booking.recipient_name, '')
  );
END;
$$;

-- ================================================================== switch + who may call what
UPDATE public.app_feature_flag_defs SET description = 'Event Project Hub: team members with check-in access may check guests in (212)'
 WHERE key = 'project_delegate_checkin';
REVOKE ALL ON FUNCTION public.event_money_audit_add(text, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.project_grant_end(text, public.event_project_members) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.project_delegate_ok(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_event_capability(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_event_checkin_names(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.project_checkin_lookup(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.project_extend_grants(text, timestamptz, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_event_checkin_names(text), public.project_checkin_lookup(uuid),
  public.project_extend_grants(text, timestamptz, uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.check_in_guest(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.check_in_guest(uuid, text) TO authenticated;
