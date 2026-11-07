-- Migration 152: attendees of a multi-ticket booking can import THEIR ticket
-- into their own banbe account (the same idea as importing a gift).
--
-- Differences from gifting (132/133), all deliberate:
--   * The booking stays with the buyer — payment and refund ownership never
--     move. Only one attendee's ticket is linked to the importing account.
--   * No recipient email was collected at purchase, so there is nothing to
--     compare an email against. The per-attendee claim code (carried by that
--     attendee's PDF link) is the proof of ownership, exactly as holding the
--     PDF's QR is proof you can attend. The importing account must still have
--     a VERIFIED email, and a code is single-use for ONE other account.
--   * The admission QR does not change, so the buyer's copy and the PDF keep
--     working; importing only makes the ticket appear in the importer's app.

-- ============ 1. Columns ============
ALTER TABLE public.booking_attendees
  ADD COLUMN IF NOT EXISTS claim_code text,
  ADD COLUMN IF NOT EXISTS claimed_by_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS claimed_at timestamptz;

-- 'ATT-' (not 'CLAIM-') so the two kinds of code can never collide and the
-- dispatcher below can tell them apart.
CREATE OR REPLACE FUNCTION public.gen_attendee_claim_code()
RETURNS text
LANGUAGE sql VOLATILE AS $$
  SELECT 'ATT-' || upper(substr(md5(random()::text || clock_timestamp()::text || gen_random_uuid()::text), 1, 10));
$$;

UPDATE public.booking_attendees SET claim_code = public.gen_attendee_claim_code() WHERE claim_code IS NULL;
ALTER TABLE public.booking_attendees ALTER COLUMN claim_code SET DEFAULT public.gen_attendee_claim_code();
ALTER TABLE public.booking_attendees ALTER COLUMN claim_code SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_booking_attendees_claim_code ON public.booking_attendees(claim_code);
CREATE INDEX IF NOT EXISTS idx_booking_attendees_claimed_by ON public.booking_attendees(claimed_by_user_id);

-- The importer can read the ticket they imported (and only that one).
DROP POLICY IF EXISTS booking_attendees_select ON public.booking_attendees;
CREATE POLICY booking_attendees_select ON public.booking_attendees FOR SELECT TO authenticated
USING (
  claimed_by_user_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.bookings b
             WHERE b.id = booking_attendees.booking_id
               AND (b.user_id = auth.uid() OR b.purchaser_id = auth.uid()))
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
);

-- ============ 2. claim_attendee_ticket ============
CREATE OR REPLACE FUNCTION public.claim_attendee_ticket(p_claim_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_verified timestamptz;
  v_att public.booking_attendees%ROWTYPE;
  v_booking public.bookings%ROWTYPE;
  v_event_status text;
  v_code text := upper(trim(p_claim_code));
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED');
  END IF;

  SELECT coalesce((to_jsonb(u)->>'email_confirmed_at')::timestamptz,
                  (to_jsonb(u)->>'confirmed_at')::timestamptz)
    INTO v_verified FROM auth.users u WHERE u.id = v_uid;
  IF v_verified IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'EMAIL_NOT_VERIFIED');
  END IF;

  SELECT * INTO v_att FROM public.booking_attendees WHERE claim_code = v_code FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_CLAIM_CODE');
  END IF;

  IF v_att.claimed_by_user_id = v_uid THEN
    RETURN jsonb_build_object('success', true, 'already_claimed', true, 'kind', 'attendee',
                              'attendee_id', v_att.id, 'booking_id', v_att.booking_id, 'event_id', v_att.event_id);
  END IF;
  IF v_att.claimed_by_user_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_CLAIMED');
  END IF;

  SELECT * INTO v_booking FROM public.bookings WHERE id = v_att.booking_id;
  IF v_booking.status IN ('cancelled', 'expired') THEN
    RETURN jsonb_build_object('success', false, 'error', 'TICKET_CANCELLED');
  END IF;
  IF v_booking.payment_state::text <> 'confirmed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_PAID_YET');
  END IF;
  SELECT e.status::text INTO v_event_status FROM public.events e WHERE e.id = v_booking.event_id;
  IF v_event_status IN ('cancelled', 'ended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_ENDED');
  END IF;

  UPDATE public.booking_attendees
  SET claimed_by_user_id = v_uid, claimed_at = now()
  WHERE id = v_att.id;

  RETURN jsonb_build_object('success', true, 'kind', 'attendee',
                            'attendee_id', v_att.id, 'booking_id', v_att.booking_id, 'event_id', v_att.event_id);
END;
$$;
REVOKE ALL ON FUNCTION public.claim_attendee_ticket(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_attendee_ticket(text) TO authenticated;

-- ============ 3. One entry point for either kind of code ============
CREATE OR REPLACE FUNCTION public.claim_ticket(p_claim_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.booking_attendees WHERE claim_code = upper(trim(p_claim_code))) THEN
    RETURN public.claim_attendee_ticket(p_claim_code);
  END IF;
  RETURN public.claim_gift_ticket(p_claim_code);
END;
$$;
REVOKE ALL ON FUNCTION public.claim_ticket(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_ticket(text) TO authenticated;

-- ============ 4. The importer's list ============
CREATE OR REPLACE FUNCTION public.get_my_imported_tickets()
RETURNS TABLE (
  attendee_id uuid, booking_id uuid, seat_no int, name text,
  admission_token uuid, ticket_code text, checked_in_at timestamptz,
  event_id text, event_key text, event_name text, starts_at timestamptz,
  event_status text, booking_status text, claimed_at timestamptz
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT a.id, a.booking_id, a.seat_no, a.name, a.admission_token, a.ticket_code, a.checked_in_at,
         e.id, e.key, e.name, e.starts_at, e.status::text, b.status::text, a.claimed_at
  FROM public.booking_attendees a
  JOIN public.bookings b ON b.id = a.booking_id
  JOIN public.events e ON e.id = a.event_id
  WHERE a.claimed_by_user_id = auth.uid()
  ORDER BY e.starts_at DESC NULLS LAST, a.seat_no;
$$;
REVOKE ALL ON FUNCTION public.get_my_imported_tickets() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_imported_tickets() TO authenticated;

-- ============ 5. Attendance counts for the person who actually came ============
CREATE OR REPLACE FUNCTION public.credit_imported_attendee_checkin()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_event_name text;
BEGIN
  SELECT name INTO v_event_name FROM events WHERE id = NEW.event_id;
  UPDATE profiles SET attended_count = COALESCE(attended_count, 0) + 1 WHERE id = NEW.claimed_by_user_id;
  INSERT INTO public.notifications (recipient_id, kind, title, body, data)
  VALUES (NEW.claimed_by_user_id, 'checked_in', 'Bạn đã được điểm danh',
          COALESCE(v_event_name, 'Sự kiện') || ' vừa xác nhận bạn đã có mặt.',
          jsonb_build_object('event_id', NEW.event_id, 'booking_id', NEW.booking_id));
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS booking_attendees_credit_checkin ON public.booking_attendees;
CREATE TRIGGER booking_attendees_credit_checkin
AFTER UPDATE OF checked_in_at ON public.booking_attendees
FOR EACH ROW
WHEN (OLD.checked_in_at IS NULL AND NEW.checked_in_at IS NOT NULL AND NEW.claimed_by_user_id IS NOT NULL)
EXECUTE FUNCTION public.credit_imported_attendee_checkin();
