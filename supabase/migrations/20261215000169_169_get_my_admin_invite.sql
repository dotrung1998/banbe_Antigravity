-- Migration: get_my_admin_invite() — the invitee's own pending admin invite,
-- resolved by the SIGNED-IN account's email (auth.users), not only by
-- admin_invites.invited_user_id.
--
-- Why: the clients used a plain select filtered on invited_user_id = auth.uid()
-- (RLS admin_invites_select_own). An invite whose invited_user_id is NULL
-- (email-only invite, or the account didn't resolve at invite time) was
-- therefore invisible to its own recipient: no banner, and respond_to_admin_
-- invite() (which requires invited_user_id = auth.uid()) could never run.
-- This RPC verifies identity server-side (same check as redeem_admin_invite_
-- token), binds invited_user_id on first sight, and returns the row.
-- Expired pending invites are marked expired and not returned.
CREATE OR REPLACE FUNCTION public.get_my_admin_invite()
RETURNS TABLE (id uuid, invited_email text, status text, created_at timestamptz, expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_email text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  SELECT lower(u.email) INTO v_email FROM auth.users u WHERE u.id = auth.uid();
  IF v_email IS NULL THEN RETURN; END IF;

  UPDATE admin_invites ai SET status = 'expired'
  WHERE ai.status = 'pending' AND ai.expires_at <= now()
    AND (ai.invited_user_id = auth.uid() OR (ai.invited_user_id IS NULL AND lower(ai.invited_email) = v_email));

  UPDATE admin_invites ai SET invited_user_id = auth.uid()
  WHERE ai.status = 'pending' AND ai.invited_user_id IS NULL AND lower(ai.invited_email) = v_email;

  RETURN QUERY
  SELECT ai.id, ai.invited_email, ai.status, ai.created_at, ai.expires_at
  FROM admin_invites ai
  WHERE ai.invited_user_id = auth.uid() AND ai.status = 'pending' AND ai.expires_at > now()
  ORDER BY ai.created_at DESC
  LIMIT 1;
END;
$$;
REVOKE ALL ON FUNCTION public.get_my_admin_invite() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_admin_invite() TO authenticated;
