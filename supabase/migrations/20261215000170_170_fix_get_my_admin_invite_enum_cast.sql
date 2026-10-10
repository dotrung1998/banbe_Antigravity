-- Migration: fix get_my_admin_invite() (169). admin_invites.status is the enum
-- admin_invite_status, but 169 declared the returned column as text and
-- selected the enum unconverted; plpgsql RETURN QUERY rejects that at call time
-- ("Returned type admin_invite_status ... does not match expected type text"),
-- so the RPC always errored. Cast to text. Same signature/return type, so
-- CREATE OR REPLACE is sufficient.
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
  SELECT ai.id, ai.invited_email, ai.status::text, ai.created_at, ai.expires_at
  FROM admin_invites ai
  WHERE ai.invited_user_id = auth.uid() AND ai.status = 'pending' AND ai.expires_at > now()
  ORDER BY ai.created_at DESC
  LIMIT 1;
END;
$$;
REVOKE ALL ON FUNCTION public.get_my_admin_invite() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_admin_invite() TO authenticated;
