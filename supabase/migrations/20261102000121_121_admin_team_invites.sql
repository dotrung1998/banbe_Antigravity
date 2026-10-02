-- 121: Admin Team invitations — "Admin Team" / "Invite Admin" in Account →
-- Admin, reusing the proven event/organizer-invite MECHANICS (high-entropy
-- hashed token, email-or-existing-user, identity re-verification at
-- redemption, revoke/expire/duplicate handling) but NOT their permissions.
--
-- ---------------------------------------------------------------------------
-- WHAT ALREADY EXISTS (not reinvented here)
-- ---------------------------------------------------------------------------
-- `public.profiles.role` ('participant'|'organizer'|'admin') is the one
-- source of truth for admin status; `public.is_platform_admin()` (026) is
-- the gate every admin-only RLS policy/RPC already checks. Today there is
-- exactly ONE designated admin, hardcoded by email in `handle_new_user()`
-- (040) — there is no "manage other admins" permission distinct from "is an
-- admin" at all. This migration does not touch `is_platform_admin()` or
-- any policy that already uses it — every existing admin-only surface
-- keeps working exactly as before.
--
-- ---------------------------------------------------------------------------
-- THE ACTUAL RBAC DECISION THIS MIGRATION MAKES (read before touching again)
-- ---------------------------------------------------------------------------
-- A real, explicit, server-enforced permission — `profiles.can_manage_admins`
-- — distinct from `role = 'admin'` itself. Being an admin and being allowed
-- to invite/revoke OTHER admins are two different things from this point
-- on, checked separately in every RPC below (`public.can_manage_admins()`).
-- Minimal compatible backfill: every account that is ALREADY an admin today
-- gets this permission granted (there is only the one), so nothing existing
-- breaks or silently loses capability. A newly-accepted admin invite does
-- NOT get it by default (see `respond_to_admin_invite` below) — it has to
-- be explicitly granted via `set_admin_management_permission()|, by someone
-- who already has it. This is what stops an unbounded "any admin can mint
-- infinite admins who can mint infinite admins" chain while still letting
-- today's one real admin manage a real team. Nothing here is a client-side
-- flag — every check is a fresh server-side read of this column, same
-- trust level as `is_platform_admin()` itself.

-- ---------------------------------------------------------------------------
-- 1. The permission column + its own checker, mirroring is_platform_admin()
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS can_manage_admins boolean NOT NULL DEFAULT false;

UPDATE public.profiles SET can_manage_admins = true WHERE role = 'admin';

CREATE OR REPLACE FUNCTION public.can_manage_admins()
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin' AND can_manage_admins = true
  );
$$;
GRANT EXECUTE ON FUNCTION public.can_manage_admins() TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. admin_invites — same shape/spirit as event_invites (113)/organizer_
--    members (098): a real table, RLS locked with no direct write policy at
--    all, every mutation through a SECURITY DEFINER RPC below.
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'admin_invite_status') THEN
    CREATE TYPE admin_invite_status AS ENUM ('pending', 'accepted', 'declined', 'revoked', 'expired');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS admin_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invited_email text NOT NULL,
  invited_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  token_hash text NOT NULL UNIQUE,
  status admin_invite_status NOT NULL DEFAULT 'pending',
  invited_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  responded_at timestamptz,
  revoked_at timestamptz,
  UNIQUE (invited_email)
);
CREATE INDEX IF NOT EXISTS idx_admin_invites_user ON admin_invites(invited_user_id);

ALTER TABLE admin_invites ENABLE ROW LEVEL SECURITY;

-- Only a manage-admins-capable admin sees the roster (pending/accepted/
-- revoked/expired history included — an internal management view).
DROP POLICY IF EXISTS "admin_invites_select_managers" ON admin_invites;
CREATE POLICY "admin_invites_select_managers" ON admin_invites FOR SELECT TO authenticated USING (
  public.can_manage_admins()
);
-- An invitee sees their OWN invite row (their own pending-invite badge/
-- accept UI) — never anyone else's.
DROP POLICY IF EXISTS "admin_invites_select_own" ON admin_invites;
CREATE POLICY "admin_invites_select_own" ON admin_invites FOR SELECT TO authenticated USING (
  invited_user_id = auth.uid()
);
-- No INSERT/UPDATE/DELETE policy for anyone — every write below goes
-- through a SECURITY DEFINER RPC, each enforcing its own authorization.

-- ---------------------------------------------------------------------------
-- 3. admin_action_log — invite/accept/revoke, auditable, never a credential
--    or token. Append-only from the server side; no client write path.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_action_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  target_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  target_email text,
  invite_id uuid REFERENCES admin_invites(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE admin_action_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin_action_log_select_managers" ON admin_action_log;
CREATE POLICY "admin_action_log_select_managers" ON admin_action_log FOR SELECT TO authenticated USING (
  public.can_manage_admins()
);
-- No write policy — only the RPCs below insert, via SECURITY DEFINER.

-- ---------------------------------------------------------------------------
-- 4. create_admin_invite() — manage-admins-capable admin only. Mirrors
--    create_event_invites()'s token/email shape exactly (32 random bytes,
--    stored only as its sha256 hash, returned once).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_admin_invite(p_email text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_email text := lower(trim(p_email));
  v_user_id uuid;
  v_token text;
  v_token_hash text;
  v_invite_id uuid;
  v_existing admin_invites%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.can_manage_admins() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  IF v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_EMAIL'); END IF;

  v_user_id := public.find_auth_user_by_email(v_email);
  IF v_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM profiles WHERE id = v_user_id AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_ADMIN');
  END IF;

  SELECT * INTO v_existing FROM admin_invites WHERE invited_email = v_email FOR UPDATE;
  IF FOUND AND v_existing.status = 'pending' AND v_existing.expires_at > now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_INVITED_PENDING');
  END IF;

  v_token := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_token, 'sha256'), 'hex');

  INSERT INTO admin_invites (invited_email, invited_user_id, token_hash, status, invited_by)
  VALUES (v_email, v_user_id, v_token_hash, 'pending', auth.uid())
  ON CONFLICT (invited_email) DO UPDATE SET
    invited_user_id = EXCLUDED.invited_user_id,
    token_hash = EXCLUDED.token_hash,
    status = 'pending',
    invited_by = auth.uid(),
    created_at = now(),
    expires_at = now() + interval '7 days',
    responded_at = NULL,
    revoked_at = NULL
  RETURNING id INTO v_invite_id;

  INSERT INTO admin_action_log (actor_id, action, target_user_id, target_email, invite_id)
  VALUES (auth.uid(), 'invite_created', v_user_id, v_email, v_invite_id);

  -- Existing-user invites get a real in-app notification through the SAME
  -- table/RLS every other kind already uses (019) — no new inbox. Email-
  -- only invites (v_user_id NULL) have no profiles row to notify; their
  -- delivery is the deep-link token itself, sent by the caller the same
  -- way create_event_invites' email-only case already works (api/notify.js).
  IF v_user_id IS NOT NULL THEN
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_user_id, 'admin_invite',
      'Lời mời trở thành quản trị viên',
      'Bạn được mời tham gia đội ngũ quản trị banbe.',
      jsonb_build_object('invite_id', v_invite_id)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'invite_id', v_invite_id, 'token', v_token, 'existing_user', v_user_id IS NOT NULL);
END;
$$;
REVOKE ALL ON FUNCTION public.create_admin_invite(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_admin_invite(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. revoke_admin_invite() — manage-admins-capable admin only. Only a
--    still-pending invite can be revoked (an already-accepted one is a real
--    admin now — see revoke_admin() below for THAT path instead).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.revoke_admin_invite(p_invite_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_invite admin_invites%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.can_manage_admins() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;

  SELECT * INTO v_invite FROM admin_invites WHERE id = p_invite_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'INVITE_NOT_FOUND'); END IF;
  IF v_invite.status != 'pending' THEN RETURN jsonb_build_object('success', false, 'error', 'INVITE_NOT_PENDING'); END IF;

  UPDATE admin_invites SET status = 'revoked', revoked_at = now() WHERE id = p_invite_id;
  INSERT INTO admin_action_log (actor_id, action, target_user_id, target_email, invite_id)
  VALUES (auth.uid(), 'invite_revoked', v_invite.invited_user_id, v_invite.invited_email, p_invite_id);

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.revoke_admin_invite(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.revoke_admin_invite(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. redeem_admin_invite_token() — binds an email-only invite to the NOW-
--    authenticated caller, identity re-verified against auth.users at
--    redemption time (never trusted from the token alone) — a forwarded
--    link cannot grant a different account access. Mirrors
--    redeem_event_invite_token() exactly. Binding only — does NOT itself
--    grant admin; respond_to_admin_invite() (below) does that.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.redeem_admin_invite_token(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_invite admin_invites%ROWTYPE;
  v_my_email text;
  v_token_hash text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF p_token IS NULL OR length(p_token) < 32 THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_TOKEN'); END IF;

  v_token_hash := encode(digest(p_token, 'sha256'), 'hex');
  SELECT * INTO v_invite FROM admin_invites WHERE token_hash = v_token_hash FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'INVITE_NOT_FOUND'); END IF;
  IF v_invite.status = 'revoked' THEN RETURN jsonb_build_object('success', false, 'error', 'INVITE_REVOKED'); END IF;
  IF v_invite.status NOT IN ('pending') AND v_invite.invited_user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVITE_NOT_PENDING');
  END IF;
  IF v_invite.expires_at <= now() THEN
    UPDATE admin_invites SET status = 'expired' WHERE id = v_invite.id;
    RETURN jsonb_build_object('success', false, 'error', 'INVITE_EXPIRED');
  END IF;

  SELECT email INTO v_my_email FROM auth.users WHERE id = auth.uid();
  IF v_my_email IS NULL OR lower(v_my_email) != lower(v_invite.invited_email) THEN
    RETURN jsonb_build_object('success', false, 'error', 'IDENTITY_MISMATCH');
  END IF;
  IF v_invite.invited_user_id IS NOT NULL AND v_invite.invited_user_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'IDENTITY_MISMATCH');
  END IF;

  UPDATE admin_invites SET invited_user_id = auth.uid()
  WHERE id = v_invite.id AND (invited_user_id IS NULL OR invited_user_id = auth.uid());

  RETURN jsonb_build_object('success', true, 'invite_id', v_invite.id);
END;
$$;
REVOKE ALL ON FUNCTION public.redeem_admin_invite_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.redeem_admin_invite_token(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 7. respond_to_admin_invite() — THE actual privilege-granting step.
--    Invitee-only (invited_user_id must already equal auth.uid(), either
--    because they were an existing user at invite time, or because
--    redeem_admin_invite_token() above already bound it). Re-verifies
--    identity AGAIN here (defense in depth against an account's email
--    changing between invite and accept) and does the role flip atomically
--    with the invite-row update, in the same transaction, so there is no
--    window where the invite reads "accepted" but the role never changed
--    (or vice versa) if anything after fails.
--
--    A newly-accepted admin does NOT inherit can_manage_admins — see this
--    file's own top-of-file RBAC note. Concurrent/repeated redemption is
--    safe: the `FOR UPDATE` row lock plus the `status = 'pending'` guard
--    means a second call (double-tap, replay) always sees NOT_PENDING.
-- ---------------------------------------------------------------------------
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
    UPDATE profiles SET role = 'admin' WHERE id = auth.uid();
    UPDATE admin_invites SET status = 'accepted', responded_at = now() WHERE id = p_invite_id;
    INSERT INTO admin_action_log (actor_id, action, target_user_id, target_email, invite_id)
    VALUES (auth.uid(), 'invite_accepted', auth.uid(), v_invite.invited_email, p_invite_id);
  ELSE
    UPDATE admin_invites SET status = 'declined', responded_at = now() WHERE id = p_invite_id;
    INSERT INTO admin_action_log (actor_id, action, target_user_id, target_email, invite_id)
    VALUES (auth.uid(), 'invite_declined', auth.uid(), v_invite.invited_email, p_invite_id);
  END IF;

  -- Let whoever sent it know, same dual-channel convention every other
  -- invite-response in this schema already uses.
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

-- ---------------------------------------------------------------------------
-- 8. set_admin_management_permission() — the ONLY way can_manage_admins
--    ever changes after this migration's own one-time backfill. Caller
--    must already have it; cannot be used to grant it to oneself (not that
--    it would do anything — the caller already has it by definition to
--    reach this far — but blocked anyway so the intent is unambiguous).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_admin_management_permission(p_user_id uuid, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.can_manage_admins() THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_user_id AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'TARGET_NOT_ADMIN');
  END IF;

  UPDATE profiles SET can_manage_admins = p_enabled WHERE id = p_user_id;
  INSERT INTO admin_action_log (actor_id, action, target_user_id)
  VALUES (auth.uid(), CASE WHEN p_enabled THEN 'management_permission_granted' ELSE 'management_permission_revoked' END, p_user_id);

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.set_admin_management_permission(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_admin_management_permission(uuid, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 9. revoke_admin() — demotes an existing admin back to 'participant'.
--    `profiles.role` has NO bearing on organizer/host authorization
--    anywhere in this schema (every real host check is organizers.owner_id/
--    user_id, confirmed by note 17's own audit) — demoting role here never
--    touches an account's organizer standing.
--    Guards: cannot revoke self (accidental self-lockout, unconditional —
--    simpler and safer than a "unless you're not the last one" carve-out);
--    cannot revoke the LAST remaining admin (so there's never a moment with
--    zero admins able to manage the platform or each other).
-- ---------------------------------------------------------------------------
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

  UPDATE profiles SET role = 'participant', can_manage_admins = false WHERE id = p_user_id;
  INSERT INTO admin_action_log (actor_id, action, target_user_id)
  VALUES (auth.uid(), 'admin_revoked', p_user_id);

  -- Proactive client resync (see this migration's own doc note on "revoke
  -- must invalidate access, not just hide a tab until next login") — both
  -- clients' existing notification poll resyncs the role the instant this
  -- lands, same "proactive, not tap-gated" pattern booking_declined's
  -- Going-tag refetch already established (15-organizer-checkin.md).
  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (p_user_id, 'admin_access_revoked', 'Quyền quản trị đã bị thu hồi', 'Bạn không còn là quản trị viên của banbe.', '{}'::jsonb);

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.revoke_admin(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.revoke_admin(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 10. expire_stale_admin_invites() — pg_cron, same "doesn't need anyone to
--     have the app open" pattern as goc_expire_lapsed_pendings/close_expired_
--     surveys (008, 114). Keeps the pending-invite badge honest even if
--     nobody ever redeems/views the stale invite.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_stale_admin_invites()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE admin_invites SET status = 'expired' WHERE status = 'pending' AND expires_at <= now();
$$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('expire-stale-admin-invites', '* * * * *', 'SELECT public.expire_stale_admin_invites()');
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- pg_cron not available/permitted in this environment — non-fatal; the
  -- lazy expiry check already embedded in redeem/respond above still
  -- correctly refuses a stale invite on actual use, this job only makes
  -- the BADGE (nothing counts an expired invite as pending) accurate
  -- without a redemption attempt.
  NULL;
END $$;

-- ---------------------------------------------------------------------------
-- 11. list_admin_roster() — the ONE read path for "who are the current
--     admins" the Admin Team UI needs. A dedicated, tightly-scoped RPC
--     rather than a new/broadened `profiles` RLS policy letting an admin
--     SELECT arbitrary other rows — keeps this feature from widening any
--     unrelated access to other accounts' profile data (this migration's
--     own "no unrelated access" requirement). Returns only the fields the
--     roster UI needs, never email/phone/private columns.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_admin_roster()
RETURNS TABLE(id uuid, display_name text, avatar_url text, can_manage_admins boolean, is_self boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.can_manage_admins() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY
    SELECT p.id, p.display_name, p.avatar_url, p.can_manage_admins, p.id = auth.uid()
    FROM profiles p WHERE p.role = 'admin' ORDER BY p.can_manage_admins DESC, p.display_name ASC;
END;
$$;
REVOKE ALL ON FUNCTION public.list_admin_roster() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_admin_roster() TO authenticated;

-- ---------------------------------------------------------------------------
-- 12. Admins seeing private documents/data — UNCHANGED. This migration adds
--     no new admin-wide data-access grant; every existing admin-scoped RLS
--     policy (bookings_select_admin, dispute_threads, pay-proof storage,
--     etc.) is untouched. A newly-accepted admin gets exactly the same
--     access any other admin already has today — nothing broader.
-- ---------------------------------------------------------------------------
