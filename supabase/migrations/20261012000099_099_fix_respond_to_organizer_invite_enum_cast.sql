-- 099: forward-fix for 098's respond_to_organizer_invite() — the CASE
-- expression assigning `status` defaulted to `text`, which Postgres
-- refuses to assign into an enum column without an explicit cast ("column
-- \"status\" is of type organizer_member_status but expression is of type
-- text", caught by live verification before this ever shipped to a real
-- invite). Everything else about the function is unchanged.

CREATE OR REPLACE FUNCTION public.respond_to_organizer_invite(
  p_membership_id uuid,
  p_accept boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row organizer_members%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT * INTO v_row FROM organizer_members WHERE id = p_membership_id AND user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND'); END IF;
  IF v_row.status <> 'invited' THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_PENDING'); END IF;

  UPDATE organizer_members SET
    status = (CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END)::organizer_member_status,
    responded_at = now(),
    joined_at = CASE WHEN p_accept THEN now() ELSE NULL END
  WHERE id = p_membership_id;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  SELECT coalesce(o.owner_id, o.user_id), 'organizer_invite_response',
    CASE WHEN p_accept THEN 'Lời mời đã được chấp nhận' ELSE 'Lời mời đã bị từ chối' END,
    coalesce(p.display_name, '') || CASE WHEN p_accept THEN ' đã tham gia đội ngũ của bạn.' ELSE ' đã từ chối lời mời tham gia đội ngũ.' END,
    jsonb_build_object('organizer_id', v_row.organizer_id)
  FROM organizers o, profiles p WHERE o.id = v_row.organizer_id AND p.id = auth.uid()
    AND coalesce(o.owner_id, o.user_id) IS NOT NULL;

  RETURN jsonb_build_object('success', true, 'status', CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END);
END;
$$;
