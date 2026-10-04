-- Migration 133: forward-fix for migration 132 (ticket gifting).
--
-- WHY THIS EXISTS
-- Migration 20261112000132 was applied to the remote database BEFORE it was
-- edited, and `supabase db push` never replays an applied version, so the
-- edits in commit 7ea85e0 never reached it. The exact text that was applied is
-- not recoverable from git (132 has a single committed version), so this file
-- does not diff against it. It instead CONVERGES any 132-shaped database onto
-- the corrected 132 definition. Every statement is idempotent, and on a fresh
-- install (where 132 is already the corrected text) it is a no-op re-assertion.
--
-- WHAT IT DELIBERATELY DOES NOT DO
--  * No UPDATE/backfill of any row: existing bookings, claim codes,
--    admission_tokens, check-ins and money columns are untouched. Nothing is
--    rotated or regenerated.
--  * No ADD COLUMN of anything except gift_idempotency_key (nullable, no
--    default). Adding `admission_token ... DEFAULT gen_random_uuid()` to a
--    populated table would assign random tokens to existing tickets, so the
--    guard below fails loudly instead if 132's columns are missing.

-- ============ 0. Guard: 132's schema must already be there ============
DO $$
DECLARE
  v_missing text;
BEGIN
  SELECT string_agg(c, ', ') INTO v_missing
  FROM unnest(ARRAY['purchaser_id','recipient_name','recipient_email','recipient_dob',
                    'gifted_at','claim_code','claimed_at','claimed_by_user_id',
                    'admission_token','original_booking_id']) AS c
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'bookings' AND column_name = c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'migration 133 requires migration 132 to be applied first; bookings is missing: %', v_missing;
  END IF;
END $$;

-- ============ 1. Idempotency key column + unique index ============
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS gift_idempotency_key text;

CREATE UNIQUE INDEX IF NOT EXISTS idx_bookings_gift_idempotency_key
  ON public.bookings(gift_idempotency_key) WHERE gift_idempotency_key IS NOT NULL;

-- ============ 2. RLS + column-level UPDATE ============
DROP POLICY IF EXISTS "bookings_select_guest" ON public.bookings;
CREATE POLICY "bookings_select_guest" ON public.bookings
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR auth.uid() = purchaser_id);

-- Gifting/claim columns are SECURITY DEFINER-only (see 132): without this a
-- single-seat purchaser could rewrite recipient_email and claim their own gift.
REVOKE UPDATE ON public.bookings FROM authenticated;
GRANT UPDATE (guest_note) ON public.bookings TO authenticated;

-- ============ 3. Obsolete overloads ============
-- The corrected functions add a defaulted trailing parameter. CREATE OR REPLACE
-- cannot change a signature, so it would leave the old overload beside the new
-- one and make `gift_ticket(a,b,c,d)` / `check_in_guest(x)` calls ambiguous.
DROP FUNCTION IF EXISTS public.gift_ticket(uuid, text, text, date);
DROP FUNCTION IF EXISTS public.check_in_guest(uuid);

-- ============ 4-7. Functions (verbatim from corrected 132) ============
-- ============ 4. RPC: gift_ticket ============
CREATE OR REPLACE FUNCTION public.gift_ticket(
  p_booking_id uuid,
  p_recipient_name text,
  p_recipient_email text,
  p_recipient_dob date,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_booking public.bookings%ROWTYPE;
  v_event public.events%ROWTYPE;
  v_gift_booking_id uuid;
  v_new_admission_token uuid;
  v_new_code text;
  v_claim_code text;
  v_clean_name text := trim(p_recipient_name);
  v_clean_email text := lower(trim(p_recipient_email));
  v_unit_price int;
  v_existing public.bookings%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  -- Validate recipient inputs
  IF v_clean_name IS NULL OR length(v_clean_name) < 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_NAME');
  END IF;

  IF v_clean_email IS NULL OR v_clean_email NOT LIKE '%_@__%.__%' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_EMAIL');
  END IF;

  IF p_recipient_dob IS NULL OR p_recipient_dob > current_date THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_DOB');
  END IF;

  -- Lock the source booking row
  SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  -- Purchaser authorization
  IF v_booking.user_id IS DISTINCT FROM v_uid
     AND coalesce(v_booking.purchaser_id, v_booking.user_id) IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- IDEMPOTENT REPLAY — deliberately ahead of every eligibility rule below, and
  -- only ever reached once the same purchaser has just been authorized for the
  -- same source booking, so a leaked key is useless on its own. Without this
  -- ordering a retry would fall through to ALREADY_GIFTED and the caller could
  -- not tell "you already did this" from "this ticket was never giftable".
  -- The unique index on gift_idempotency_key is what makes two genuinely
  -- concurrent replays safe: exactly one transfer wins and the loser stops at
  -- the ALREADY_GIFTED check rather than moving a second seat.
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.bookings
    WHERE gift_idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true,
        'already_gifted', true,
        'booking_id', v_existing.id,
        'admission_token', v_existing.admission_token,
        'ticket_code', v_existing.code,
        'claim_code', v_existing.claim_code,
        'recipient_name', v_existing.recipient_name,
        'recipient_email', v_existing.recipient_email,
        'recipient_dob', v_existing.recipient_dob,
        'event_id', v_existing.event_id
      );
    END IF;
  END IF;

  -- Eligibility check: must be confirmed and paid
  IF v_booking.status != 'confirmed' OR v_booking.payment_state != 'confirmed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_ELIGIBLE');
  END IF;

  IF v_booking.recipient_name IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_GIFTED');
  END IF;

  -- Check event status
  SELECT * INTO v_event FROM public.events WHERE id = v_booking.event_id;
  IF v_event.status IN ('cancelled', 'ended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_ENDED');
  END IF;

  -- Generate new recipient admission credentials & claim code
  v_new_admission_token := gen_random_uuid();
  v_new_code := public.gen_gift_ticket_code();
  v_claim_code := public.gen_gift_claim_code();

  IF v_booking.qty > 1 THEN
    -- Transfer exactly ONE ticket from a multi-ticket booking: the purchased
    -- row keeps its own admission credential and entry code (the purchaser is
    -- still attending with the remaining seat — rotating theirs would break a
    -- ticket they never gave away) and only qty/total shrink. The gifted seat
    -- gets its own row so the recipient's attendance, claim and admission
    -- token are all independent of the purchaser's remaining seats.
    v_unit_price := v_booking.total_vnd / v_booking.qty;

    UPDATE public.bookings
    SET qty = qty - 1,
        total_vnd = total_vnd - v_unit_price
    WHERE id = v_booking.id;

    -- Create new row for the gifted single ticket
    INSERT INTO public.bookings (
      event_id,
      user_id,
      purchaser_id,
      qty,
      total_vnd,
      code,
      status,
      payment_state,
      paid_marked_at,
      paid_method,
      recipient_name,
      recipient_email,
      recipient_dob,
      gifted_at,
      claim_code,
      admission_token,
      original_booking_id,
      gift_idempotency_key
    ) VALUES (
      v_booking.event_id,
      v_uid,
      v_uid,
      1,
      v_unit_price,
      v_new_code,
      'confirmed',
      'confirmed',
      v_booking.paid_marked_at,
      v_booking.paid_method,
      v_clean_name,
      v_clean_email,
      p_recipient_dob,
      now(),
      v_claim_code,
      v_new_admission_token,
      v_booking.id,
      p_idempotency_key
    )
    RETURNING id INTO v_gift_booking_id;

  ELSE
    -- Single ticket: this whole row IS the seat being given away, so the
    -- purchaser's previous admission credential is invalidated here — new
    -- admission_token, new entry code — while purchaser_id (payment/refund
    -- ownership) is written explicitly and stays behind.
    v_gift_booking_id := v_booking.id;

    UPDATE public.bookings
    SET purchaser_id = v_uid,
        recipient_name = v_clean_name,
        recipient_email = v_clean_email,
        recipient_dob = p_recipient_dob,
        gifted_at = now(),
        claim_code = v_claim_code,
        admission_token = v_new_admission_token,
        code = v_new_code,
        gift_idempotency_key = p_idempotency_key
    WHERE id = v_booking.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'booking_id', v_gift_booking_id,
    'admission_token', v_new_admission_token,
    'ticket_code', v_new_code,
    'claim_code', v_claim_code,
    'recipient_name', v_clean_name,
    'recipient_email', v_clean_email,
    'recipient_dob', p_recipient_dob,
    'event_id', v_booking.event_id
  );
END;
$$;
REVOKE ALL ON FUNCTION public.gift_ticket(uuid, text, text, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gift_ticket(uuid, text, text, date, text) TO authenticated;

-- ============ 5. RPC: claim_gift_ticket ============
CREATE OR REPLACE FUNCTION public.claim_gift_ticket(p_claim_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_user_email text;
  v_email_verified_at timestamptz;
  v_booking public.bookings%ROWTYPE;
  v_event public.events%ROWTYPE;
  v_clean_code text := upper(trim(p_claim_code));
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  -- Lookup the authenticated user's email. Read through to_jsonb because
  -- GoTrue's own confirmation column was renamed (email_confirmed_at ->
  -- confirmed_at); reading it directly would make this RPC fail to compile at
  -- all on one schema version or the other.
  SELECT lower(trim(u.email)),
         coalesce((to_jsonb(u)->>'email_confirmed_at')::timestamptz,
                  (to_jsonb(u)->>'confirmed_at')::timestamptz)
    INTO v_user_email, v_email_verified_at
    FROM auth.users u WHERE u.id = v_uid;

  IF v_user_email IS NULL OR v_user_email = '' THEN
    SELECT lower(trim(p.email)) INTO v_user_email FROM public.profiles p WHERE p.id = v_uid;
  END IF;

  IF v_user_email IS NULL OR v_user_email = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMAIL_NOT_FOUND');
  END IF;

  -- A date of birth is self-asserted and proves nothing about which mailbox
  -- somebody controls, so ownership rests on the verified email alone. An
  -- unconfirmed address could be somebody else's until the owner clicks the
  -- link, which would hand this seat to the wrong person.
  IF v_email_verified_at IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMAIL_NOT_VERIFIED');
  END IF;

  -- Lock gifted booking row by claim code
  SELECT * INTO v_booking FROM public.bookings
  WHERE claim_code = v_clean_code
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_CLAIM_CODE');
  END IF;

  -- Repeated import check: if already claimed by this user, return success idempotently
  IF v_booking.claimed_by_user_id = v_uid THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_claimed', true,
      'booking_id', v_booking.id,
      'event_id', v_booking.event_id
    );
  END IF;

  -- If already claimed by someone else
  IF v_booking.claimed_by_user_id IS NOT NULL AND v_booking.claimed_by_user_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_CLAIMED');
  END IF;

  -- Verify recipient email matches authenticated email
  IF v_user_email != lower(trim(v_booking.recipient_email)) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'EMAIL_MISMATCH',
      'expected_email', v_booking.recipient_email,
      'actual_email', v_user_email
    );
  END IF;

  -- Check ticket eligibility
  IF v_booking.status IN ('cancelled', 'expired') THEN
    RETURN jsonb_build_object('success', false, 'error', 'TICKET_CANCELLED');
  END IF;

  SELECT e.status INTO v_event.status FROM public.events e WHERE e.id = v_booking.event_id;
  IF v_event.status IN ('cancelled', 'ended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_ENDED');
  END IF;

  -- Attach ticket to recipient's account without creating extra seats
  UPDATE public.bookings
  SET user_id = v_uid,
      claimed_at = now(),
      claimed_by_user_id = v_uid
  WHERE id = v_booking.id;

  RETURN jsonb_build_object(
    'success', true,
    'booking_id', v_booking.id,
    'event_id', v_booking.event_id
  );
END;
$$;
REVOKE ALL ON FUNCTION public.claim_gift_ticket(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_gift_ticket(text) TO authenticated;

-- ============ 6. Update get_checkin_guest_info ============
CREATE OR REPLACE FUNCTION public.get_checkin_guest_info(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_booking public.bookings%ROWTYPE;
  v_org text;
  v_allowed boolean;
  v_name text;
  v_dob date;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED');
  END IF;

  -- Match either primary ID or admission_token
  SELECT * INTO v_booking FROM public.bookings
  WHERE id = p_booking_id OR admission_token = p_booking_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  -- OLD-QR REJECTION:
  -- If ticket was gifted and the scanned credential is NOT the new admission_token
  IF v_booking.recipient_name IS NOT NULL
     AND v_booking.admission_token IS NOT NULL
     AND p_booking_id != v_booking.admission_token THEN
    RETURN jsonb_build_object('success', false, 'error', 'CREDENTIAL_INVALIDATED');
  END IF;

  SELECT e.organizer_id INTO v_org FROM public.events e WHERE e.id = v_booking.event_id;

  v_allowed := (v_org IS NOT NULL AND public.is_promo_host(v_org, v_uid))
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'admin');
  IF NOT v_allowed THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  IF v_booking.status NOT IN ('confirmed', 'attended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_ELIGIBLE');
  END IF;

  IF (SELECT count(*) FROM public.checkin_dob_views
       WHERE host_id = v_uid AND viewed_at > now() - interval '1 hour') >= 300 THEN
    RETURN jsonb_build_object('success', false, 'error', 'RATE_LIMITED');
  END IF;

  -- Attendee name and date of birth: use recipient details for gifted tickets
  IF v_booking.recipient_name IS NOT NULL THEN
    v_name := v_booking.recipient_name;
    v_dob := v_booking.recipient_dob;
  ELSE
    SELECT nullif(p.display_name, '') INTO v_name FROM public.profiles p WHERE p.id = v_booking.user_id;
    SELECT d.date_of_birth INTO v_dob FROM public.user_private_dob d WHERE d.user_id = v_booking.user_id;
  END IF;

  INSERT INTO public.checkin_dob_views (host_id, booking_id, guest_id)
  VALUES (v_uid, v_booking.id, v_booking.user_id);

  RETURN jsonb_build_object(
    'success', true,
    'booking_id', v_booking.id,
    'status', v_booking.status,
    'name', coalesce(v_name, ''),
    'date_of_birth', v_dob
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_checkin_guest_info(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_checkin_guest_info(uuid) TO authenticated;

-- ============ 7. Update check_in_guest ============
-- p_source separates the two callers that both resolve a booking by uuid:
--   'scan'  — the value came out of a ticket QR, so the admission-credential
--              rule below applies and a superseded QR is refused.
--   'manual'— the host tapped a row in their OWN guest list for their OWN
--              event. Not a credential at all, so it must not be caught by
--              that rule: a gifted row's id IS still how the list addresses
--              it, and refusing it would make the recipient impossible to
--              admit by hand.
CREATE OR REPLACE FUNCTION public.check_in_guest(p_reservation_id uuid, p_source text DEFAULT 'manual')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_host boolean;
  v_is_admin boolean;
  v_checkin_id uuid;
  v_attendee uuid;
BEGIN
  -- Match either primary ID or admission_token
  SELECT * INTO v_booking FROM bookings
  WHERE id = p_reservation_id OR admission_token = p_reservation_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
  END IF;

  -- Superseded-QR rejection (scan only). gifting a single seat rotates that
  -- seat's admission_token, so a screenshot of the ticket taken beforehand no
  -- longer resolves to it.
  IF coalesce(p_source, 'manual') = 'scan'
     AND v_booking.recipient_name IS NOT NULL
     AND v_booking.admission_token IS NOT NULL
     AND p_reservation_id != v_booking.admission_token THEN
    RETURN jsonb_build_object('success', false, 'error', 'Credential invalidated');
  END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  SELECT EXISTS(
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_booking.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) INTO v_is_host;

  SELECT EXISTS(
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ) INTO v_is_admin;

  IF NOT v_is_host AND NOT v_is_admin THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;

  IF v_booking.status NOT IN ('confirmed', 'attended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking is not eligible for check-in');
  END IF;

  INSERT INTO check_ins (booking_id, reservation_id, event_id, checked_in_by)
  VALUES (v_booking.id, v_booking.id, v_booking.event_id, auth.uid())
  ON CONFLICT (booking_id) DO NOTHING
  RETURNING id INTO v_checkin_id;

  IF v_checkin_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Guest already checked in');
  END IF;

  UPDATE bookings SET status = 'attended' WHERE id = v_booking.id;

  -- Attendance counts for the person who actually walked through the door:
  -- the claiming recipient once they have imported it, otherwise whoever the
  -- account on the row is. Purchaser's attended_count must not rise for a
  -- seat they handed over.
  v_attendee := coalesce(v_booking.claimed_by_user_id, v_booking.user_id);
  IF v_attendee IS NOT NULL AND v_attendee <> v_booking.purchaser_id THEN
    UPDATE profiles SET attended_count = COALESCE(attended_count, 0) + 1 WHERE id = v_attendee;
  END IF;

  IF v_attendee IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_attendee,
      'checked_in',
      'Bạn đã được điểm danh',
      COALESCE(v_event.name, 'Sự kiện') || ' vừa xác nhận bạn đã có mặt.',
      jsonb_build_object('event_id', v_booking.event_id, 'booking_id', v_booking.id)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'booking_id', v_booking.id,
    'name', COALESCE(v_booking.recipient_name, '')
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.check_in_guest(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.check_in_guest(uuid, text) TO authenticated;
