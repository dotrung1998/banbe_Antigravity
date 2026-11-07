-- 098: Organizer Team pass (2026-09-27), Stage 1 — real, opt-in organizer
-- membership, kept strictly separate from authorization.
--
-- `organizer_members` is genuinely new: nothing before this derived "who's
-- on a Team" from follows/bookings/check-ins, and this migration doesn't
-- either — every row here is the direct result of an explicit invite this
-- account's owner sent and the invitee accepted. No existing account is
-- auto-published as a member of anything.
--
-- Two axes, deliberately never conflated:
--   - `status` (invited/accepted/declined/removed) — is this a REAL,
--     accepted membership at all.
--   - `public_visible` — does the MEMBER (never the owner) want it shown
--     publicly. Defaults false even once accepted; only
--     set_organizer_member_visibility() (invitee-only) can ever turn it
--     on, and remove_organizer_member() (owner-only) can only ever force
--     it back OFF, never on — "owner may remove membership but cannot
--     force it public" is enforced structurally, not just by convention:
--     no RPC lets the owner write `public_visible = true` for anyone.
--   - `public_role` is a display-only title ("Người sáng lập"/"Điều phối"/
--     "Thành viên"). It is NEVER read by any authorization check anywhere
--     — event/payment/refund/bank actions still gate purely on
--     `organizers.owner_id`/`organizers.user_id`, exactly as before this
--     migration. A member with a fancy public title has exactly the same
--     (zero) write access to those as before.

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'organizer_member_status') THEN
    CREATE TYPE organizer_member_status AS ENUM ('invited', 'accepted', 'declined', 'removed');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS organizer_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id text NOT NULL REFERENCES organizers(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status organizer_member_status NOT NULL DEFAULT 'invited',
  public_role text NOT NULL DEFAULT 'Thành viên',
  public_visible boolean NOT NULL DEFAULT false,
  invited_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  invited_at timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,
  joined_at timestamptz,
  removed_at timestamptz,
  UNIQUE (organizer_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_organizer_members_organizer ON organizer_members(organizer_id);
CREATE INDEX IF NOT EXISTS idx_organizer_members_user ON organizer_members(user_id);

ALTER TABLE organizer_members ENABLE ROW LEVEL SECURITY;

-- Owner/co-owner sees the FULL roster (every status, including a removed/
-- declined history) — an internal management view, never what anon/public
-- gets (that's get_organizer_team() below, accepted+public_visible only).
DROP POLICY IF EXISTS "organizer_members_select_owner" ON organizer_members;
CREATE POLICY "organizer_members_select_owner" ON organizer_members FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = organizer_members.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);
-- A member sees their OWN row on any organizer (their pending invites,
-- their own current visibility switch) — never another member's row.
DROP POLICY IF EXISTS "organizer_members_select_own" ON organizer_members;
CREATE POLICY "organizer_members_select_own" ON organizer_members FOR SELECT TO authenticated USING (
  user_id = auth.uid()
);
-- No INSERT/UPDATE/DELETE policy at all, for anyone — every write goes
-- through a SECURITY DEFINER RPC below (invite/respond/visibility/
-- remove), each enforcing its own real authorization. A direct table
-- write from any role is a plain RLS rejection.

-- ---------------------------------------------------------------------------
-- invite_organizer_member() — owner/co-owner only. Looks the invitee up by
-- their real handle (never an email/phone — this app's own public
-- identity), so the owner can only ever invite a real Banbe account they
-- can already see the public handle of.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.invite_organizer_member(
  p_organizer_id text,
  p_handle text,
  p_public_role text DEFAULT 'Thành viên'
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_invitee profiles%ROWTYPE;
  v_role text := left(trim(coalesce(p_public_role, '')), 40);
  v_existing organizer_members%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF v_role = '' THEN v_role := 'Thành viên'; END IF;

  IF NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = p_organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  SELECT * INTO v_invitee FROM profiles WHERE lower(handle) = lower(trim(p_handle));
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'USER_NOT_FOUND'); END IF;

  IF EXISTS (SELECT 1 FROM organizers o WHERE o.id = p_organizer_id AND (o.owner_id = v_invitee.id OR o.user_id = v_invitee.id)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'CANNOT_INVITE_OWNER');
  END IF;

  SELECT * INTO v_existing FROM organizer_members WHERE organizer_id = p_organizer_id AND user_id = v_invitee.id FOR UPDATE;
  IF FOUND AND v_existing.status IN ('invited', 'accepted') THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_MEMBER');
  END IF;

  IF FOUND THEN
    -- Re-inviting a previously removed/declined member — a clean invite,
    -- never resurrecting their old public_visible choice.
    UPDATE organizer_members SET
      status = 'invited', public_role = v_role, public_visible = false,
      invited_by = auth.uid(), invited_at = now(), responded_at = NULL, joined_at = NULL, removed_at = NULL
    WHERE id = v_existing.id;
  ELSE
    INSERT INTO organizer_members (organizer_id, user_id, public_role, invited_by)
    VALUES (p_organizer_id, v_invitee.id, v_role, auth.uid());
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (
    v_invitee.id, 'organizer_invite',
    'Lời mời tham gia Team',
    'Bạn được mời tham gia đội ngũ tổ chức sự kiện.',
    jsonb_build_object('organizer_id', p_organizer_id)
  );

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.invite_organizer_member(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invite_organizer_member(text, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- respond_to_organizer_invite() — invitee only. Accepting NEVER sets
-- public_visible; that stays a separate, later, member-only choice.
-- ---------------------------------------------------------------------------
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
REVOKE ALL ON FUNCTION public.respond_to_organizer_invite(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.respond_to_organizer_invite(uuid, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- set_organizer_member_visibility() — the member's OWN switch, and the
-- ONLY way `public_visible` can ever become true. Only once accepted.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_organizer_member_visibility(
  p_membership_id uuid,
  p_visible boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row organizer_members%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT * INTO v_row FROM organizer_members WHERE id = p_membership_id AND user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND'); END IF;
  IF v_row.status <> 'accepted' THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_A_MEMBER'); END IF;

  UPDATE organizer_members SET public_visible = p_visible WHERE id = p_membership_id;
  RETURN jsonb_build_object('success', true, 'public_visible', p_visible);
END;
$$;
REVOKE ALL ON FUNCTION public.set_organizer_member_visibility(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_organizer_member_visibility(uuid, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- remove_organizer_member() — owner/co-owner only. Always forces
-- public_visible back to false — the owner can revoke, never publish.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.remove_organizer_member(p_membership_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row organizer_members%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT om.* INTO v_row FROM organizer_members om
    JOIN organizers o ON o.id = om.organizer_id
    WHERE om.id = p_membership_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;

  UPDATE organizer_members SET status = 'removed', public_visible = false, removed_at = now() WHERE id = p_membership_id;
  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.remove_organizer_member(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.remove_organizer_member(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- get_organizer_team() — the ONE public/anon read path. Only accepted AND
-- public_visible rows, and only fields meant for public display: never
-- email/phone/any private column, never a hidden/pending member, never a
-- roster count that would let a caller infer how many are hidden.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_organizer_team(p_organizer_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM organizers WHERE id = p_organizer_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;
  RETURN jsonb_build_object(
    'success', true,
    'organizer_id', p_organizer_id,
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
REVOKE ALL ON FUNCTION public.get_organizer_team(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_organizer_team(text) TO authenticated, anon;
