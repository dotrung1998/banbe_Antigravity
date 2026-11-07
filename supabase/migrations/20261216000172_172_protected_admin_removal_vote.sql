-- Migration 172: protect banbetestadmin@gmail.com (the "protected admin") from
-- being stripped of team-management access or of the admin role, except through
-- a voting round — and only while there are at least 3 admins.
--
-- Rules (decided with the owner, 2026-10-10)
--   * Protects BOTH: can_manage_admins ("team-management access") and role = 'admin'.
--   * With fewer than 3 admins in total (role = 'admin', protected admin included)
--     neither can be removed at all. With 3 or more, a vote may be opened.
--   * Electorate = admins WITH can_manage_admins, EXCLUDING the protected admin
--     (they do not vote on their own removal). A strict majority of the electorate
--     (floor(n/2)+1 yes votes) is required; at least 2 voters must exist.
--   * Any electorate member may open a vote (the opener's vote counts as yes) and
--     cast one ballot (no changing it). Votes expire after 72 hours.
--   * The direct paths (revoke_admin / set_admin_management_permission) now refuse
--     the protected admin outright. The removal itself runs only from
--     _apply_admin_removal(), which no client role can execute.
--   * A new admin does not inherit can_manage_admins (121), so they must be granted
--     it before they can vote.

-- ---------------------------------------------------------------------------
-- 1. Who is protected
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protected_admin_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT id FROM auth.users WHERE lower(email) = 'banbetestadmin@gmail.com' LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.protected_admin_id() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Vote tables (RLS on, no policies: only the SECURITY DEFINER RPCs below touch them)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_removal_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('revoke_admin', 'revoke_management')),
  opened_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'passed', 'failed', 'expired', 'cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '72 hours'),
  resolved_at timestamptz
);
-- one open vote per target+kind
CREATE UNIQUE INDEX IF NOT EXISTS admin_removal_votes_one_open
  ON public.admin_removal_votes (target_user_id, kind) WHERE status = 'open';

CREATE TABLE IF NOT EXISTS public.admin_removal_ballots (
  vote_id uuid NOT NULL REFERENCES public.admin_removal_votes(id) ON DELETE CASCADE,
  voter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  approve boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (vote_id, voter_id)
);
ALTER TABLE public.admin_removal_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_removal_ballots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_removal_votes, public.admin_removal_ballots FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Counting helpers (internal)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._admin_total()
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::int FROM profiles WHERE role = 'admin';
$$;
REVOKE ALL ON FUNCTION public._admin_total() FROM PUBLIC, anon, authenticated;

-- Voters for a removal of p_target: managers other than the target.
CREATE OR REPLACE FUNCTION public._admin_electorate(p_target uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::int FROM profiles WHERE role = 'admin' AND can_manage_admins = true AND id <> p_target;
$$;
REVOKE ALL ON FUNCTION public._admin_electorate(uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Direct paths now refuse the protected admin
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_admin_management_permission(p_user_id uuid, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.can_manage_admins() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_user_id AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'TARGET_NOT_ADMIN');
  END IF;
  IF NOT p_enabled AND p_user_id = public.protected_admin_id() THEN
    RETURN jsonb_build_object('success', false,
      'error', CASE WHEN public._admin_total() < 3 THEN 'PROTECTED_ADMIN_MIN_ADMINS' ELSE 'PROTECTED_ADMIN_VOTE_REQUIRED' END);
  END IF;

  UPDATE profiles SET can_manage_admins = p_enabled WHERE id = p_user_id;
  INSERT INTO admin_action_log (actor_id, action, target_user_id)
  VALUES (auth.uid(), CASE WHEN p_enabled THEN 'management_permission_granted' ELSE 'management_permission_revoked' END, p_user_id);

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.set_admin_management_permission(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_admin_management_permission(uuid, boolean) TO authenticated;

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
  IF p_user_id = public.protected_admin_id() THEN
    RETURN jsonb_build_object('success', false,
      'error', CASE WHEN public._admin_total() < 3 THEN 'PROTECTED_ADMIN_MIN_ADMINS' ELSE 'PROTECTED_ADMIN_VOTE_REQUIRED' END);
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

-- ---------------------------------------------------------------------------
-- 5. Applying a passed vote — internal only (no client role may execute it)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._apply_admin_removal(p_vote_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v public.admin_removal_votes%ROWTYPE;
BEGIN
  SELECT * INTO v FROM public.admin_removal_votes WHERE id = p_vote_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  -- The world may have changed since the vote opened: re-check the floor.
  IF public._admin_total() < 3 OR NOT EXISTS (SELECT 1 FROM profiles WHERE id = v.target_user_id AND role = 'admin') THEN
    UPDATE public.admin_removal_votes SET status = 'cancelled', resolved_at = now() WHERE id = p_vote_id;
    RETURN false;
  END IF;

  IF v.kind = 'revoke_admin' THEN
    PERFORM set_config('app.role_change_allowed', '1', true);
    UPDATE profiles SET role = 'participant', can_manage_admins = false WHERE id = v.target_user_id;
    PERFORM set_config('app.role_change_allowed', '0', true);
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (v.target_user_id, 'admin_access_revoked', 'Quyền quản trị đã bị thu hồi', 'Bạn không còn là quản trị viên của banbe.', '{}'::jsonb);
  ELSE
    UPDATE profiles SET can_manage_admins = false WHERE id = v.target_user_id;
  END IF;

  UPDATE public.admin_removal_votes SET status = 'passed', resolved_at = now() WHERE id = p_vote_id;
  INSERT INTO admin_action_log (actor_id, action, target_user_id)
  VALUES (v.opened_by,
          CASE WHEN v.kind = 'revoke_admin' THEN 'admin_revoked_by_vote' ELSE 'management_permission_revoked_by_vote' END,
          v.target_user_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public._apply_admin_removal(uuid) FROM PUBLIC, anon, authenticated;

-- Marks open votes past their deadline as expired (called before any read/write below).
CREATE OR REPLACE FUNCTION public._expire_admin_removal_votes()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.admin_removal_votes SET status = 'expired', resolved_at = now()
  WHERE status = 'open' AND expires_at <= now();
$$;
REVOKE ALL ON FUNCTION public._expire_admin_removal_votes() FROM PUBLIC, anon, authenticated;

-- Resolves a vote if the tally is decided (passed or can no longer pass). Returns its status.
CREATE OR REPLACE FUNCTION public._resolve_admin_removal_vote(p_vote_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v public.admin_removal_votes%ROWTYPE;
  n int; needed int; yes_n int; no_n int;
BEGIN
  SELECT * INTO v FROM public.admin_removal_votes WHERE id = p_vote_id;
  IF NOT FOUND OR v.status <> 'open' THEN RETURN coalesce(v.status, 'missing'); END IF;
  n := public._admin_electorate(v.target_user_id);
  needed := n / 2 + 1;
  SELECT count(*) FILTER (WHERE b.approve), count(*) FILTER (WHERE NOT b.approve) INTO yes_n, no_n
  FROM public.admin_removal_ballots b
  JOIN profiles p ON p.id = b.voter_id AND p.role = 'admin' AND p.can_manage_admins = true AND p.id <> v.target_user_id
  WHERE b.vote_id = p_vote_id;

  IF yes_n >= needed THEN
    PERFORM public._apply_admin_removal(p_vote_id);
  ELSIF no_n > n - needed THEN
    UPDATE public.admin_removal_votes SET status = 'failed', resolved_at = now() WHERE id = p_vote_id;
  END IF;
  RETURN (SELECT status FROM public.admin_removal_votes WHERE id = p_vote_id);
END;
$$;
REVOKE ALL ON FUNCTION public._resolve_admin_removal_vote(uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Client RPCs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.open_admin_removal_vote(p_target uuid, p_kind text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id uuid;
  v_opener_name text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.can_manage_admins() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  IF p_kind NOT IN ('revoke_admin', 'revoke_management') THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_KIND'); END IF;
  IF p_target IS DISTINCT FROM public.protected_admin_id() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_PROTECTED_TARGET'); END IF;
  IF p_target = auth.uid() THEN RETURN jsonb_build_object('success', false, 'error', 'CANNOT_VOTE_ON_SELF'); END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_target AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'TARGET_NOT_ADMIN');
  END IF;
  IF p_kind = 'revoke_management' AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_target AND can_manage_admins = true) THEN
    RETURN jsonb_build_object('success', false, 'error', 'TARGET_HAS_NO_MANAGEMENT_ACCESS');
  END IF;
  IF public._admin_total() < 3 THEN RETURN jsonb_build_object('success', false, 'error', 'PROTECTED_ADMIN_MIN_ADMINS'); END IF;
  IF public._admin_electorate(p_target) < 2 THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_ENOUGH_VOTERS'); END IF;

  PERFORM public._expire_admin_removal_votes();
  IF EXISTS (SELECT 1 FROM public.admin_removal_votes WHERE target_user_id = p_target AND kind = p_kind AND status = 'open') THEN
    RETURN jsonb_build_object('success', false, 'error', 'VOTE_ALREADY_OPEN');
  END IF;

  INSERT INTO public.admin_removal_votes (target_user_id, kind, opened_by) VALUES (p_target, p_kind, auth.uid()) RETURNING id INTO v_id;
  INSERT INTO public.admin_removal_ballots (vote_id, voter_id, approve) VALUES (v_id, auth.uid(), true);
  INSERT INTO admin_action_log (actor_id, action, target_user_id)
  VALUES (auth.uid(), 'removal_vote_opened_' || p_kind, p_target);

  SELECT coalesce(display_name, 'Admin') INTO v_opener_name FROM profiles WHERE id = auth.uid();
  INSERT INTO notifications (recipient_id, kind, title, body, data)
  SELECT p.id, 'admin_removal_vote',
    'Cần bỏ phiếu: ' || CASE WHEN p_kind = 'revoke_admin' THEN 'gỡ quyền quản trị' ELSE 'gỡ quyền quản lý đội ngũ' END,
    v_opener_name || ' đã mở một cuộc bỏ phiếu. Vào Đội Ngũ Quản Trị để bỏ phiếu.',
    jsonb_build_object('vote_id', v_id)
  FROM profiles p WHERE p.role = 'admin' AND p.can_manage_admins = true AND p.id NOT IN (p_target, auth.uid());

  PERFORM public._resolve_admin_removal_vote(v_id);  -- the opener's yes may already be decisive
  RETURN jsonb_build_object('success', true, 'vote_id', v_id);
END;
$$;
REVOKE ALL ON FUNCTION public.open_admin_removal_vote(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_admin_removal_vote(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.cast_admin_removal_vote(p_vote_id uuid, p_approve boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v public.admin_removal_votes%ROWTYPE;
  v_status text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.can_manage_admins() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  PERFORM public._expire_admin_removal_votes();
  SELECT * INTO v FROM public.admin_removal_votes WHERE id = p_vote_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'VOTE_NOT_FOUND'); END IF;
  IF v.status <> 'open' THEN RETURN jsonb_build_object('success', false, 'error', 'VOTE_NOT_OPEN'); END IF;
  IF auth.uid() = v.target_user_id THEN RETURN jsonb_build_object('success', false, 'error', 'CANNOT_VOTE_ON_SELF'); END IF;
  IF EXISTS (SELECT 1 FROM public.admin_removal_ballots WHERE vote_id = p_vote_id AND voter_id = auth.uid()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_VOTED');
  END IF;

  INSERT INTO public.admin_removal_ballots (vote_id, voter_id, approve) VALUES (p_vote_id, auth.uid(), p_approve);
  v_status := public._resolve_admin_removal_vote(p_vote_id);

  IF v_status IN ('passed', 'failed') THEN
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    SELECT p.id, 'admin_removal_vote_result',
      CASE WHEN v_status = 'passed' THEN 'Cuộc bỏ phiếu đã được thông qua' ELSE 'Cuộc bỏ phiếu không được thông qua' END,
      'Xem chi tiết trong Đội Ngũ Quản Trị.',
      jsonb_build_object('vote_id', p_vote_id, 'status', v_status)
    FROM profiles p
    WHERE p.role = 'admin' AND p.can_manage_admins = true AND p.id <> v.target_user_id
       OR p.id = v.target_user_id;
  END IF;
  RETURN jsonb_build_object('success', true, 'status', v_status);
END;
$$;
REVOKE ALL ON FUNCTION public.cast_admin_removal_vote(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cast_admin_removal_vote(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_admin_removal_vote(p_vote_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v public.admin_removal_votes%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT * INTO v FROM public.admin_removal_votes WHERE id = p_vote_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'VOTE_NOT_FOUND'); END IF;
  IF v.opened_by <> auth.uid() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  IF v.status <> 'open' THEN RETURN jsonb_build_object('success', false, 'error', 'VOTE_NOT_OPEN'); END IF;
  UPDATE public.admin_removal_votes SET status = 'cancelled', resolved_at = now() WHERE id = p_vote_id;
  INSERT INTO admin_action_log (actor_id, action, target_user_id)
  VALUES (auth.uid(), 'removal_vote_cancelled', v.target_user_id);
  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_admin_removal_vote(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_admin_removal_vote(uuid) TO authenticated;

-- One read for both clients: the protection state + open votes with tallies.
CREATE OR REPLACE FUNCTION public.admin_removal_overview()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_target uuid := public.protected_admin_id();
  v_total int;
  v_n int;
  v_votes jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_manage_admins() THEN
    RETURN jsonb_build_object('error', 'NOT_AUTHORIZED');
  END IF;
  PERFORM public._expire_admin_removal_votes();
  v_total := public._admin_total();
  v_n := coalesce(public._admin_electorate(v_target), 0);

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', rv.id,
      'kind', rv.kind,
      'target_user_id', rv.target_user_id,
      'target_name', coalesce(tp.display_name, ''),
      'opened_by_name', coalesce(op.display_name, ''),
      'is_opener', rv.opened_by = auth.uid(),
      'expires_at', rv.expires_at,
      'yes', (SELECT count(*) FROM public.admin_removal_ballots b WHERE b.vote_id = rv.id AND b.approve),
      'no', (SELECT count(*) FROM public.admin_removal_ballots b WHERE b.vote_id = rv.id AND NOT b.approve),
      'electorate', v_n,
      'needed', v_n / 2 + 1,
      'my_vote', (SELECT CASE WHEN b.approve THEN 'yes' ELSE 'no' END FROM public.admin_removal_ballots b WHERE b.vote_id = rv.id AND b.voter_id = auth.uid()),
      'can_vote', auth.uid() <> rv.target_user_id
                  AND NOT EXISTS (SELECT 1 FROM public.admin_removal_ballots b WHERE b.vote_id = rv.id AND b.voter_id = auth.uid())
    ) ORDER BY rv.created_at), '[]'::jsonb)
  INTO v_votes
  FROM public.admin_removal_votes rv
  LEFT JOIN profiles tp ON tp.id = rv.target_user_id
  LEFT JOIN profiles op ON op.id = rv.opened_by
  WHERE rv.status = 'open';

  RETURN jsonb_build_object(
    'protected_user_id', v_target,
    'admin_count', v_total,
    'min_admins', 3,
    'electorate', v_n,
    'can_open', v_total >= 3 AND v_n >= 2,
    'votes', v_votes
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_removal_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_removal_overview() TO authenticated;
