-- Migration: Strict invite-only events — real backend enforcement.
--
-- Root problem (confirmed by reading, not assumed): `events.visibility`
-- (migration 001) has existed since day one but nothing ever enforced it.
-- `events_select_public` (001, reaffirmed 084) only checks `status`, so any
-- `visibility='invite'` row with `status IN ('live','ended','cancelled')` is
-- fully SELECT-able by anon/authenticated via direct id/slug — a deep link,
-- API join, or a guessed id bypasses privacy entirely. `claim_seats` (007)
-- has no visibility check at all. `event_photos`/`event-photos` bucket RLS
-- is unconditional (`USING (true)` / public bucket). This migration is
-- purely additive (new table, new policies alongside existing ones per
-- this repo's own admin-policy convention in 085) except for the two
-- policies that were the actual bug (`events_select_public`,
-- `event_photos_select_public`), which are narrowed, not removed.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============ 1. event_invites ============
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_invite_status') THEN
    CREATE TYPE event_invite_status AS ENUM ('pending', 'accepted', 'declined', 'revoked', 'expired');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS event_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  -- Resolved at invite time via find_auth_user_by_email() when the email
  -- already has an account; NULL until an email-only invite is redeemed.
  invited_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  -- Always stored (even once invited_user_id resolves) so the host's own
  -- management list can show who was invited without a second auth.users
  -- join through RLS.
  invited_email text NOT NULL,
  -- High-entropy token is returned to the caller exactly once (invite
  -- creation) and never stored in plaintext — only its SHA-256 hash, same
  -- "never store the secret itself" posture as otp_codes (009).
  token_hash text NOT NULL UNIQUE,
  status event_invite_status NOT NULL DEFAULT 'pending',
  invited_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,
  revoked_at timestamptz,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '30 days')
);

CREATE INDEX IF NOT EXISTS idx_event_invites_event ON event_invites(event_id);
CREATE INDEX IF NOT EXISTS idx_event_invites_user ON event_invites(invited_user_id) WHERE invited_user_id IS NOT NULL;
-- One live invite per (event, resolved user) / (event, email) — a host
-- re-inviting the same person updates the existing row via the RPC rather
-- than creating a duplicate.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_event_invite_user ON event_invites(event_id, invited_user_id) WHERE invited_user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uniq_event_invite_email ON event_invites(event_id, lower(invited_email));

ALTER TABLE event_invites ENABLE ROW LEVEL SECURITY;

-- Two SECURITY DEFINER helpers, same posture as the existing
-- is_platform_admin() (026): executing as the owning role bypasses RLS
-- entirely for whatever the function body touches. These exist because
-- events' own RLS needs to check event_invites, and event_invites' RLS
-- needs to check events/organizers — a direct correlated EXISTS in each
-- policy referencing the other table is a genuine mutual-recursion cycle
-- ("infinite recursion detected in policy"), confirmed by actually
-- running it against a local Postgres before this fix. Routing both
-- through bypass functions breaks the cycle: evaluating one table's
-- policy no longer re-triggers RLS evaluation on the other table.
CREATE OR REPLACE FUNCTION public.is_event_host(p_event_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = p_event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  );
$$;
REVOKE ALL ON FUNCTION public.is_event_host(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_event_host(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.has_event_invite_access(p_event_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM event_invites ei
    WHERE ei.event_id = p_event_id AND ei.invited_user_id = auth.uid()
      AND ei.status IN ('pending', 'accepted') AND ei.expires_at > now()
  );
$$;
REVOKE ALL ON FUNCTION public.has_event_invite_access(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_event_invite_access(text) TO anon, authenticated;

-- Host (event's organizer owner), platform admin, or the invited account
-- itself may read an invite row. No direct INSERT/UPDATE/DELETE policy —
-- every write goes through a SECURITY DEFINER RPC below (same posture as
-- claim_seats/bookings: the table owner's RPC bypasses RLS internally,
-- but only after its own explicit authorization + identity checks).
CREATE POLICY "event_invites_select" ON event_invites FOR SELECT TO authenticated USING (
  invited_user_id = auth.uid()
  OR public.is_event_host(event_invites.event_id)
  OR public.is_platform_admin()
);

-- ============ 2. Close the real gap: events/event_photos RLS must honor visibility ============
-- Narrowed, not removed: the public/anon branch now additionally requires
-- visibility = 'public'. Owner access (existing EXISTS clause) and admin
-- access (events_select_admin, 085, untouched, additive) are unaffected.
-- Invited users get their OWN additive policy below, same pattern as 085.
DROP POLICY IF EXISTS "events_select_public" ON events;
CREATE POLICY "events_select_public" ON events FOR SELECT TO anon, authenticated USING (
  (status IN ('live', 'ended', 'cancelled') AND visibility = 'public')
  OR EXISTS (SELECT 1 FROM organizers o WHERE o.id = events.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
);

DROP POLICY IF EXISTS "events_select_invited" ON events;
CREATE POLICY "events_select_invited" ON events FOR SELECT TO authenticated USING (
  status IN ('live', 'ended', 'cancelled')
  AND public.has_event_invite_access(events.id)
);

-- event_photos row metadata (the DB record, not yet the storage object —
-- see section 3) must be gated the same way; this was `USING (true)`.
-- Deliberately just "the parent event is visible to me" rather than
-- duplicating events' own visibility/host/admin/invite logic a second
-- time — events' RLS (three policies above, OR'd) is already the single
-- source of truth for "who can see this event," so a photo row is
-- visible exactly when its event is.
DROP POLICY IF EXISTS "event_photos_select_public" ON event_photos;
CREATE POLICY "event_photos_select_public" ON event_photos FOR SELECT TO anon, authenticated USING (
  EXISTS (SELECT 1 FROM events e WHERE e.id = event_photos.event_id)
);

-- ============ 3. Real photo privacy: a second, PRIVATE bucket for invite-only events ============
-- The spec's own callout, confirmed true here: the public 'event-photos'
-- bucket (005) serves any object via its CDN getPublicUrl() regardless of
-- storage.objects RLS — RLS only gates the authenticated download/sign
-- API, never the public URL path for a bucket marked public=true. Gating
-- storage.objects RLS on the existing bucket alone would NOT have closed
-- this (confirmed against Supabase's own documented behavior, not
-- guessed). Converting the whole 'event-photos' bucket to private would
-- force every public event's cover/gallery photo everywhere in the app
-- (Home cards, Map, Organizer profile, Pulse) onto a signed-URL fetch —
-- a much larger blast radius than this slice's actual scope. Instead:
-- invite-only events' photos now upload to a SEPARATE, genuinely private
-- bucket; public events are completely untouched (still the fast
-- synchronous getPublicUrl() path). Client-side routing of which bucket a
-- given event's photo goes to is enforced again here at the RLS layer —
-- the client choosing the "right" bucket is a convenience, not the trust
-- boundary.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('event-photos-private', 'event-photos-private', false, 52428800, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

-- Path convention mirrors the public bucket: '<event_id>/<file>'. Reuses
-- the same is_event_host()/has_event_invite_access() bypass helpers as
-- events/event_invites above, both for consistency and because a normal
-- (non-SECURITY-DEFINER) storage.objects policy directly correlated to
-- events/organizers/event_invites would otherwise re-run THEIR RLS too —
-- harmless on its own here (storage.objects isn't referenced back by
-- either policy), but routed through the same helpers anyway to keep one
-- source of truth for "host or admin or invited".
DROP POLICY IF EXISTS "event_photos_private_select" ON storage.objects;
CREATE POLICY "event_photos_private_select" ON storage.objects FOR SELECT TO authenticated USING (
  bucket_id = 'event-photos-private' AND (
    public.is_event_host(split_part(name, '/', 1))
    OR public.is_platform_admin()
    OR public.has_event_invite_access(split_part(name, '/', 1))
  )
);

DROP POLICY IF EXISTS "event_photos_private_insert" ON storage.objects;
CREATE POLICY "event_photos_private_insert" ON storage.objects FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'event-photos-private' AND public.is_event_host(split_part(name, '/', 1))
);

DROP POLICY IF EXISTS "event_photos_private_delete" ON storage.objects;
CREATE POLICY "event_photos_private_delete" ON storage.objects FOR DELETE TO authenticated USING (
  bucket_id = 'event-photos-private' AND public.is_event_host(split_part(name, '/', 1))
);

-- ============ 4. claim_seats — gated for defense-in-depth (NOT the live path) ============
-- IMPORTANT, found only by reading the client (GocContext.jsx's own
-- submitReserve comment, migration 053): the real reserve flow calls
-- hold_seats(), not this function — claim_seats() is described in that
-- comment as "legacy" (it never touches payment_state/hold_expires_at,
-- which is exactly why hold_seats replaced it for real bookings). Gating
-- claim_seats ALONE would have left the actual booking path completely
-- unprotected despite looking fixed. Both are gated below: claim_seats
-- for defense-in-depth/any other caller, hold_seats (section 4b) because
-- it is what the app actually calls.
-- Redefined with ONE added check (visibility/invite gate, right after the
-- existing status check, before the capacity check — cheapest-first,
-- matching the function's own existing ordering convention). Everything
-- else byte-for-byte identical to migration 007's version: same capacity
-- math, same instant/manual approval branch, same thread auto-creation.
CREATE OR REPLACE FUNCTION claim_seats(
  p_event text,
  p_qty int,
  p_note text DEFAULT NULL
)
RETURNS bookings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev events%ROWTYPE;
  v_taken int;
  v_user profiles%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_booking_code text;
  v_expires_at timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  SELECT * INTO v_user FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND';
  END IF;

  SELECT * INTO v_ev FROM events WHERE id = p_event OR slug = p_event OR key = p_event FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND';
  END IF;

  IF v_ev.status != 'live' AND v_ev.status::text != 'open' THEN
    RAISE EXCEPTION 'EVENT_NOT_LIVE';
  END IF;

  -- Invite-only gate: the organizer owner may always book their own event;
  -- anyone else needs a non-revoked, non-declined, non-expired invite row
  -- addressed to THEM specifically. A pending invite is enough to book —
  -- "accept" is a separate, informational RSVP acknowledgment (see
  -- respond_to_event_invite below), not a hard prerequisite for booking,
  -- per the spec's own "an invite grant is not a ticket" framing (the
  -- ticket rules below are what actually gate the seat, not this switch).
  IF v_ev.visibility = 'invite'
     AND NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_ev.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
  THEN
    IF NOT EXISTS (
      SELECT 1 FROM event_invites ei
      WHERE ei.event_id = v_ev.id AND ei.invited_user_id = auth.uid()
        AND ei.status IN ('pending', 'accepted') AND ei.expires_at > now()
    ) THEN
      RAISE EXCEPTION 'INVITE_REQUIRED';
    END IF;
  END IF;

  SELECT COALESCE(SUM(qty), 0) INTO v_taken
  FROM bookings
  WHERE event_id = v_ev.id
    AND status IN ('confirmed', 'pending')
    AND (expires_at IS NULL OR expires_at > now());

  IF v_taken + p_qty > v_ev.capacity THEN
    RAISE EXCEPTION 'SOLD_OUT';
  END IF;

  v_booking_code := upper(substr(md5(gen_random_uuid()::text), 1, 6));

  IF v_ev.approval = 'instant' THEN
    INSERT INTO bookings (
      event_id, user_id, qty, total_vnd, code, status, guest_note, confirmed_at
    ) VALUES (
      v_ev.id, auth.uid(), p_qty, v_ev.price_vnd * p_qty, v_booking_code, 'confirmed', p_note, now()
    )
    RETURNING * INTO v_booking;
  ELSE
    v_expires_at := now() + interval '30 minutes';
    INSERT INTO bookings (
      event_id, user_id, qty, total_vnd, code, status, expires_at, guest_note
    ) VALUES (
      v_ev.id, auth.uid(), p_qty, v_ev.price_vnd * p_qty, v_booking_code, 'pending', v_expires_at, p_note
    )
    RETURNING * INTO v_booking;
  END IF;

  IF v_ev.organizer_id IS NOT NULL THEN
    INSERT INTO threads (event_id, guest_id, organizer_id)
    SELECT v_ev.id, auth.uid(), v_ev.organizer_id
    WHERE NOT EXISTS (
      SELECT 1 FROM threads
      WHERE event_id = v_ev.id AND guest_id = auth.uid()
    );
  END IF;

  RETURN v_booking;
END;
$$;
REVOKE EXECUTE ON FUNCTION claim_seats FROM anon;
GRANT EXECUTE ON FUNCTION claim_seats TO authenticated;

-- ============ 4b. hold_seats — the REAL booking path (migration 053) ============
-- Byte-for-byte identical to 053's version except the one added gate
-- (same shape/placement as claim_seats above: right after the status
-- check, before the capacity count). Nothing else changed — same free/
-- paid branch, same notifications, same thread/message writes.
CREATE OR REPLACE FUNCTION public.hold_seats(
  p_event text, p_qty int, p_note text DEFAULT NULL,
  p_ip text DEFAULT NULL, p_user_agent text DEFAULT NULL
)
RETURNS bookings
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ev events%ROWTYPE;
  v_org organizers%ROWTYPE;
  v_user profiles%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_taken int;
  v_is_free boolean;
  v_hold_minutes int;
  v_ref text;
  v_thread_id uuid;
  v_recipient uuid;
  v_message text;
  v_amount_str text;
  v_pay_lines text := '';
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_qty IS NULL OR p_qty < 1 OR p_qty > 20 THEN RAISE EXCEPTION 'INVALID_QTY'; END IF;

  SELECT * INTO v_user FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;

  -- The lock that makes the count below trustworthy.
  SELECT * INTO v_ev FROM events
   WHERE id = p_event OR slug = p_event OR key = p_event
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVENT_NOT_FOUND'; END IF;
  IF v_ev.status != 'live' AND v_ev.status::text != 'open' THEN RAISE EXCEPTION 'EVENT_NOT_LIVE'; END IF;

  -- Strict invite-only events (migration 113) — same gate as claim_seats
  -- above: the organizer owner may always book their own event; anyone
  -- else needs a non-revoked/non-declined/non-expired invite addressed to
  -- them specifically. This is the check that actually matters, since
  -- this is the function the real reserve flow calls.
  IF v_ev.visibility = 'invite'
     AND NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_ev.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
  THEN
    IF NOT EXISTS (
      SELECT 1 FROM event_invites ei
      WHERE ei.event_id = v_ev.id AND ei.invited_user_id = auth.uid()
        AND ei.status IN ('pending', 'accepted') AND ei.expires_at > now()
    ) THEN
      RAISE EXCEPTION 'INVITE_REQUIRED';
    END IF;
  END IF;

  SELECT COALESCE(SUM(b.qty), 0) INTO v_taken
  FROM bookings b
  WHERE b.event_id = v_ev.id
    AND booking_holds_seat(b.payment_state, b.hold_expires_at, b.status);

  IF v_taken + p_qty > v_ev.capacity THEN RAISE EXCEPTION 'SOLD_OUT'; END IF;

  IF v_ev.organizer_id IS NOT NULL THEN
    SELECT * INTO v_org FROM organizers WHERE id = v_ev.organizer_id;
  END IF;

  v_is_free := COALESCE(v_ev.price_vnd, 0) <= 0;
  v_hold_minutes := GREATEST(COALESCE(v_ev.hold_minutes, 30), 1);
  v_ref := 'ART' || lpad(nextval('payment_ref_seq')::text, 5, '0');

  INSERT INTO bookings (
    event_id, user_id, qty, total_vnd, code, status, guest_note,
    payment_state, payment_ref, hold_minutes, hold_expires_at, expires_at, confirmed_at
  ) VALUES (
    v_ev.id, auth.uid(), p_qty, COALESCE(v_ev.price_vnd, 0) * p_qty,
    upper(substr(md5(gen_random_uuid()::text), 1, 6)),
    -- Seat status still follows the event's approval mode; payment_state is
    -- the axis that decides whether a ticket exists.
    CASE WHEN v_ev.approval = 'instant' THEN 'confirmed'::booking_status
         ELSE 'pending'::booking_status END,
    p_note,
    CASE WHEN v_is_free THEN 'confirmed'::payment_state
         ELSE 'holding'::payment_state END,
    v_ref, v_hold_minutes,
    CASE WHEN v_is_free THEN NULL ELSE now() + make_interval(mins => v_hold_minutes) END,
    CASE WHEN v_is_free THEN NULL ELSE now() + make_interval(mins => v_hold_minutes) END,
    CASE WHEN v_ev.approval = 'instant' THEN now() ELSE NULL END
  )
  RETURNING * INTO v_booking;

  -- T1: reservation, with the buyer's session metadata.
  PERFORM log_payment_event(
    v_booking.id, 'T1_hold_created', NULL, v_booking.payment_state,
    auth.uid(), 'buyer', p_ip, p_user_agent,
    jsonb_build_object(
      'qty', p_qty, 'total_vnd', v_booking.total_vnd, 'payment_ref', v_ref,
      'hold_minutes', v_hold_minutes, 'hold_expires_at', v_booking.hold_expires_at,
      'is_free', v_is_free
    )
  );

  IF v_is_free THEN
    UPDATE bookings SET
      paid_marked_at = now(), paid_method = 'free',
      verified_at = now(), verified_via = 'free',
      confirmed_at = COALESCE(confirmed_at, now()), status = 'confirmed'
    WHERE id = v_booking.id
    RETURNING * INTO v_booking;

    PERFORM log_payment_event(v_booking.id, 'T3_verified', 'holding', 'confirmed',
                              NULL, 'system', NULL, NULL,
                              jsonb_build_object('via', 'free'));
    BEGIN
      PERFORM ensure_payment_document(v_booking.id, 'invoice');
      PERFORM ensure_payment_document(v_booking.id, 'receipt');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (auth.uid(), 'payment_confirmed', 'Đã xác nhận',
            'Bạn đã tham gia ' || v_ev.name || '. Vé đã sẵn sàng.',
            jsonb_build_object('booking_id', v_booking.id, 'event_id', v_ev.id, 'via', 'free'));
  ELSE
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (auth.uid(), 'hold_created', 'Đã giữ chỗ',
            'Chỗ của bạn cho ' || v_ev.name || ' đang được giữ trong ' || v_hold_minutes
              || ' phút ▪︎ mã ' || v_ref || '. Chuyển khoản và báo lại trước khi hết giờ.',
            jsonb_build_object('booking_id', v_booking.id, 'event_id', v_ev.id,
                               'payment_ref', v_ref, 'hold_expires_at', v_booking.hold_expires_at));
  END IF;

  IF v_ev.organizer_id IS NOT NULL THEN
    INSERT INTO threads (event_id, guest_id, organizer_id)
    SELECT v_ev.id, auth.uid(), v_ev.organizer_id
    WHERE NOT EXISTS (SELECT 1 FROM threads WHERE event_id = v_ev.id AND guest_id = auth.uid());
    SELECT id INTO v_thread_id FROM threads WHERE event_id = v_ev.id AND guest_id = auth.uid();

    IF v_thread_id IS NOT NULL THEN
      IF v_is_free THEN
        v_message := 'Đặt chỗ thành công ▪︎ sự kiện miễn phí, không cần thanh toán.';
      ELSE
        v_amount_str := replace(to_char(v_booking.total_vnd, 'FM999G999G999'), ',', '.') || '₫';
        IF COALESCE(v_org.bank_account_no, '') <> '' THEN
          v_pay_lines := v_pay_lines || 'Ngân hàng: ' || COALESCE(v_org.bank_name, '')
                       || ', STK ' || v_org.bank_account_no
                       || COALESCE(' (' || NULLIF(v_org.bank_account_name, '') || ')', '') || '. ';
        END IF;
        IF COALESCE(v_org.momo_phone, '') <> '' THEN
          v_pay_lines := v_pay_lines || 'MoMo: ' || v_org.momo_phone || '. ';
        END IF;

        v_message := 'Đặt chỗ thành công ▪︎ số tiền ' || v_amount_str
                  || '. Nội dung chuyển khoản bắt buộc: ' || v_ref
                  || '. Giữ chỗ trong ' || v_hold_minutes || ' phút.'
                  || CASE WHEN v_pay_lines = ''
                          THEN ' Người tổ chức sẽ gửi thông tin chuyển khoản sớm.'
                          ELSE ' Chuyển khoản tới: ' || v_pay_lines END
                  || COALESCE(NULLIF(v_org.pay_note, '') || ' ', '')
                  || 'Sau khi chuyển, bấm "Tôi đã chuyển khoản" để giữ chỗ không bị huỷ.';
      END IF;

      INSERT INTO messages (thread_id, sender_id, body, kind)
      VALUES (v_thread_id, auth.uid(), v_message, 'system');
    END IF;

    SELECT COALESCE(v_org.owner_id, v_org.user_id) INTO v_recipient;
    IF v_recipient IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_recipient, 'booking_requested',
        CASE WHEN v_is_free THEN 'Có người tham gia mới' ELSE 'Yêu cầu đặt chỗ mới' END,
        COALESCE(NULLIF(v_user.display_name, ''), 'Một người tham gia')
          || ' đã đặt ' || p_qty || ' chỗ cho ' || v_ev.name
          || CASE WHEN v_is_free THEN '.' ELSE ' ▪︎ mã ' || v_ref || '.' END,
        jsonb_build_object('booking_id', v_booking.id, 'event_id', v_ev.id,
                           'payment_ref', v_ref, 'qty', p_qty,
                           'total_vnd', v_booking.total_vnd, 'is_free', v_is_free)
      );
    END IF;
  END IF;

  RETURN v_booking;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.hold_seats(text, int, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.hold_seats(text, int, text, text, text) TO authenticated;

-- ============ 5. Invite management RPCs ============

-- Host creates/refreshes invites for up to 25 emails at once. Returns the
-- plaintext tokens (once, never persisted) keyed by email so the caller
-- can build redemption links; the caller is responsible for emailing them
-- (done from api/notify.js's new 'event_invite' branch, which calls this
-- RPC's client-side sibling then sends the email — see note for the flow).
CREATE OR REPLACE FUNCTION public.create_event_invites(p_event_id text, p_emails text[])
RETURNS TABLE(email text, invite_id uuid, token text, existing_user boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_ev events%ROWTYPE;
  v_email text;
  v_user_id uuid;
  v_token text;
  v_token_hash text;
  v_invite_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_emails IS NULL OR array_length(p_emails, 1) IS NULL OR array_length(p_emails, 1) > 25 THEN
    RAISE EXCEPTION 'INVALID_EMAIL_LIST';
  END IF;

  SELECT * INTO v_ev FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVENT_NOT_FOUND'; END IF;
  IF NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_ev.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_ev.visibility != 'invite' THEN
    RAISE EXCEPTION 'EVENT_NOT_INVITE_ONLY';
  END IF;

  FOREACH v_email IN ARRAY p_emails LOOP
    v_email := lower(trim(v_email));
    CONTINUE WHEN v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$';

    v_user_id := public.find_auth_user_by_email(v_email);
    v_token := encode(gen_random_bytes(32), 'hex');
    v_token_hash := encode(digest(v_token, 'sha256'), 'hex');

    INSERT INTO event_invites (event_id, invited_user_id, invited_email, token_hash, status, invited_by)
    VALUES (p_event_id, v_user_id, v_email, v_token_hash, 'pending', auth.uid())
    ON CONFLICT (event_id, lower(invited_email)) DO UPDATE SET
      invited_user_id = EXCLUDED.invited_user_id,
      token_hash = EXCLUDED.token_hash,
      status = 'pending',
      responded_at = NULL,
      revoked_at = NULL,
      expires_at = now() + interval '30 days'
    RETURNING id INTO v_invite_id;

    -- Existing-user invites get a real in-app notification through the
    -- same table/RLS every other notification kind already uses (019) —
    -- "reuse existing notification pipelines," not a parallel inbox.
    -- Email-only invites (v_user_id NULL) have no profiles row to attach
    -- a notification to; their delivery is the email itself, sent by the
    -- caller (api/notify.js) using the plaintext token returned below.
    IF v_user_id IS NOT NULL THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_user_id, 'event_invite',
        'Bạn được mời tham dự một sự kiện riêng tư',
        v_ev.name,
        jsonb_build_object('event_id', p_event_id, 'invite_id', v_invite_id)
      );
    END IF;

    email := v_email;
    invite_id := v_invite_id;
    token := v_token;
    existing_user := v_user_id IS NOT NULL;
    RETURN NEXT;
  END LOOP;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.create_event_invites(text, text[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_event_invites(text, text[]) TO authenticated;

-- Host revokes a single invite. Does NOT touch any existing booking — per
-- spec, revocation must not silently delete a ticket or change financial
-- state; an existing booking still requires the explicit cancellation flow.
CREATE OR REPLACE FUNCTION public.revoke_event_invite(p_invite_id uuid)
RETURNS event_invites
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_invite event_invites%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_invite FROM event_invites WHERE id = p_invite_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'INVITE_NOT_FOUND'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_invite.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  UPDATE event_invites SET status = 'revoked', revoked_at = now() WHERE id = p_invite_id RETURNING * INTO v_invite;
  RETURN v_invite;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.revoke_event_invite(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.revoke_event_invite(uuid) TO authenticated;

-- Invitee accepts/declines an invite already resolved to their own
-- account (invited_user_id already set — the in-app case: they were
-- already a Banbe user when invited).
CREATE OR REPLACE FUNCTION public.respond_to_event_invite(p_invite_id uuid, p_response text)
RETURNS event_invites
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_invite event_invites%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_response NOT IN ('accepted', 'declined') THEN RAISE EXCEPTION 'INVALID_RESPONSE'; END IF;

  SELECT * INTO v_invite FROM event_invites WHERE id = p_invite_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'INVITE_NOT_FOUND'; END IF;
  IF v_invite.invited_user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF v_invite.status NOT IN ('pending', 'accepted', 'declined') THEN RAISE EXCEPTION 'INVITE_NOT_RESPONDABLE'; END IF;
  IF v_invite.expires_at <= now() THEN RAISE EXCEPTION 'INVITE_EXPIRED'; END IF;

  UPDATE event_invites SET status = p_response::event_invite_status, responded_at = now()
  WHERE id = p_invite_id RETURNING * INTO v_invite;
  RETURN v_invite;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.respond_to_event_invite(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.respond_to_event_invite(uuid, text) TO authenticated;

-- Email-invite redemption: binds an invite that was addressed to an email
-- (invited_user_id still NULL at send time — the recipient didn't have an
-- account yet) to the NOW-authenticated caller, but ONLY if the caller's
-- own verified account email matches the invited address exactly. This is
-- the atomic "forwarded link doesn't grant a different account access"
-- check the spec calls for: identity is re-verified against auth.users at
-- redemption time, never trusted from the token alone. Token is compared
-- by its hash; a raw token is never stored or logged.
CREATE OR REPLACE FUNCTION public.redeem_event_invite_token(p_token text)
RETURNS event_invites
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_invite event_invites%ROWTYPE;
  v_my_email text;
  v_token_hash text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_token IS NULL OR length(p_token) < 32 THEN RAISE EXCEPTION 'INVALID_TOKEN'; END IF;

  v_token_hash := encode(digest(p_token, 'sha256'), 'hex');
  SELECT * INTO v_invite FROM event_invites WHERE token_hash = v_token_hash FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'INVITE_NOT_FOUND'; END IF;
  IF v_invite.status = 'revoked' THEN RAISE EXCEPTION 'INVITE_REVOKED'; END IF;
  IF v_invite.expires_at <= now() THEN
    UPDATE event_invites SET status = 'expired' WHERE id = v_invite.id;
    RAISE EXCEPTION 'INVITE_EXPIRED';
  END IF;

  SELECT email INTO v_my_email FROM auth.users WHERE id = auth.uid();
  IF v_my_email IS NULL OR lower(v_my_email) != lower(v_invite.invited_email) THEN
    RAISE EXCEPTION 'IDENTITY_MISMATCH';
  END IF;

  -- Already bound to a different account than the current caller (should
  -- be impossible given the email-match check above unless the invitee's
  -- account email changed after redemption) — fail closed rather than
  -- silently re-binding.
  IF v_invite.invited_user_id IS NOT NULL AND v_invite.invited_user_id != auth.uid() THEN
    RAISE EXCEPTION 'IDENTITY_MISMATCH';
  END IF;

  UPDATE event_invites SET invited_user_id = auth.uid()
  WHERE id = v_invite.id AND (invited_user_id IS NULL OR invited_user_id = auth.uid())
  RETURNING * INTO v_invite;
  RETURN v_invite;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.redeem_event_invite_token(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.redeem_event_invite_token(text) TO authenticated;

-- ============ 6. set_event_visibility ============
-- Deliberately a separate, additive RPC rather than a new positional
-- param threaded through create_event_draft/resubmit_event_for_review —
-- both already large, multiply-extended functions (see this repo's own
-- set_event_keywords, migration 108, for the identical precedent/
-- reasoning). Owner-checked, works regardless of status so an existing
-- draft/review/live event's visibility can be changed later, not just at
-- creation. Switching FROM 'invite' TO 'public' never touches
-- event_invites rows — they simply stop being load-bearing (events_
-- select_public already covers the event once public); switching TO
-- 'invite' does not retroactively revoke anyone who could already see it
-- (existing bookings/threads are financial/relationship state, untouched
-- by a visibility flip, same "don't silently change financial state" rule
-- as revoke_event_invite above).
CREATE OR REPLACE FUNCTION public.set_event_visibility(p_event_id text, p_visibility text)
RETURNS events
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ev events%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_visibility NOT IN ('public', 'invite') THEN RAISE EXCEPTION 'INVALID_VISIBILITY'; END IF;

  SELECT * INTO v_ev FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVENT_NOT_FOUND'; END IF;
  IF NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_ev.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  UPDATE events SET visibility = p_visibility::event_visibility WHERE id = p_event_id RETURNING * INTO v_ev;
  RETURN v_ev;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_event_visibility(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_event_visibility(text, text) TO authenticated;
