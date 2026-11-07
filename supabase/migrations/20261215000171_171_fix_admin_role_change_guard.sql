-- Migration: respond_to_admin_invite() / revoke_admin() (121) could never change
-- profiles.role. guard_profile_role() (016) silently reverts ANY role change made
-- while auth.uid() is non-null unless `app.role_change_allowed` = '1'; SECURITY
-- DEFINER does not clear auth.uid(), and 121 never set that flag. Result: accepting
-- an admin invite marked the invite 'accepted' (and notified the sender) but the
-- account stayed a participant, so no Admin tab ever appeared; revoke_admin() had
-- the same silent no-op in the other direction.
--
-- Fix: set the flag around exactly the role UPDATE, as set_organizer_mode() does
-- (016/082/103), and reset it right after. Function bodies are otherwise identical
-- to 121.
CREATE OR REPLACE FUNCTION public.respond_to_admin_invite(p_invite_id uuid, p_accept boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_invite admin_invites%ROWTYPE;
  v_my_email text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;

  SELECT * INTO v_invite FROM admin_invites WHERE id = p_invite_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'INVITE_NOT_FOUND'); END IF;
  IF v_invite.invited_user_id IS DISTINCT FROM auth.uid() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  IF v_invite.status != 'pending' THEN RETURN jsonb_build_object('success', false, 'error', 'INVITE_NOT_PENDING'); END IF;
  IF v_invite.expires_at <= now() THEN
    UPDATE admin_invites SET status = 'expired' WHERE id = p_invite_id;
    RETURN jsonb_build_object('success', false, 'error', 'INVITE_EXPIRED');
  END IF;

  SELECT email INTO v_my_email FROM auth.users WHERE id = auth.uid();
  IF v_my_email IS NULL OR lower(v_my_email) != lower(v_invite.invited_email) THEN
    RETURN jsonb_build_object('success', false, 'error', 'IDENTITY_MISMATCH');
  END IF;

  IF p_accept THEN
    PERFORM set_config('app.role_change_allowed', '1', true);
    UPDATE profiles SET role = 'admin' WHERE id = auth.uid();
    PERFORM set_config('app.role_change_allowed', '0', true);
    UPDATE admin_invites SET status = 'accepted', responded_at = now() WHERE id = p_invite_id;
    INSERT INTO admin_action_log (actor_id, action, target_user_id, target_email, invite_id)
    VALUES (auth.uid(), 'invite_accepted', auth.uid(), v_invite.invited_email, p_invite_id);
  ELSE
    UPDATE admin_invites SET status = 'declined', responded_at = now() WHERE id = p_invite_id;
    INSERT INTO admin_action_log (actor_id, action, target_user_id, target_email, invite_id)
    VALUES (auth.uid(), 'invite_declined', auth.uid(), v_invite.invited_email, p_invite_id);
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  SELECT v_invite.invited_by, 'admin_invite_response',
    CASE WHEN p_accept THEN 'Lời mời quản trị đã được chấp nhận' ELSE 'Lời mời quản trị đã bị từ chối' END,
    coalesce(p.display_name, v_invite.invited_email),
    jsonb_build_object('invite_id', p_invite_id)
  FROM profiles p WHERE p.id = auth.uid();

  RETURN jsonb_build_object('success', true, 'status', CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END);
END;
$$;
REVOKE ALL ON FUNCTION public.respond_to_admin_invite(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.respond_to_admin_invite(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.revoke_admin(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_count int;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.can_manage_admins() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  IF p_user_id = auth.uid() THEN RETURN jsonb_build_object('success', false, 'error', 'CANNOT_REVOKE_SELF'); END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_user_id AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'TARGET_NOT_ADMIN');
  END IF;

  SELECT count(*) INTO v_admin_count FROM profiles WHERE role = 'admin';
  IF v_admin_count <= 1 THEN RETURN jsonb_build_object('success', false, 'error', 'LAST_ADMIN_CANNOT_BE_REVOKED'); END IF;

  PERFORM set_config('app.role_change_allowed', '1', true);
  UPDATE profiles SET role = 'participant', can_manage_admins = false WHERE id = p_user_id;
  PERFORM set_config('app.role_change_allowed', '0', true);
  INSERT INTO admin_action_log (actor_id, action, target_user_id)
  VALUES (auth.uid(), 'admin_revoked', p_user_id);

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (p_user_id, 'admin_access_revoked', 'Quyền quản trị đã bị thu hồi', 'Bạn không còn là quản trị viên của banbe.', '{}'::jsonb);

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.revoke_admin(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.revoke_admin(uuid) TO authenticated;

-- One-time repair: accounts that already ACCEPTED an invite while the guard was
-- silently reverting the role. Promote only those whose accepted invite is not
-- followed by an admin_revoked entry. (Past revoke_admin() calls were no-ops too,
-- so a previously "revoked" admin may still be an admin — review separately.)
-- can_manage_admins is deliberately NOT granted (a new admin never inherits it).
UPDATE public.profiles p
SET role = 'admin'
FROM public.admin_invites ai
WHERE ai.status = 'accepted' AND ai.invited_user_id = p.id AND p.role <> 'admin'
  AND NOT EXISTS (
    SELECT 1 FROM public.admin_action_log l
    WHERE l.target_user_id = p.id AND l.action = 'admin_revoked'
      AND l.created_at > coalesce(ai.responded_at, ai.created_at)
  );
