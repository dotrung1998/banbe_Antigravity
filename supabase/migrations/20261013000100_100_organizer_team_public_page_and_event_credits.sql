-- 100: Organizer Team pass (2026-09-27), Stage 2 — clickable Team + member
-- cards. Two real additions:
--
--   1. event_credits — "did this member REALLY help organize this event."
--      Never derived from ticket attendance/bookings/check-ins (this
--      ticket's own explicit rule): only an owner's explicit assignment
--      that the member themselves has explicitly ACCEPTED counts as a
--      real credit anywhere public.
--   2. get_public_profile() (091/096) gains `team_badges` (which real,
--      accepted, PUBLIC memberships this profile currently has) and
--      `credited_events` (which real, accepted event credits this profile
--      currently has, and ONLY for an organizer where this same profile's
--      own membership is still public_visible = true — hiding Team
--      association hides event credits in the same instant, since both
--      read that same live flag rather than a snapshot).

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_credit_status') THEN
    CREATE TYPE event_credit_status AS ENUM ('invited', 'accepted', 'declined');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS event_credits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  organizer_id text NOT NULL REFERENCES organizers(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status event_credit_status NOT NULL DEFAULT 'invited',
  assigned_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,
  UNIQUE (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_event_credits_event ON event_credits(event_id);
CREATE INDEX IF NOT EXISTS idx_event_credits_user ON event_credits(user_id);

ALTER TABLE event_credits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "event_credits_select_owner" ON event_credits;
CREATE POLICY "event_credits_select_owner" ON event_credits FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM organizers o WHERE o.id = event_credits.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);
DROP POLICY IF EXISTS "event_credits_select_own" ON event_credits;
CREATE POLICY "event_credits_select_own" ON event_credits FOR SELECT TO authenticated USING (
  user_id = auth.uid()
);
-- No INSERT/UPDATE/DELETE policy — assign_event_credit()/
-- respond_to_event_credit() (SECURITY DEFINER) are the only writers.

-- ---------------------------------------------------------------------------
-- assign_event_credit() — owner/co-owner only, and only for a real
-- ACCEPTED member of that same organizer (never a stranger, never an
-- invited-but-not-accepted one, never the owner "crediting" themselves
-- through this path — the owner's own name never needed a credit row to
-- begin with).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assign_event_credit(
  p_event_id text,
  p_user_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer_id text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;

  SELECT e.organizer_id INTO v_organizer_id FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid());
  IF v_organizer_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;

  IF NOT EXISTS (
    SELECT 1 FROM organizer_members om WHERE om.organizer_id = v_organizer_id AND om.user_id = p_user_id AND om.status = 'accepted'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_A_MEMBER');
  END IF;

  IF EXISTS (SELECT 1 FROM event_credits WHERE event_id = p_event_id AND user_id = p_user_id AND status IN ('invited', 'accepted')) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_CREDITED');
  END IF;

  INSERT INTO event_credits (event_id, organizer_id, user_id, assigned_by)
  VALUES (p_event_id, v_organizer_id, p_user_id, auth.uid())
  ON CONFLICT (event_id, user_id) DO UPDATE SET
    status = 'invited', assigned_by = auth.uid(), created_at = now(), responded_at = NULL;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (
    p_user_id, 'event_credit_invite',
    'Ghi nhận đóng góp sự kiện',
    'Bạn được ghi nhận là người tổ chức cho một sự kiện.',
    jsonb_build_object('event_id', p_event_id)
  );

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.assign_event_credit(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_event_credit(text, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.respond_to_event_credit(
  p_credit_id uuid,
  p_accept boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row event_credits%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT * INTO v_row FROM event_credits WHERE id = p_credit_id AND user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND'); END IF;
  IF v_row.status <> 'invited' THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_PENDING'); END IF;

  UPDATE event_credits SET
    status = (CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END)::event_credit_status,
    responded_at = now()
  WHERE id = p_credit_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.respond_to_event_credit(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.respond_to_event_credit(uuid, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- get_public_profile() — adds `team_badges` and `credited_events`, both
-- read-only public data, both gated on the SAME live public_visible flag
-- (never a cached copy), so hiding Team association hides both in the
-- same instant. Everything else about this function (091/096) unchanged.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_public_profile(p_handle text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_organizer_id text;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE lower(handle) = lower(trim(p_handle));
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  SELECT o.id INTO v_organizer_id FROM organizers o
  WHERE o.owner_id = v_profile.id OR o.user_id = v_profile.id
  ORDER BY o.created_at ASC LIMIT 1;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_profile.id,
    'handle', v_profile.handle,
    'display_name', v_profile.display_name,
    'avatar_url', v_profile.avatar_url,
    'bio', v_profile.bio,
    'city', v_profile.city,
    'interests', v_profile.interests,
    'profile_theme', v_profile.profile_theme,
    'is_organizer', v_organizer_id IS NOT NULL,
    'organizer_mode', v_profile.role IN ('organizer', 'admin'),
    'organizer', CASE WHEN v_organizer_id IS NULL THEN NULL ELSE (
      SELECT jsonb_build_object(
        'id', o.id, 'name', o.name, 'verified', o.verified,
        'event_count', (
          SELECT count(*) FROM events e
          WHERE e.organizer_id = o.id AND e.status IN ('live', 'ended')
        ),
        'hosting_since_year', (
          SELECT EXTRACT(YEAR FROM min(e.starts_at))::int FROM events e
          WHERE e.organizer_id = o.id AND e.status IN ('live', 'ended') AND e.starts_at IS NOT NULL
        ),
        'follower_count', (SELECT count(*) FROM follows f WHERE f.organizer_id = o.id),
        'following', auth.uid() IS NOT NULL AND EXISTS (
          SELECT 1 FROM follows f WHERE f.organizer_id = o.id AND f.user_id = auth.uid()
        )
      )
      FROM organizers o WHERE o.id = v_organizer_id
    ) END,
    'team_badges', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'organizer_id', om.organizer_id, 'organizer_name', o.name, 'public_role', om.public_role
      )), '[]'::jsonb)
      FROM organizer_members om JOIN organizers o ON o.id = om.organizer_id
      WHERE om.user_id = v_profile.id AND om.status = 'accepted' AND om.public_visible = true
    ),
    'credited_events', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'event_id', e.id, 'event_name', e.name, 'organizer_id', ec.organizer_id, 'organizer_name', o.name
      ) ORDER BY e.starts_at DESC NULLS LAST), '[]'::jsonb)
      FROM event_credits ec
      JOIN events e ON e.id = ec.event_id
      JOIN organizers o ON o.id = ec.organizer_id
      JOIN organizer_members om ON om.organizer_id = ec.organizer_id AND om.user_id = ec.user_id
      WHERE ec.user_id = v_profile.id AND ec.status = 'accepted'
        AND om.status = 'accepted' AND om.public_visible = true
        AND e.status IN ('live', 'ended')
    )
  );
END;
$$;
