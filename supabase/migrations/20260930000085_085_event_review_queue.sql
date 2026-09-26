-- Migration: real event submission -> admin review -> publish.
--
-- ROOT CAUSE (confirmed by reading create_event_draft(), migration 012, and
-- a live read-only query of `events`): CreateEvent.jsx/OnboardingViews.swift
-- both already call a REAL RPC (create_event_draft) that inserts a REAL
-- events row, owned by the caller's own organizer, with real validation
-- (name non-empty, capacity >= 1, role must be organizer/admin). This was
-- never a fake "Đã gửi" local flag. The actual bug: that RPC inserts with
-- `status = 'live', visibility = 'public'` UNCONDITIONALLY — the event is
-- live and publicly bookable the instant Submit is tapped. Nothing ever
-- reads or writes `status = 'review'` anywhere in this schema despite the
-- enum already having that value (migration 001) and despite both clients'
-- own copy promising a review ("Gửi để duyệt ▪︎ banbe duyệt trong 48 giờ").
-- There was no review queue to build a UI for — the gate itself never
-- existed server-side.
--
-- This migration adds the actual gate: create_event_draft() now inserts
-- 'review', not 'live'. Approval/rejection happens through a new
-- SECURITY DEFINER RPC (admin_review_event), never a raw client UPDATE, so
-- "authenticated platform admin" is enforced server-side regardless of
-- what UI does or doesn't hide. events_select_public (migration 001/084)
-- already keeps a 'review'/'draft' row owner-only for anyone but the
-- organizer who owns it — no visibility change needed there; the only new
-- policy is admin read access across EVERY organizer's pending rows.

-- 1. Review bookkeeping columns.
ALTER TABLE events ADD COLUMN IF NOT EXISTS submitted_at timestamptz;
ALTER TABLE events ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;
ALTER TABLE events ADD COLUMN IF NOT EXISTS reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE events ADD COLUMN IF NOT EXISTS rejection_reason text DEFAULT '';

-- 2. Admin read access to every organizer's pending (or any-status) event —
-- same is_platform_admin() bypass bookings_select_admin already uses
-- (migration 026). events_select_public (084) is untouched: an admin who
-- ISN'T also the owning organizer would otherwise see nothing for a
-- 'review'/'draft' row, same as any other non-owner.
DROP POLICY IF EXISTS "events_select_admin" ON events;
CREATE POLICY "events_select_admin" ON events FOR SELECT TO authenticated USING (
  public.is_platform_admin()
);

-- 3. create_event_draft() — same signature/validation as migration 012's
-- version, only the final status changes (and starts_at now actually gets
-- set: it was silently left NULL before, which would have kept any
-- newly-approved event invisible to every starts_at-filtered discovery
-- surface — Home's "Cuối tuần này", MapExplore — even once truly live).
CREATE OR REPLACE FUNCTION create_event_draft(
  p_name text, p_category text, p_description text, p_location text,
  p_event_date date, p_event_time time, p_price_vnd bigint, p_capacity int,
  p_organizer_name text, p_instagram text DEFAULT '', p_about text DEFAULT ''
) RETURNS events LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer organizers%ROWTYPE;
  v_event events%ROWTYPE;
  v_org_id text;
  v_event_id text;
  v_role text;
  v_starts_at timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 OR p_capacity IS NULL OR p_capacity < 1 THEN RAISE EXCEPTION 'INVALID_EVENT'; END IF;

  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role IS NULL OR v_role NOT IN ('organizer', 'admin') THEN
    RAISE EXCEPTION 'FORBIDDEN: Only organizers can create events.';
  END IF;

  SELECT * INTO v_organizer FROM organizers WHERE owner_id = auth.uid() OR user_id = auth.uid() ORDER BY created_at LIMIT 1;
  IF NOT FOUND THEN
    v_org_id := 'org_' || substr(md5(gen_random_uuid()::text), 1, 8);
    INSERT INTO organizers(id, owner_id, user_id, name, ig_handle, instagram, bio, about)
    VALUES (v_org_id, auth.uid(), auth.uid(), COALESCE(NULLIF(trim(p_organizer_name), ''), 'Organizer'), p_instagram, p_instagram, p_about, p_about)
    RETURNING * INTO v_organizer;
  ELSE
    UPDATE organizers SET name = COALESCE(NULLIF(trim(p_organizer_name), ''), name), instagram = COALESCE(p_instagram, instagram), about = COALESCE(p_about, about) WHERE id = v_organizer.id;
  END IF;

  v_event_id := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(md5(gen_random_uuid()::text), 1, 6);
  -- p_event_date/p_event_time are both optional free-text-parsed fields on
  -- the client (CreateEvent.jsx/OnboardingViews.swift) — only combine them
  -- when both actually parsed, same "leave it null rather than guess" rule
  -- the rest of this schema already follows for partial input.
  v_starts_at := CASE WHEN p_event_date IS NOT NULL AND p_event_time IS NOT NULL
                       THEN (p_event_date + p_event_time) AT TIME ZONE 'Asia/Ho_Chi_Minh'
                       ELSE NULL END;

  INSERT INTO events(id, key, slug, organizer_id, name, category, cat_key, cat_label, description, price_vnd, price_cents, capacity, seats_remaining, area, event_date, event_time, starts_at, status, approval, visibility, submitted_at)
  VALUES (
    v_event_id,
    v_event_id,
    v_event_id,
    v_organizer.id,
    trim(p_name),
    p_category,
    p_category,
    p_category,
    COALESCE(p_description, ''),
    COALESCE(p_price_vnd, 0),
    COALESCE(p_price_vnd, 0) * 100,
    p_capacity,
    p_capacity,
    COALESCE(p_location, ''),
    p_event_date,
    p_event_time,
    v_starts_at,
    -- THE FIX: was 'live' (migration 012) — instantly published, no review
    -- ever happened despite the UI's own promise. Real events discovery
    -- (Home, EventList, MapExplore, the weekend section) already excludes
    -- non-'live' rows by construction, so nothing else has to change to
    -- keep a pending submission out of the public feed.
    'review',
    'host_approves',
    'public',
    now()
  )
  RETURNING * INTO v_event;

  RETURN v_event;
END;
$$;
REVOKE EXECUTE ON FUNCTION create_event_draft FROM anon;
GRANT EXECUTE ON FUNCTION create_event_draft TO authenticated;

-- 4. The actual review decision. SECURITY DEFINER so "authenticated
-- platform admin" is enforced HERE, not merely by which screen the client
-- shows — a direct RPC call from a non-admin session gets ADMIN_ONLY, same
-- shape resolve_dispute() already returns for its own admin gate.
--
-- Race/duplicate-decision guard: `SELECT ... FOR UPDATE` takes a row lock,
-- and the `status <> 'review'` check runs AFTER acquiring it — so if two
-- admins (or one admin double-tapping) call this concurrently for the same
-- event, whichever transaction commits first flips status away from
-- 'review', and the second transaction's own check (now running against
-- the post-commit row) sees NOT_PENDING and fails cleanly instead of
-- silently reprocessing an already-decided event.
CREATE OR REPLACE FUNCTION public.admin_review_event(
  p_event_id text, p_approve boolean, p_reason text DEFAULT ''
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_event events%ROWTYPE;
  v_reason text := left(trim(COALESCE(p_reason, '')), 500);
  v_owner_id uuid;
  v_now timestamptz := now();
BEGIN
  IF NOT public.is_platform_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADMIN_ONLY');
  END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;
  IF v_event.status <> 'review' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_PENDING', 'status', v_event.status);
  END IF;
  IF NOT p_approve AND length(v_reason) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'REASON_REQUIRED');
  END IF;

  SELECT COALESCE(o.owner_id, o.user_id) INTO v_owner_id
  FROM organizers o WHERE o.id = v_event.organizer_id;

  IF p_approve THEN
    UPDATE events SET
      status = 'live', reviewed_by = auth.uid(), reviewed_at = v_now, rejection_reason = ''
    WHERE id = p_event_id;
    IF v_owner_id IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (v_owner_id, 'event_approved', 'Sự kiện đã được duyệt',
              'Sự kiện "' || v_event.name || '" đã được banbe duyệt và hiện đang hiển thị công khai.',
              jsonb_build_object('event_id', p_event_id));
    END IF;
  ELSE
    -- Back to 'draft', not left at 'review' — this is what makes the event
    -- editable/resubmittable (resubmit_event_for_review below only accepts
    -- a 'draft' row), and what events_select_public already treats as
    -- owner-only, same as before it was ever submitted.
    UPDATE events SET
      status = 'draft', reviewed_by = auth.uid(), reviewed_at = v_now, rejection_reason = v_reason
    WHERE id = p_event_id;
    IF v_owner_id IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (v_owner_id, 'event_rejected', 'Sự kiện cần chỉnh sửa',
              'Sự kiện "' || v_event.name || '" chưa được duyệt: ' || v_reason,
              jsonb_build_object('event_id', p_event_id, 'reason', v_reason));
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'status', CASE WHEN p_approve THEN 'live' ELSE 'draft' END);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_review_event(text, boolean, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_review_event(text, boolean, text) TO authenticated;

-- 5. Host correction + resubmission — only ever moves a 'draft' row (i.e.
-- one this account owns AND that has already been through create_event_
-- draft/a rejection, never a brand-new client-side-only draft) back to
-- 'review'. Ownership check mirrors events_update_own's own USING clause.
CREATE OR REPLACE FUNCTION public.resubmit_event_for_review(
  p_event_id text, p_name text, p_category text, p_description text, p_location text,
  p_event_date date, p_event_time time, p_price_vnd bigint, p_capacity int
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_event events%ROWTYPE;
  v_starts_at timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 OR p_capacity IS NULL OR p_capacity < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_EVENT');
  END IF;

  SELECT e.* INTO v_event FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;
  IF v_event.status <> 'draft' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_EDITABLE', 'status', v_event.status);
  END IF;

  v_starts_at := CASE WHEN p_event_date IS NOT NULL AND p_event_time IS NOT NULL
                       THEN (p_event_date + p_event_time) AT TIME ZONE 'Asia/Ho_Chi_Minh'
                       ELSE NULL END;

  UPDATE events SET
    name = trim(p_name), category = p_category, cat_key = p_category, cat_label = p_category,
    description = COALESCE(p_description, ''), area = COALESCE(p_location, ''),
    event_date = p_event_date, event_time = p_event_time, starts_at = v_starts_at,
    price_vnd = COALESCE(p_price_vnd, 0), price_cents = COALESCE(p_price_vnd, 0) * 100,
    capacity = p_capacity, seats_remaining = p_capacity,
    status = 'review', submitted_at = now(), reviewed_at = NULL, reviewed_by = NULL, rejection_reason = ''
  WHERE id = p_event_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.resubmit_event_for_review(text, text, text, text, text, date, time, bigint, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.resubmit_event_for_review(text, text, text, text, text, date, time, bigint, int) TO authenticated;
