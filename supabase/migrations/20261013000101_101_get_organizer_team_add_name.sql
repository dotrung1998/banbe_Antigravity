-- 101: get_organizer_team() (098) forward-fix — the public Team page
-- (Stage 2) needs the organizer's own real name to render standalone
-- (not only when navigated to from a screen that already has it loaded).
-- Everything else about the function (098) is unchanged.

CREATE OR REPLACE FUNCTION public.get_organizer_team(p_organizer_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_org organizers%ROWTYPE;
BEGIN
  SELECT * INTO v_org FROM organizers WHERE id = p_organizer_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;
  RETURN jsonb_build_object(
    'success', true,
    'organizer_id', p_organizer_id,
    'organizer_name', v_org.name,
    'members', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'handle', p.handle, 'display_name', p.display_name, 'avatar_url', p.avatar_url,
        'public_role', om.public_role, 'joined_at', om.joined_at
      ) ORDER BY om.joined_at ASC), '[]'::jsonb)
      FROM organizer_members om JOIN profiles p ON p.id = om.user_id
      WHERE om.organizer_id = p_organizer_id AND om.status = 'accepted' AND om.public_visible = true
    )
  );
END;
$$;
