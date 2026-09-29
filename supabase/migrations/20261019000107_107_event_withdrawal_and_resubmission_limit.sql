-- 107: Owner-only withdrawal of a PENDING submission + a server-enforced
-- resubmission rate limit, plus a real audit trail for status transitions.
--
-- Ground truth (confirmed by reading migration 085/088/089/094/105/106, not
-- guessed): there is NO withdrawal path anywhere in this schema today —
-- `admin_review_event` is the only RPC that ever moves an event OFF
-- 'review', and only an admin can call it. There is also no per-event audit
-- table: `events.reviewed_at`/`reviewed_by`/`rejection_reason` (085) are a
-- single overwritten snapshot of the MOST RECENT decision, not a history.
--
-- This migration is purely ADDITIVE — no historical migration is edited,
-- no RLS is weakened, no existing booking/payment flow is touched.
--
-- Product-policy call made here, per this ticket's own "you're authorized to
-- make reasonable calls" instruction (documented, not silently assumed):
-- withdrawal reuses the EXISTING 'draft' status (already owner-only-visible
-- via events_select_public/084, already what admin_review_event's own
-- rejection branch uses) rather than adding a new `event_status` enum
-- value. `ALTER TYPE ... ADD VALUE` cannot safely be used and then
-- referenced inside the SAME transaction/migration on every Postgres
-- version this project's migration history has otherwise been careful
-- about (no prior migration in this repo does it), so a new enum value
-- would need its own migration before it could be used at all — reusing
-- 'draft' avoids that entirely while staying semantically sound: a
-- withdrawn event is, exactly like a rejected one, "not currently pending,
-- editable, resubmittable, and not publicly visible." What distinguishes a
-- withdrawal from a rejection is recorded explicitly below (`event_status_
-- history.action = 'withdraw'` + `events.withdrawal_reason`), never
-- conflated with `rejection_reason`/an admin decision.

-- 1. Real audit trail — every status transition this migration's own RPCs
-- (and, going forward, admin_review_event) can produce, as an
-- append-only log. Owner + admin can read a given event's own history;
-- nobody can write it directly (SECURITY DEFINER RPCs only).
CREATE TABLE IF NOT EXISTS event_status_history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_id text NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  action text NOT NULL CHECK (action IN ('submit', 'approve', 'reject', 'withdraw', 'resubmit')),
  from_status event_status,
  to_status event_status NOT NULL,
  reason text NOT NULL DEFAULT '',
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS event_status_history_event_id_idx ON event_status_history(event_id, created_at DESC);

ALTER TABLE event_status_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "event_status_history_select_owner" ON event_status_history;
CREATE POLICY "event_status_history_select_owner" ON event_status_history FOR SELECT TO authenticated USING (
  public.is_platform_admin()
  OR EXISTS (
    SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = event_status_history.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);
-- No INSERT/UPDATE/DELETE policy at all — every write goes through a
-- SECURITY DEFINER RPC below, never a direct client write.

-- 2. Withdrawal bookkeeping + rolling-24h resubmission-limit bookkeeping.
ALTER TABLE events ADD COLUMN IF NOT EXISTS withdrawal_reason text NOT NULL DEFAULT '';
ALTER TABLE events ADD COLUMN IF NOT EXISTS withdrawn_at timestamptz;
-- `resubmission_count`/`resubmission_window_start` together implement the
-- rolling-24h window: the count resets to 0 and the window restarts the
-- first time a resubmission happens more than 24h after the window
-- started. This is a banbe PRODUCT POLICY choice (2 successful
-- resubmissions per event per rolling 24h), NOT a Vietnamese legal
-- requirement and NOT a Ticketbox-documented quota — never describe it as
-- either in user-facing copy or code comments (see this migration's own
-- RPC below and both clients' own surfacing code).
ALTER TABLE events ADD COLUMN IF NOT EXISTS resubmission_count int NOT NULL DEFAULT 0;
ALTER TABLE events ADD COLUMN IF NOT EXISTS resubmission_window_start timestamptz;

COMMENT ON COLUMN events.resubmission_count IS
  'Successful resubmissions (resubmit_event_for_review calls that actually '
  'committed) within the CURRENT rolling 24h window starting at '
  'resubmission_window_start. A banbe product policy cap (2 per rolling '
  '24h), not a legal or third-party (e.g. Ticketbox) requirement.';

-- 3. withdraw_event_submission — owner-only, requires a non-empty reason,
-- only ever moves a 'review' row to 'draft' (never touches a 'live'/
-- 'cancelled'/'ended' row — withdrawing a already-approved, already-public
-- event is a different, deliberately out-of-scope action this ticket did
-- not ask for). Preserves the row (never deletes/recreates), records the
-- reason, and does NOT touch resubmission_count/resubmission_window_start
-- — per the ticket's own explicit rule, withdrawal itself never counts
-- against the resubmission limit.
CREATE OR REPLACE FUNCTION public.withdraw_event_submission(
  p_event_id text, p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_event events%ROWTYPE;
  v_reason text := trim(COALESCE(p_reason, ''));
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF length(v_reason) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'REASON_REQUIRED');
  END IF;
  IF length(v_reason) > 500 THEN v_reason := left(v_reason, 500); END IF;

  SELECT e.* INTO v_event FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;
  IF v_event.status <> 'review' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_PENDING', 'status', v_event.status);
  END IF;

  UPDATE events SET
    status = 'draft',
    withdrawal_reason = v_reason,
    withdrawn_at = now(),
    reviewed_at = NULL, reviewed_by = NULL, rejection_reason = ''
  WHERE id = p_event_id;

  INSERT INTO event_status_history(event_id, action, from_status, to_status, reason, actor_id)
  VALUES (p_event_id, 'withdraw', v_event.status, 'draft', v_reason, auth.uid());

  RETURN jsonb_build_object('success', true, 'status', 'draft');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.withdraw_event_submission(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.withdraw_event_submission(text, text) TO authenticated;

-- 4. get_event_resubmission_status — read-only helper both clients call to
-- surface "N attempts left" / "next eligible at" WITHOUT racing the actual
-- resubmit call (this never locks the row). Owner/admin only, matching the
-- history table's own read policy.
CREATE OR REPLACE FUNCTION public.get_event_resubmission_status(
  p_event_id text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_event events%ROWTYPE;
  v_window_active boolean;
  v_remaining int;
  v_next_eligible timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;

  SELECT e.* INTO v_event FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid());
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;

  v_window_active := v_event.resubmission_window_start IS NOT NULL
                      AND now() - v_event.resubmission_window_start < interval '24 hours';
  v_remaining := CASE WHEN v_window_active THEN GREATEST(0, 2 - v_event.resubmission_count) ELSE 2 END;
  v_next_eligible := CASE WHEN v_window_active AND v_remaining = 0
                          THEN v_event.resubmission_window_start + interval '24 hours'
                          ELSE NULL END;

  RETURN jsonb_build_object(
    'success', true,
    'remaining_attempts', v_remaining,
    'next_eligible_at', v_next_eligible,
    'status', v_event.status
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_event_resubmission_status(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_event_resubmission_status(text) TO authenticated;

-- 5. resubmit_event_for_review — atomic 2-per-rolling-24h enforcement,
-- added on top of migration 106's own signature/behavior (unchanged
-- otherwise: same params, same address/coordinate validation, same
-- ownership + 'draft'-only gate). `SELECT ... FOR UPDATE` (already present
-- since 085) makes the read-check-increment atomic under concurrency: two
-- overlapping calls for the same event serialize on this row lock, so the
-- second one always sees the FIRST call's already-committed count/window,
-- never a stale pre-increment value.
CREATE OR REPLACE FUNCTION public.resubmit_event_for_review(
  p_event_id text, p_name text, p_category text, p_description text, p_location text,
  p_event_date date, p_event_time time, p_price_vnd bigint, p_capacity int,
  p_cover_image text DEFAULT '',
  p_included_items jsonb DEFAULT '[]'::jsonb,
  p_intro text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_address_line text DEFAULT NULL,
  p_city text DEFAULT NULL,
  p_postal_code text DEFAULT NULL,
  p_address_verified boolean DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_event events%ROWTYPE;
  v_starts_at timestamptz;
  v_cat_key text;
  v_cat_label text;
  v_category text;
  v_item jsonb;
  v_label text;
  v_detail text;
  v_included_labels text[] := ARRAY[]::text[];
  v_included_text text := '';
  v_window_start timestamptz;
  v_count int;
  v_next_eligible timestamptz;
  v_address_verified boolean;
  v_address_line text;
  v_city text;
  v_postal_code text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 OR p_capacity IS NULL OR p_capacity < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_EVENT');
  END IF;
  IF p_intro IS NOT NULL AND length(p_intro) > 4000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_INTRO');
  END IF;
  IF (p_lat IS NOT NULL AND (p_lat < -90 OR p_lat > 90)) OR (p_lng IS NOT NULL AND (p_lng < -180 OR p_lng > 180)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_COORDINATES');
  END IF;
  IF p_lat IS NOT NULL AND p_lng IS NOT NULL
     AND (p_lat < 8 OR p_lat > 24 OR p_lng < 102 OR p_lng > 110) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADDRESS_NOT_PLAUSIBLE');
  END IF;

  -- Row lock FIRST, before any counter logic — this is what makes the
  -- check-and-increment below atomic under concurrent calls.
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

  -- Rolling-24h window bookkeeping — a banbe product policy (2 successful
  -- resubmissions per event per rolling 24h), not a legal/third-party
  -- quota. The initial create_event_draft submission never touches these
  -- columns at all, so it never counts; only a resubmission that reaches
  -- this point (i.e. actually commits) increments the counter.
  IF v_event.resubmission_window_start IS NULL
     OR now() - v_event.resubmission_window_start >= interval '24 hours' THEN
    v_window_start := now();
    v_count := 0;
  ELSE
    v_window_start := v_event.resubmission_window_start;
    v_count := v_event.resubmission_count;
  END IF;

  IF v_count >= 2 THEN
    v_next_eligible := v_window_start + interval '24 hours';
    RETURN jsonb_build_object(
      'success', false, 'error', 'RESUBMISSION_LIMIT_REACHED',
      'remaining_attempts', 0, 'next_eligible_at', v_next_eligible
    );
  END IF;

  -- Address fields: NULL means "caller didn't re-touch this," so the
  -- already-verified value on the row carries over unchanged — same
  -- COALESCE-to-existing-row pattern migration 106 introduced for exactly
  -- this "old caller/unchanged address" case, restored here verbatim
  -- (this migration only ADDS the resubmission-limit/history logic below,
  -- it does not relax 106's own address-completeness enforcement).
  v_address_verified := COALESCE(p_address_verified, v_event.address_verified);
  v_address_line := trim(COALESCE(p_address_line, v_event.address_line));
  v_city := trim(COALESCE(p_city, v_event.city));
  v_postal_code := trim(COALESCE(p_postal_code, v_event.postal_code));

  IF v_address_verified THEN
    IF length(v_address_line) = 0
       OR length(trim(COALESCE(p_location, v_event.area))) = 0
       OR length(v_city) = 0
       OR COALESCE(p_lat, v_event.lat) IS NULL OR COALESCE(p_lng, v_event.lng) IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'ADDRESS_NOT_VERIFIED');
    END IF;
  END IF;

  v_starts_at := CASE WHEN p_event_date IS NOT NULL AND p_event_time IS NOT NULL
                       THEN (p_event_date + p_event_time) AT TIME ZONE 'Asia/Ho_Chi_Minh'
                       ELSE NULL END;
  IF v_starts_at IS NOT NULL AND v_starts_at < (now() - interval '5 minutes') THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAST_EVENT_NOT_ALLOWED');
  END IF;

  SELECT cat_key, cat_label, category INTO v_cat_key, v_cat_label, v_category
  FROM public.normalize_event_category(p_category);

  IF p_included_items IS NOT NULL AND jsonb_typeof(p_included_items) = 'array' THEN
    IF jsonb_array_length(p_included_items) > 3 THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_INCLUDED_ITEMS');
    END IF;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_included_items) LOOP
      v_label := trim(COALESCE(v_item->>'label', ''));
      v_detail := trim(COALESCE(v_item->>'detail', ''));
      IF length(v_label) = 0 OR length(v_label) > 60 THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_INCLUDED_LABEL');
      END IF;
      IF length(v_detail) > 300 THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_INCLUDED_DETAIL');
      END IF;
      v_included_labels := array_append(v_included_labels, v_label);
    END LOOP;
    v_included_text := array_to_string(v_included_labels, ' ▪︎ ');
  END IF;

  UPDATE events SET
    name = trim(p_name), category = v_category, cat_key = v_cat_key, cat_label = v_cat_label,
    description = COALESCE(p_description, ''), area = trim(COALESCE(p_location, v_event.area)),
    event_date = p_event_date, event_time = p_event_time, starts_at = v_starts_at,
    price_vnd = COALESCE(p_price_vnd, 0), price_cents = COALESCE(p_price_vnd, 0) * 100,
    capacity = p_capacity, seats_remaining = p_capacity,
    cover_image = CASE WHEN length(trim(COALESCE(p_cover_image, ''))) > 0 THEN trim(p_cover_image) ELSE cover_image END,
    included = CASE WHEN length(v_included_text) > 0 THEN v_included_text ELSE included END,
    included_items = COALESCE(p_included_items, included_items),
    intro = COALESCE(p_intro, intro),
    lat = COALESCE(p_lat, v_event.lat), lng = COALESCE(p_lng, v_event.lng),
    address_line = v_address_line, city = v_city, postal_code = v_postal_code, address_verified = v_address_verified,
    status = 'review', submitted_at = now(), reviewed_at = NULL, reviewed_by = NULL, rejection_reason = '',
    withdrawal_reason = '', withdrawn_at = NULL,
    resubmission_count = v_count + 1, resubmission_window_start = v_window_start
  WHERE id = p_event_id;

  INSERT INTO event_status_history(event_id, action, from_status, to_status, reason, actor_id)
  VALUES (p_event_id, 'resubmit', v_event.status, 'review', '', auth.uid());

  RETURN jsonb_build_object(
    'success', true,
    'remaining_attempts', 2 - (v_count + 1),
    'next_eligible_at', CASE WHEN (v_count + 1) >= 2 THEN v_window_start + interval '24 hours' ELSE NULL END
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.resubmit_event_for_review(
  text, text, text, text, text, date, time, bigint, int, text, jsonb, text,
  double precision, double precision, text, text, text, boolean
) FROM anon;
GRANT EXECUTE ON FUNCTION public.resubmit_event_for_review(
  text, text, text, text, text, date, time, bigint, int, text, jsonb, text,
  double precision, double precision, text, text, text, boolean
) TO authenticated;

-- 6. Duplicate-new-row guard — a client cannot route around the
-- resubmission limit by creating a BRAND NEW event row for the same
-- logical event instead of using resubmit_event_for_review. Dedupe by
-- owner + trimmed/lowercased name + event_date, only against a row that is
-- CURRENTLY pending or awaiting-fix (review/draft with a submitted_at in
-- the last 24h) — an owner is still free to create a genuinely new,
-- differently-named/dated event at any time; this only blocks recreating
-- the SAME one to dodge the limit.
CREATE OR REPLACE FUNCTION create_event_draft(
  p_name text, p_category text, p_description text, p_location text,
  p_event_date date, p_event_time time, p_price_vnd bigint, p_capacity int,
  p_organizer_name text, p_instagram text DEFAULT '', p_about text DEFAULT '',
  p_cover_image text DEFAULT '',
  p_included_items jsonb DEFAULT '[]'::jsonb,
  p_intro text DEFAULT '',
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_address_line text DEFAULT '',
  p_city text DEFAULT '',
  p_postal_code text DEFAULT '',
  p_address_verified boolean DEFAULT false
) RETURNS events LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer organizers%ROWTYPE;
  v_event events%ROWTYPE;
  v_org_id text;
  v_event_id text;
  v_role text;
  v_starts_at timestamptz;
  v_cat_key text;
  v_cat_label text;
  v_category text;
  v_item jsonb;
  v_label text;
  v_detail text;
  v_included_labels text[] := ARRAY[]::text[];
  v_included_text text := '';
  v_dup_id text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 OR p_capacity IS NULL OR p_capacity < 1 THEN
    RAISE EXCEPTION 'INVALID_EVENT';
  END IF;
  IF p_intro IS NOT NULL AND length(p_intro) > 4000 THEN
    RAISE EXCEPTION 'INVALID_INTRO: Max 4000 characters';
  END IF;
  IF (p_lat IS NOT NULL AND (p_lat < -90 OR p_lat > 90)) OR (p_lng IS NOT NULL AND (p_lng < -180 OR p_lng > 180)) THEN
    RAISE EXCEPTION 'INVALID_COORDINATES';
  END IF;
  IF p_lat IS NOT NULL AND p_lng IS NOT NULL
     AND (p_lat < 8 OR p_lat > 24 OR p_lng < 102 OR p_lng > 110) THEN
    RAISE EXCEPTION 'ADDRESS_NOT_PLAUSIBLE: Coordinates fall outside Vietnam';
  END IF;
  IF length(COALESCE(p_address_line, '')) > 200 THEN
    RAISE EXCEPTION 'INVALID_ADDRESS_LINE: Max 200 characters';
  END IF;
  IF length(COALESCE(p_city, '')) > 100 THEN
    RAISE EXCEPTION 'INVALID_CITY: Max 100 characters';
  END IF;
  IF length(COALESCE(p_postal_code, '')) > 20 THEN
    RAISE EXCEPTION 'INVALID_POSTAL_CODE: Max 20 characters';
  END IF;
  IF COALESCE(p_address_verified, false) THEN
    IF length(trim(COALESCE(p_address_line, ''))) = 0
       OR length(trim(COALESCE(p_location, ''))) = 0
       OR length(trim(COALESCE(p_city, ''))) = 0
       OR p_lat IS NULL OR p_lng IS NULL THEN
      RAISE EXCEPTION 'ADDRESS_NOT_VERIFIED: address_verified was true but the address is incomplete';
    END IF;
  END IF;

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
    UPDATE organizers SET
      name = COALESCE(NULLIF(trim(p_organizer_name), ''), name),
      instagram = COALESCE(p_instagram, instagram),
      about = COALESCE(p_about, about)
    WHERE id = v_organizer.id;

    -- Duplicate-pending-event guard (task 1e): blocks creating a NEW row
    -- for what is really the same logical event this owner already has
    -- pending, as a way around the per-event resubmission limit. Only
    -- reachable once an organizer row already exists (the ELSE branch
    -- above, run only when the initial SELECT found one) — a first-ever
    -- event from a brand-new organizer can never collide with anything.
    SELECT e.id INTO v_dup_id FROM events e
      WHERE e.organizer_id = v_organizer.id
        AND e.status IN ('review', 'draft')
        AND lower(trim(e.name)) = lower(trim(p_name))
        AND e.event_date IS NOT DISTINCT FROM p_event_date
        AND e.submitted_at > now() - interval '24 hours'
      LIMIT 1;
    IF v_dup_id IS NOT NULL THEN
      RAISE EXCEPTION 'DUPLICATE_PENDING_EVENT: An event with this name and date is already pending — edit and resubmit it instead of creating a new one (id=%).', v_dup_id;
    END IF;
  END IF;

  v_event_id := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(md5(gen_random_uuid()::text), 1, 6);

  v_starts_at := CASE WHEN p_event_date IS NOT NULL AND p_event_time IS NOT NULL
                       THEN (p_event_date + p_event_time) AT TIME ZONE 'Asia/Ho_Chi_Minh'
                       ELSE NULL END;
  IF v_starts_at IS NOT NULL AND v_starts_at < (now() - interval '5 minutes') THEN
    RAISE EXCEPTION 'PAST_EVENT_NOT_ALLOWED';
  END IF;

  SELECT cat_key, cat_label, category INTO v_cat_key, v_cat_label, v_category
  FROM public.normalize_event_category(p_category);

  IF p_included_items IS NOT NULL AND jsonb_typeof(p_included_items) = 'array' THEN
    IF jsonb_array_length(p_included_items) > 3 THEN
      RAISE EXCEPTION 'INVALID_INCLUDED_ITEMS: Maximum 3 items allowed';
    END IF;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_included_items) LOOP
      v_label := trim(COALESCE(v_item->>'label', ''));
      v_detail := trim(COALESCE(v_item->>'detail', ''));
      IF length(v_label) = 0 OR length(v_label) > 60 THEN
        RAISE EXCEPTION 'INVALID_INCLUDED_LABEL: Label must be between 1 and 60 characters';
      END IF;
      IF length(v_detail) > 300 THEN
        RAISE EXCEPTION 'INVALID_INCLUDED_DETAIL: Detail must be under 300 characters';
      END IF;
      v_included_labels := array_append(v_included_labels, v_label);
    END LOOP;
    v_included_text := array_to_string(v_included_labels, ' ▪︎ ');
  END IF;

  INSERT INTO events(
    id, key, slug, organizer_id, name, category, cat_key, cat_label,
    description, price_vnd, price_cents, capacity, seats_remaining, area,
    event_date, event_time, starts_at, status, approval, visibility, submitted_at,
    cover_image, included, included_items, intro, lat, lng,
    address_line, city, postal_code, address_verified
  )
  VALUES (
    v_event_id, v_event_id, v_event_id, v_organizer.id,
    trim(p_name), v_category, v_cat_key, v_cat_label,
    COALESCE(p_description, ''),
    COALESCE(p_price_vnd, 0), COALESCE(p_price_vnd, 0) * 100,
    p_capacity, p_capacity,
    COALESCE(p_location, ''),
    p_event_date, p_event_time, v_starts_at,
    'review', 'host_approves', 'public', now(),
    COALESCE(trim(p_cover_image), ''),
    v_included_text,
    COALESCE(p_included_items, '[]'::jsonb),
    COALESCE(p_intro, ''),
    p_lat, p_lng,
    COALESCE(p_address_line, ''), COALESCE(p_city, ''), COALESCE(p_postal_code, ''), COALESCE(p_address_verified, false)
  )
  RETURNING * INTO v_event;

  INSERT INTO event_status_history(event_id, action, from_status, to_status, reason, actor_id)
  VALUES (v_event_id, 'submit', NULL, 'review', '', auth.uid());

  RETURN v_event;
END;
$$;
REVOKE EXECUTE ON FUNCTION create_event_draft FROM anon;
GRANT EXECUTE ON FUNCTION create_event_draft TO authenticated;

-- 7. admin_review_event — unchanged decision logic (085), only gains its
-- own history-log inserts so approve/reject show up in the same audit
-- trail as submit/withdraw/resubmit.
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
    INSERT INTO event_status_history(event_id, action, from_status, to_status, reason, actor_id)
    VALUES (p_event_id, 'approve', v_event.status, 'live', '', auth.uid());
    IF v_owner_id IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (v_owner_id, 'event_approved', 'Sự kiện đã được duyệt',
              'Sự kiện "' || v_event.name || '" đã được banbe duyệt và hiện đang hiển thị công khai.',
              jsonb_build_object('event_id', p_event_id));
    END IF;
  ELSE
    UPDATE events SET
      status = 'draft', reviewed_by = auth.uid(), reviewed_at = v_now, rejection_reason = v_reason
    WHERE id = p_event_id;
    INSERT INTO event_status_history(event_id, action, from_status, to_status, reason, actor_id)
    VALUES (p_event_id, 'reject', v_event.status, 'draft', v_reason, auth.uid());
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
