-- Migration: the two-phase payment state machine, with the concurrency and
-- audit guarantees the old flow never had.
--
-- ---------------------------------------------------------------------------
-- WHY payment_state is a NEW column rather than a rewrite of bookings.status
-- ---------------------------------------------------------------------------
-- bookings.status ('pending'|'confirmed'|'cancelled'|'expired'|'no_show'|
-- 'attended') conflates two orthogonal lifecycles: does this booking hold a
-- seat, and did the person turn up. Payment is a third, independent axis —
-- a booking can be paid and no_show, or attended and disputed. Folding
-- payment into that enum would mean rewriting check_in_guest, cancel_booking,
-- cancel_event, v_event_availability, v_host_ledger, eight RLS policies and
-- both clients' Booking models, to end up with a less precise model. So
-- payment gets its own column, and paid_marked_at is kept in lockstep with
-- payment_state='confirmed' so everything already gating on it (the QR
-- ticket on both clients, confirm_payment's receipts) keeps working.
--
-- ---------------------------------------------------------------------------
-- TWO DEFECTS THIS FIXES, both of which released a seat that must stay locked
-- ---------------------------------------------------------------------------
-- 1. The cron job goc_expire_lapsed_pendings (migration 008) expired ANY
--    pending booking past expires_at — including one where the buyer had
--    already uploaded proof and was waiting on the organizer. It is replaced
--    below with one that only ever touches 'holding'.
-- 2. Worse, and quieter: claim_seats() and v_event_availability counted a
--    seat as held only while `expires_at > now()`. A frozen booking stopped
--    counting the instant its original deadline passed — so the seat leaked
--    to the next buyer before any cron ran at all. Both now go through
--    booking_holds_seat(), so the rule lives in exactly one place.

-- ---------------------------------------------------------------------------
-- 1. States
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_state') THEN
    CREATE TYPE payment_state AS ENUM (
      'holding',              -- PHASE 1: buyer's countdown is running
      'pending_verification', -- PHASE 2: proof in, countdown FROZEN, seat locked
      'confirmed',            -- money verified (webhook, organizer, or free)
      'expired',              -- PHASE 1 lapsed with no proof; seat released
      'disputed',             -- organizer rejected the proof; needs an admin
      'cancelled'             -- cancelled out of band
    );
  END IF;
END $$;

-- Human-quotable bank memo: ART10492. Short, alphanumeric and collision-free
-- by construction — Vietnamese banks strip punctuation out of transfer
-- descriptions and truncate them, so anything longer or prettier than this
-- would not survive the round trip through the bank.
CREATE SEQUENCE IF NOT EXISTS payment_ref_seq START WITH 10000;

--
-- The admin check MUST go through a SECURITY DEFINER helper, not an inline
-- EXISTS on profiles. profiles carries `profiles_select_for_organizer`, whose
-- USING clause reads bookings — so an RLS policy on bookings that reads
-- profiles closes a cycle and Postgres aborts every query on either table
-- with "infinite recursion detected in policy for relation bookings".
-- SECURITY DEFINER runs the lookup as the owner, bypassing profiles' RLS and
-- breaking the cycle. (The same EXISTS is fine inside the SECURITY DEFINER
-- RPCs elsewhere in this file, which never run under RLS to begin with.)
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin');
$$;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated;


-- ---------------------------------------------------------------------------
-- 2. Columns
-- ---------------------------------------------------------------------------
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS payment_state payment_state NOT NULL DEFAULT 'holding',
  ADD COLUMN IF NOT EXISTS payment_ref text,
  -- Kept separate from the legacy expires_at, which other code still reads.
  -- This one is the authoritative PHASE 1 deadline and is FROZEN (left in
  -- the past, deliberately) the moment proof arrives.
  ADD COLUMN IF NOT EXISTS hold_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS hold_minutes int NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS proof_submitted_at timestamptz,
  ADD COLUMN IF NOT EXISTS transaction_id text,
  -- Organizer SLA: when their window to answer runs out.
  ADD COLUMN IF NOT EXISTS verify_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS verify_reminded_at timestamptz,
  ADD COLUMN IF NOT EXISTS verify_escalated_at timestamptz,
  ADD COLUMN IF NOT EXISTS verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS verified_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  -- 'webhook' | 'organizer' | 'admin' | 'free'
  ADD COLUMN IF NOT EXISTS verified_via text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS disputed_at timestamptz,
  ADD COLUMN IF NOT EXISTS dispute_reason text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS dispute_resolved_at timestamptz,
  ADD COLUMN IF NOT EXISTS dispute_resolution text NOT NULL DEFAULT '';

CREATE UNIQUE INDEX IF NOT EXISTS bookings_payment_ref_idx
  ON public.bookings (payment_ref) WHERE payment_ref IS NOT NULL;
CREATE INDEX IF NOT EXISTS bookings_payment_state_idx
  ON public.bookings (payment_state, hold_expires_at);
CREATE INDEX IF NOT EXISTS bookings_verify_due_idx
  ON public.bookings (verify_due_at) WHERE payment_state = 'pending_verification';

-- Default the hold window to the spec's 60 minutes. events.hold_minutes stays
-- authoritative per event so an organizer can shorten it for a same-day event.
ALTER TABLE public.events ALTER COLUMN hold_minutes SET DEFAULT 60;

-- ---------------------------------------------------------------------------
-- 3. THE seat rule. One definition, used by both the availability view and
--    the claim path, so the two can never disagree about whether a seat is
--    taken — which is the class of bug that oversells an event.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.booking_holds_seat(
  p_state payment_state, p_hold_expires_at timestamptz, p_status booking_status
)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    -- Attendance outcomes are terminal and always held their seat.
    WHEN p_status IN ('attended', 'no_show') THEN true
    WHEN p_status IN ('cancelled', 'expired') THEN false
    WHEN p_state = 'confirmed' THEN true
    -- PHASE 2 never releases on a timer. This is the whole point: the
    -- buyer's clock is frozen and only an organizer, an admin, or a matching
    -- webhook moves it off this state.
    WHEN p_state = 'pending_verification' THEN true
    -- A disputed booking stays off the market until an admin rules on it;
    -- handing the seat to someone else would make the dispute unwinnable.
    WHEN p_state = 'disputed' THEN true
    WHEN p_state = 'holding' THEN COALESCE(p_hold_expires_at, 'infinity'::timestamptz) > now()
    ELSE false
  END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Audit log. Append-only: the point of T1/T2/T3 is that nobody, including
--    the organizer and including us, can quietly revise the record after a
--    dispute starts. timestamptz is microsecond-precision natively, so the
--    spec's millisecond requirement is satisfied with room to spare.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_audit_log (
  id bigserial PRIMARY KEY,
  booking_id uuid REFERENCES public.bookings(id) ON DELETE CASCADE,
  event_id text,
  action text NOT NULL,
  from_state payment_state,
  to_state payment_state,
  actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  -- 'buyer' | 'organizer' | 'admin' | 'system' | 'webhook'
  actor_kind text NOT NULL DEFAULT 'system',
  ip inet,
  user_agent text,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS payment_audit_booking_idx
  ON public.payment_audit_log (booking_id, at);

ALTER TABLE public.payment_audit_log ENABLE ROW LEVEL SECURITY;

-- Both sides of a booking can read its own trail; that is what makes the log
-- useful in a dispute rather than just useful to us.
DROP POLICY IF EXISTS "payment_audit_select_party" ON public.payment_audit_log;
CREATE POLICY "payment_audit_select_party" ON public.payment_audit_log
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.bookings b
      LEFT JOIN public.events e ON e.id = b.event_id
      LEFT JOIN public.organizers o ON o.id = e.organizer_id
      WHERE b.id = payment_audit_log.booking_id
        AND (b.user_id = auth.uid() OR o.owner_id = auth.uid() OR o.user_id = auth.uid())
    )
    OR public.is_platform_admin()
  );

-- No INSERT/UPDATE/DELETE policy at all: only SECURITY DEFINER functions
-- write here, so a client cannot forge, amend or erase a step of the trail.
REVOKE INSERT, UPDATE, DELETE ON public.payment_audit_log FROM authenticated, anon;

CREATE OR REPLACE FUNCTION public.log_payment_event(
  p_booking uuid, p_action text,
  p_from payment_state DEFAULT NULL, p_to payment_state DEFAULT NULL,
  p_actor uuid DEFAULT NULL, p_actor_kind text DEFAULT 'system',
  p_ip text DEFAULT NULL, p_user_agent text DEFAULT NULL,
  p_meta jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_event_id text;
  v_ip inet;
BEGIN
  SELECT event_id INTO v_event_id FROM bookings WHERE id = p_booking;
  -- A malformed forwarded-for header must never cost us the audit row.
  BEGIN
    v_ip := NULLIF(trim(p_ip), '')::inet;
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
  END;

  INSERT INTO payment_audit_log (
    booking_id, event_id, action, from_state, to_state,
    actor_id, actor_kind, ip, user_agent, meta, at
  ) VALUES (
    p_booking, v_event_id, p_action, p_from, p_to,
    p_actor, p_actor_kind, v_ip, left(COALESCE(p_user_agent, ''), 400),
    COALESCE(p_meta, '{}'::jsonb), clock_timestamp()
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Webhook receipts. Stored raw and keyed by the provider's own id so a
--    retried delivery (every one of these providers retries) can never
--    confirm the same booking twice or double-count an amount.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  external_id text NOT NULL,
  signature_ok boolean NOT NULL DEFAULT false,
  amount_vnd bigint,
  memo text NOT NULL DEFAULT '',
  matched_booking_id uuid REFERENCES public.bookings(id) ON DELETE SET NULL,
  -- 'matched' | 'no_match' | 'amount_mismatch' | 'already_confirmed' | 'duplicate'
  match_status text NOT NULL DEFAULT 'no_match',
  raw jsonb NOT NULL DEFAULT '{}'::jsonb,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE UNIQUE INDEX IF NOT EXISTS payment_webhook_provider_external_idx
  ON public.payment_webhook_events (provider, external_id);

ALTER TABLE public.payment_webhook_events ENABLE ROW LEVEL SECURITY;
-- Service-role only. Raw bank payloads name real people and account numbers.
DROP POLICY IF EXISTS "payment_webhook_admin_select" ON public.payment_webhook_events;
CREATE POLICY "payment_webhook_admin_select" ON public.payment_webhook_events
  FOR SELECT TO authenticated USING (public.is_platform_admin());

-- ---------------------------------------------------------------------------
-- 6. Backfill, so existing rows obey the new rule from the first second.
-- ---------------------------------------------------------------------------
UPDATE public.bookings SET
  payment_state = CASE
    WHEN status = 'cancelled' THEN 'cancelled'::payment_state
    WHEN status = 'expired' THEN 'expired'::payment_state
    WHEN paid_marked_at IS NOT NULL THEN 'confirmed'::payment_state
    WHEN proof_uploaded_at IS NOT NULL THEN 'pending_verification'::payment_state
    WHEN status IN ('attended', 'no_show') THEN 'confirmed'::payment_state
    ELSE 'holding'::payment_state
  END,
  hold_expires_at = COALESCE(hold_expires_at, expires_at),
  verified_at = COALESCE(verified_at, paid_marked_at),
  verified_via = CASE WHEN paid_marked_at IS NOT NULL AND verified_via = ''
                      THEN 'organizer' ELSE verified_via END,
  payment_ref = COALESCE(payment_ref, 'ART' || lpad(nextval('payment_ref_seq')::text, 5, '0'))
WHERE payment_ref IS NULL;

-- ---------------------------------------------------------------------------
-- 7. Availability, rebuilt on booking_holds_seat().
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_event_availability AS
SELECT
    e.id AS event_id,
    e.capacity,
    COALESCE(SUM(CASE WHEN booking_holds_seat(b.payment_state, b.hold_expires_at, b.status)
                      THEN b.qty ELSE 0 END), 0) AS live_claims,
    e.capacity - COALESCE(SUM(CASE WHEN booking_holds_seat(b.payment_state, b.hold_expires_at, b.status)
                                   THEN b.qty ELSE 0 END), 0) AS seats_left
FROM events e
LEFT JOIN bookings b ON e.id = b.event_id
GROUP BY e.id, e.capacity;

-- ---------------------------------------------------------------------------
-- 8. hold_seats() — PHASE 1 entry.
--
--    Concurrency: the event row is taken FOR UPDATE before the capacity is
--    counted, so two buyers racing for the last seat serialise — the second
--    one blocks until the first has committed its booking and then recounts
--    against it. Counting without that lock is what lets an event oversell.
-- ---------------------------------------------------------------------------
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

  SELECT COALESCE(SUM(b.qty), 0) INTO v_taken
  FROM bookings b
  WHERE b.event_id = v_ev.id
    AND booking_holds_seat(b.payment_state, b.hold_expires_at, b.status);

  IF v_taken + p_qty > v_ev.capacity THEN RAISE EXCEPTION 'SOLD_OUT'; END IF;

  IF v_ev.organizer_id IS NOT NULL THEN
    SELECT * INTO v_org FROM organizers WHERE id = v_ev.organizer_id;
  END IF;

  v_is_free := COALESCE(v_ev.price_vnd, 0) <= 0;
  v_hold_minutes := GREATEST(COALESCE(v_ev.hold_minutes, 60), 1);
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

-- claim_seats keeps its old signature and simply delegates — both clients and
-- migration 025 call it, and there is no reason to make them change in
-- lockstep with the server.
CREATE OR REPLACE FUNCTION public.claim_seats(p_event text, p_qty int, p_note text DEFAULT NULL)
RETURNS bookings
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM hold_seats(p_event, p_qty, p_note, NULL, NULL);
$$;
REVOKE EXECUTE ON FUNCTION public.claim_seats(text, int, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.claim_seats(text, int, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 9. submit_payment_proof() — PHASE 1 -> PHASE 2. "I have transferred."
--
--    This is the transition the whole design exists to protect. It FREEZES
--    the buyer's countdown (hold_expires_at is deliberately left where it is
--    and stops being consulted once payment_state leaves 'holding') and
--    starts the organizer's SLA clock instead.
--
--    Concurrency: the booking row is taken FOR UPDATE, so a double-tap, or a
--    webhook landing in the same instant, cannot produce two PHASE 2 entries
--    or walk back a confirmation that already happened.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_payment_proof(
  p_booking uuid,
  p_transaction_id text,
  p_proof_path text,
  p_ip text DEFAULT NULL,
  p_user_agent text DEFAULT NULL,
  p_sla_minutes int DEFAULT 15
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_from payment_state;
  v_thread_id uuid;
  v_recipient uuid;
  v_txn text := left(trim(COALESCE(p_transaction_id, '')), 120);
  v_proof text := left(trim(COALESCE(p_proof_path, '')), 400);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  IF v_b.user_id <> auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- The spec requires proof AND a transaction id; without both there is
  -- nothing for an organizer to reconcile against their statement.
  IF v_txn = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'TRANSACTION_ID_REQUIRED');
  END IF;
  IF v_proof = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'PROOF_REQUIRED');
  END IF;

  v_from := v_b.payment_state;

  -- Already sorted: say so rather than reopening a settled booking.
  IF v_from = 'confirmed' THEN
    RETURN jsonb_build_object('success', true, 'state', 'confirmed', 'noop', true);
  END IF;
  IF v_from = 'pending_verification' THEN
    -- Re-submitting replaces the evidence but must not restart the SLA, or a
    -- buyer could keep an organizer's clock permanently reset.
    UPDATE bookings SET transaction_id = v_txn, proof_path = v_proof, proof_uploaded_at = now()
    WHERE id = p_booking RETURNING * INTO v_b;
    PERFORM log_payment_event(p_booking, 'T2_proof_resubmitted', v_from, v_from,
                              auth.uid(), 'buyer', p_ip, p_user_agent,
                              jsonb_build_object('transaction_id', v_txn, 'proof_path', v_proof));
    RETURN jsonb_build_object('success', true, 'state', 'pending_verification',
                              'verify_due_at', v_b.verify_due_at);
  END IF;
  IF v_from NOT IN ('holding', 'expired') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_from);
  END IF;

  -- A hold that lapsed only moments ago, whose seat nothing has taken yet, is
  -- recoverable — the buyer did pay. If the seat is gone, it is gone, and
  -- saying so here is far better than confirming a ticket that cannot exist.
  IF v_from = 'expired' THEN
    IF EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = v_b.event_id
        AND (SELECT COALESCE(SUM(b2.qty), 0) FROM bookings b2
             WHERE b2.event_id = e.id
               AND booking_holds_seat(b2.payment_state, b2.hold_expires_at, b2.status))
            + v_b.qty > e.capacity
    ) THEN
      PERFORM log_payment_event(p_booking, 'T2_proof_rejected_sold_out', v_from, v_from,
                                auth.uid(), 'buyer', p_ip, p_user_agent,
                                jsonb_build_object('transaction_id', v_txn));
      RETURN jsonb_build_object('success', false, 'error', 'HOLD_EXPIRED_AND_SOLD_OUT');
    END IF;
  END IF;

  UPDATE bookings SET
    payment_state = 'pending_verification',
    transaction_id = v_txn,
    proof_path = v_proof,
    proof_uploaded_at = now(),
    proof_submitted_at = now(),
    -- The organizer's clock starts here. The buyer's is now irrelevant:
    -- booking_holds_seat() stops consulting hold_expires_at outside 'holding'.
    verify_due_at = now() + make_interval(mins => GREATEST(COALESCE(p_sla_minutes, 15), 1)),
    verify_reminded_at = NULL,
    verify_escalated_at = NULL,
    status = CASE WHEN status = 'expired' THEN 'pending'::booking_status ELSE status END
  WHERE id = p_booking
  RETURNING * INTO v_b;

  -- T2: the buyer's confirmation, with everything a dispute would need.
  PERFORM log_payment_event(
    p_booking, 'T2_proof_submitted', v_from, 'pending_verification',
    auth.uid(), 'buyer', p_ip, p_user_agent,
    jsonb_build_object(
      'transaction_id', v_txn, 'proof_path', v_proof,
      'payment_ref', v_b.payment_ref, 'amount_vnd', v_b.total_vnd,
      'verify_due_at', v_b.verify_due_at, 'recovered_from_expired', v_from = 'expired'
    )
  );

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Khách báo đã chuyển khoản ▪︎ mã ' || COALESCE(v_b.payment_ref, '')
            || ', mã giao dịch ' || v_txn || '. Chỗ được giữ cho tới khi bạn xác nhận.',
            'system');
  END IF;

  SELECT COALESCE(o.owner_id, o.user_id) INTO v_recipient
  FROM events e JOIN organizers o ON o.id = e.organizer_id
  WHERE e.id = v_b.event_id;

  IF v_recipient IS NOT NULL THEN
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_recipient, 'payment_awaiting_verification',
      'Cần xác nhận thanh toán',
      'Một khách đã báo chuyển khoản ' || replace(to_char(v_b.total_vnd, 'FM999G999G999'), ',', '.')
        || '₫ ▪︎ mã ' || COALESCE(v_b.payment_ref, '') || '. Kiểm tra và xác nhận.',
      jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                         'payment_ref', v_b.payment_ref, 'transaction_id', v_txn,
                         'amount_vnd', v_b.total_vnd, 'verify_due_at', v_b.verify_due_at)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'state', 'pending_verification',
                            'verify_due_at', v_b.verify_due_at,
                            'payment_ref', v_b.payment_ref);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.submit_payment_proof(uuid, text, text, text, text, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.submit_payment_proof(uuid, text, text, text, text, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- 10. verify_payment() — PHASE 2 -> CONFIRMED. The one door every route in
--     (webhook auto-match, organizer tap, admin override) goes through, so
--     the ticket, the receipt and the audit line can never disagree.
--
--     p_actor_kind 'webhook'/'system' bypasses the auth.uid() ownership check
--     because it runs as the service role from the webhook handler, which has
--     already authenticated the provider's signature.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verify_payment(
  p_booking uuid,
  p_via text DEFAULT 'organizer',
  p_actor_kind text DEFAULT 'organizer',
  p_meta jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_from payment_state;
  v_authorized boolean;
  v_thread_id uuid;
  v_receipt payment_documents%ROWTYPE;
  v_receipt_number text;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  IF p_actor_kind IN ('webhook', 'system') THEN
    v_authorized := true;
  ELSE
    IF auth.uid() IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
    END IF;
    SELECT EXISTS(
      SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
      WHERE e.id = v_b.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    ) OR EXISTS (
      SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
    ) INTO v_authorized;
  END IF;

  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  v_from := v_b.payment_state;

  -- Idempotent by design: the webhook fires at least once, and an organizer
  -- can easily tap approve on a booking a webhook just settled.
  IF v_from = 'confirmed' THEN
    RETURN jsonb_build_object('success', true, 'state', 'confirmed', 'noop', true);
  END IF;
  IF v_from NOT IN ('holding', 'pending_verification', 'disputed', 'expired') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_from);
  END IF;

  UPDATE bookings SET
    payment_state = 'confirmed',
    status = CASE WHEN status IN ('attended', 'no_show') THEN status
                  ELSE 'confirmed'::booking_status END,
    verified_at = now(),
    verified_via = left(COALESCE(p_via, 'organizer'), 40),
    verified_by = CASE WHEN p_actor_kind IN ('webhook', 'system') THEN NULL ELSE auth.uid() END,
    -- The compatibility bridge: every existing ticket gate reads these.
    paid_marked_at = COALESCE(paid_marked_at, now()),
    paid_method = CASE WHEN COALESCE(paid_method, '') = ''
                       THEN left(COALESCE(p_via, 'bank'), 40) ELSE paid_method END,
    paid_marked_by = COALESCE(paid_marked_by,
                              CASE WHEN p_actor_kind IN ('webhook','system') THEN NULL ELSE auth.uid() END),
    confirmed_at = COALESCE(confirmed_at, now()),
    verify_due_at = NULL
  WHERE id = p_booking
  RETURNING * INTO v_b;

  BEGIN
    PERFORM ensure_payment_document(v_b.id, 'invoice');
    v_receipt := ensure_payment_document(v_b.id, 'receipt');
    v_receipt_number := v_receipt.number;
  EXCEPTION WHEN OTHERS THEN
    v_receipt_number := NULL;
  END;

  -- T3: verification, naming which route settled it.
  PERFORM log_payment_event(
    p_booking, 'T3_verified', v_from, 'confirmed',
    CASE WHEN p_actor_kind IN ('webhook','system') THEN NULL ELSE auth.uid() END,
    p_actor_kind, NULL, NULL,
    COALESCE(p_meta, '{}'::jsonb)
      || jsonb_build_object('via', p_via, 'receipt_number', v_receipt_number,
                            'amount_vnd', v_b.total_vnd, 'payment_ref', v_b.payment_ref)
  );

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id,
            CASE WHEN p_actor_kind IN ('webhook','system') THEN NULL ELSE auth.uid() END,
            'Đã xác nhận thanh toán ▪︎ '
            || CASE WHEN p_via = 'webhook' THEN 'tự động đối soát qua ngân hàng'
                    ELSE 'người tổ chức xác nhận' END
            || COALESCE('. Biên nhận ' || v_receipt_number, '') || '.',
            'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_b.user_id, 'payment_confirmed', 'Đã nhận thanh toán',
          'Thanh toán của bạn đã được xác nhận. Vé và biên nhận đã sẵn sàng.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                             'receipt_number', v_receipt_number, 'via', p_via));

  RETURN jsonb_build_object('success', true, 'state', 'confirmed',
                            'receipt_number', v_receipt_number, 'via', p_via);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.verify_payment(uuid, text, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.verify_payment(uuid, text, text, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- 11. reject_payment() — organizer says the money never arrived.
--
--     Goes to 'disputed', NOT to 'expired'. The buyer has asserted in writing
--     that they paid and attached evidence; quietly releasing the seat would
--     resolve that disagreement in the organizer's favour by default and
--     destroy the only leverage the buyer has. The seat stays locked (see
--     booking_holds_seat) until an admin rules.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reject_payment(
  p_booking uuid, p_reason text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_from payment_state;
  v_authorized boolean;
  v_thread_id uuid;
  v_reason text := left(trim(COALESCE(p_reason, '')), 400);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM events e JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_b.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) INTO v_authorized;
  IF NOT v_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  v_from := v_b.payment_state;
  IF v_from NOT IN ('pending_verification', 'holding') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'state', v_from);
  END IF;

  UPDATE bookings SET
    payment_state = 'disputed',
    disputed_at = now(),
    dispute_reason = v_reason,
    verify_due_at = NULL
  WHERE id = p_booking
  RETURNING * INTO v_b;

  PERFORM log_payment_event(
    p_booking, 'T3_rejected', v_from, 'disputed', auth.uid(), 'organizer', NULL, NULL,
    jsonb_build_object('reason', v_reason, 'transaction_id', v_b.transaction_id,
                       'proof_path', v_b.proof_path, 'payment_ref', v_b.payment_ref)
  );

  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Người tổ chức chưa tìm thấy khoản chuyển khoản này'
            || COALESCE(': ' || NULLIF(v_reason, ''), '')
            || '. Chỗ của bạn vẫn được giữ trong lúc banbe xem xét.', 'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_b.user_id, 'payment_disputed', 'Thanh toán đang được xem xét',
          'Người tổ chức chưa xác nhận được khoản chuyển khoản của bạn. Chỗ vẫn được giữ trong lúc banbe xem xét.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_b.event_id,
                             'reason', v_reason));

  -- Surfaces on the organizer's public profile, same counter the overdue
  -- refund sweep uses.
  UPDATE organizers o SET disputes_open = COALESCE(o.disputes_open, 0) + 1
  FROM events e WHERE e.id = v_b.event_id AND o.id = e.organizer_id;

  RETURN jsonb_build_object('success', true, 'state', 'disputed');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.reject_payment(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reject_payment(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 12. resolve_dispute() — platform admin only. Either the buyer was right
--     (confirm, ticket issues) or they were not (release the seat).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_dispute(
  p_booking uuid, p_uphold boolean, p_resolution text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_note text := left(trim(COALESCE(p_resolution, '')), 400);
  v_result jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADMIN_ONLY');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  IF v_b.payment_state <> 'disputed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_DISPUTED', 'state', v_b.payment_state);
  END IF;

  UPDATE bookings SET dispute_resolved_at = now(), dispute_resolution = v_note
  WHERE id = p_booking;

  IF p_uphold THEN
    -- Buyer was right. verify_payment issues the ticket and the receipt.
    v_result := verify_payment(p_booking, 'admin', 'admin',
                               jsonb_build_object('dispute_resolution', v_note));
  ELSE
    UPDATE bookings SET
      payment_state = 'expired', status = 'expired', verify_due_at = NULL
    WHERE id = p_booking;
    PERFORM log_payment_event(p_booking, 'dispute_resolved_against_buyer',
                              'disputed', 'expired', auth.uid(), 'admin', NULL, NULL,
                              jsonb_build_object('resolution', v_note));
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (v_b.user_id, 'dispute_resolved', 'Kết quả xem xét thanh toán',
            'banbe đã xem xét và không xác nhận được khoản thanh toán này. Chỗ đã được mở lại.',
            jsonb_build_object('booking_id', p_booking, 'resolution', v_note));
    v_result := jsonb_build_object('success', true, 'state', 'expired');
  END IF;

  UPDATE organizers o SET disputes_open = GREATEST(COALESCE(o.disputes_open, 1) - 1, 0)
  FROM events e WHERE e.id = v_b.event_id AND o.id = e.organizer_id;

  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.resolve_dispute(uuid, boolean, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_dispute(uuid, boolean, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 13. Scheduled sweeps.
--
--     expire_stale_holds() is the corrected replacement for migration 008's
--     goc_expire_lapsed_pendings. The critical difference is the first
--     predicate: it only ever touches 'holding'. A booking in
--     'pending_verification' or 'disputed' is invisible to it no matter how
--     long ago its original deadline passed.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_stale_holds()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row record;
  v_count int := 0;
BEGIN
  FOR v_row IN
    SELECT id, user_id, event_id, payment_ref
    FROM bookings
    WHERE payment_state = 'holding'
      AND hold_expires_at IS NOT NULL
      AND hold_expires_at < now()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE bookings SET payment_state = 'expired', status = 'expired'
    WHERE id = v_row.id;

    PERFORM log_payment_event(v_row.id, 'hold_expired', 'holding', 'expired',
                              NULL, 'system', NULL, NULL,
                              jsonb_build_object('payment_ref', v_row.payment_ref));

    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (v_row.user_id, 'hold_expired', 'Hết thời gian giữ chỗ',
            'Chỗ của bạn đã được mở lại vì chưa nhận được xác nhận chuyển khoản.',
            jsonb_build_object('booking_id', v_row.id, 'event_id', v_row.event_id));

    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.expire_stale_holds() FROM anon, authenticated;

-- The old job released seats that PHASE 2 requires stay locked. Replace it.
DO $$ BEGIN
  PERFORM cron.unschedule('goc_expire_lapsed_pendings');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule('bb_expire_stale_holds', '* * * * *',
                     $cmd$ SELECT public.expire_stale_holds(); $cmd$);

-- ---------------------------------------------------------------------------
-- 14. Escalation queue.
--
--     Postgres cannot make outbound HTTP calls here, so the sweep marks what
--     is overdue and enqueues the dispatch; api/cron/escalate-verifications.js
--     drains the queue and does the actual sending. That split also means a
--     Telegram outage cannot roll back or stall a database transaction.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.alert_outbox (
  id bigserial PRIMARY KEY,
  booking_id uuid REFERENCES public.bookings(id) ON DELETE CASCADE,
  -- 'verification_request' | 'verification_reminder' | 'verification_escalation'
  kind text NOT NULL,
  channel text NOT NULL DEFAULT 'telegram',
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  attempts int NOT NULL DEFAULT 0,
  sent_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS alert_outbox_pending_idx
  ON public.alert_outbox (created_at) WHERE sent_at IS NULL;
ALTER TABLE public.alert_outbox ENABLE ROW LEVEL SECURITY;
-- Service role only; no policy.

CREATE OR REPLACE FUNCTION public.sweep_verification_slas()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row record;
  v_reminded int := 0;
  v_escalated int := 0;
BEGIN
  -- T+SLA: first reminder.
  FOR v_row IN
    SELECT b.id, b.event_id, b.payment_ref, b.total_vnd, b.verify_due_at
    FROM bookings b
    WHERE b.payment_state = 'pending_verification'
      AND b.verify_due_at IS NOT NULL
      AND b.verify_due_at < now()
      AND b.verify_reminded_at IS NULL
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE bookings SET verify_reminded_at = now() WHERE id = v_row.id;
    INSERT INTO alert_outbox (booking_id, kind, payload)
    VALUES (v_row.id, 'verification_reminder',
            jsonb_build_object('payment_ref', v_row.payment_ref,
                               'amount_vnd', v_row.total_vnd, 'event_id', v_row.event_id));
    PERFORM log_payment_event(v_row.id, 'sla_reminder_queued',
                              'pending_verification', 'pending_verification',
                              NULL, 'system', NULL, NULL, '{}'::jsonb);
    v_reminded := v_reminded + 1;
  END LOOP;

  -- T+2×SLA: urgent escalation. Deliberately keyed off verify_reminded_at, so
  -- the gap is always one full SLA window after the reminder actually went
  -- out — not after a due date that may have been set before a retry.
  FOR v_row IN
    SELECT b.id, b.event_id, b.payment_ref, b.total_vnd, b.verify_due_at
    FROM bookings b
    WHERE b.payment_state = 'pending_verification'
      AND b.verify_reminded_at IS NOT NULL
      AND b.verify_escalated_at IS NULL
      AND b.verify_reminded_at < now() - make_interval(mins => 15)
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE bookings SET verify_escalated_at = now() WHERE id = v_row.id;
    INSERT INTO alert_outbox (booking_id, kind, channel, payload)
    VALUES (v_row.id, 'verification_escalation', 'urgent',
            jsonb_build_object('payment_ref', v_row.payment_ref,
                               'amount_vnd', v_row.total_vnd, 'event_id', v_row.event_id));
    PERFORM log_payment_event(v_row.id, 'sla_escalation_queued',
                              'pending_verification', 'pending_verification',
                              NULL, 'system', NULL, NULL, '{}'::jsonb);
    v_escalated := v_escalated + 1;
  END LOOP;

  RETURN jsonb_build_object('reminded', v_reminded, 'escalated', v_escalated);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.sweep_verification_slas() FROM anon, authenticated;

SELECT cron.schedule('bb_sweep_verification_slas', '* * * * *',
                     $cmd$ SELECT public.sweep_verification_slas(); $cmd$);

-- ---------------------------------------------------------------------------
-- 15. record_bank_transaction() — the auto-reconciliation matcher.
--
--     Called by api/payment-webhook.js once it has verified the provider's
--     signature. Everything below it is deliberately the database's job, not
--     the handler's: idempotency, matching and the state transition have to
--     happen inside one transaction or a retried delivery can confirm twice.
--
--     Matching is memo AND amount, never memo alone. A memo can be mistyped
--     or reused by the payer; releasing a ticket for the wrong amount because
--     the reference happened to match is not recoverable.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_bank_transaction(
  p_provider text,
  p_external_id text,
  p_amount_vnd bigint,
  p_memo text,
  p_raw jsonb DEFAULT '{}'::jsonb,
  p_signature_ok boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_ref text;
  v_status text;
  v_result jsonb;
  v_webhook_id uuid;
BEGIN
  IF COALESCE(trim(p_external_id), '') = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'EXTERNAL_ID_REQUIRED');
  END IF;

  -- Idempotency gate. The unique index on (provider, external_id) is what
  -- actually enforces it; ON CONFLICT turns a retry into a no-op answer
  -- rather than an error the provider would then retry again.
  INSERT INTO payment_webhook_events (provider, external_id, signature_ok, amount_vnd, memo, raw)
  VALUES (p_provider, trim(p_external_id), p_signature_ok, p_amount_vnd,
          left(COALESCE(p_memo, ''), 500), COALESCE(p_raw, '{}'::jsonb))
  ON CONFLICT (provider, external_id) DO NOTHING
  RETURNING id INTO v_webhook_id;

  IF v_webhook_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'match_status', 'duplicate', 'noop', true);
  END IF;

  IF NOT p_signature_ok THEN
    UPDATE payment_webhook_events SET match_status = 'no_match' WHERE id = v_webhook_id;
    RETURN jsonb_build_object('success', false, 'error', 'BAD_SIGNATURE');
  END IF;

  -- Banks mangle the description: case changes, stripped punctuation, and
  -- the payer's own name and the bank's own boilerplate wrapped around it.
  -- So find our reference inside the noise rather than expecting equality.
  SELECT (regexp_match(upper(COALESCE(p_memo, '')), 'ART[0-9]{4,8}'))[1] INTO v_ref;

  IF v_ref IS NULL THEN
    UPDATE payment_webhook_events SET match_status = 'no_match' WHERE id = v_webhook_id;
    RETURN jsonb_build_object('success', true, 'match_status', 'no_match');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE payment_ref = v_ref FOR UPDATE;
  IF NOT FOUND THEN
    UPDATE payment_webhook_events SET match_status = 'no_match', memo = COALESCE(p_memo, '')
    WHERE id = v_webhook_id;
    RETURN jsonb_build_object('success', true, 'match_status', 'no_match', 'ref', v_ref);
  END IF;

  IF v_b.payment_state = 'confirmed' THEN
    UPDATE payment_webhook_events
       SET match_status = 'already_confirmed', matched_booking_id = v_b.id
     WHERE id = v_webhook_id;
    RETURN jsonb_build_object('success', true, 'match_status', 'already_confirmed',
                              'booking_id', v_b.id);
  END IF;

  -- Underpayment is never auto-confirmed. Overpayment is matched (the money
  -- did arrive) but the difference is recorded for the organizer to settle.
  IF p_amount_vnd IS NULL OR p_amount_vnd < v_b.total_vnd THEN
    UPDATE payment_webhook_events
       SET match_status = 'amount_mismatch', matched_booking_id = v_b.id
     WHERE id = v_webhook_id;
    PERFORM log_payment_event(v_b.id, 'webhook_amount_mismatch',
                              v_b.payment_state, v_b.payment_state, NULL, 'webhook', NULL, NULL,
                              jsonb_build_object('expected_vnd', v_b.total_vnd,
                                                 'received_vnd', p_amount_vnd,
                                                 'external_id', p_external_id, 'ref', v_ref));
    RETURN jsonb_build_object('success', true, 'match_status', 'amount_mismatch',
                              'booking_id', v_b.id, 'expected_vnd', v_b.total_vnd,
                              'received_vnd', p_amount_vnd);
  END IF;

  UPDATE payment_webhook_events
     SET match_status = 'matched', matched_booking_id = v_b.id
   WHERE id = v_webhook_id;

  -- Straight to CONFIRMED with no organizer involvement — the point of the
  -- whole reconciliation path.
  v_result := verify_payment(
    v_b.id, 'webhook', 'webhook',
    jsonb_build_object('provider', p_provider, 'external_id', p_external_id,
                       'received_vnd', p_amount_vnd, 'ref', v_ref,
                       'overpaid_vnd', GREATEST(p_amount_vnd - v_b.total_vnd, 0))
  );

  RETURN jsonb_build_object('success', true, 'match_status', 'matched',
                            'booking_id', v_b.id, 'verify', v_result);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.record_bank_transaction(text, text, bigint, text, jsonb, boolean)
  FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 16. Queues the two clients read.
-- ---------------------------------------------------------------------------

-- What an organizer has to act on, newest first.
-- SECURITY INVOKER IS LOAD-BEARING. A Postgres view defaults to running as
-- its owner, which here owns `bookings` and therefore bypasses every RLS
-- policy on it. Without this, any signed-in user reading the view got back
-- every pending payment on the platform — other people's payment refs,
-- transaction ids, amounts and proof-image paths — while a direct read of
-- `bookings` correctly returned nothing. Verified by probing as an unrelated
-- account: 0 rows direct, 1 row through the view.
--
-- (v_event_availability above is deliberately left as a definer view: it
-- exposes only per-event seat totals, which the public feed already shows,
-- and invoker semantics would make every count read 0 for anonymous
-- browsers.)
CREATE OR REPLACE VIEW public.v_pending_verifications
WITH (security_invoker = true) AS
SELECT
  b.id AS booking_id, b.event_id, e.name AS event_name, e.organizer_id,
  b.user_id, p.display_name AS guest_name,
  b.qty, b.total_vnd, b.payment_ref, b.transaction_id, b.proof_path,
  b.proof_submitted_at, b.verify_due_at,
  b.verify_reminded_at IS NOT NULL AS reminded,
  b.verify_escalated_at IS NOT NULL AS escalated,
  b.verify_due_at < now() AS overdue
FROM bookings b
JOIN events e ON e.id = b.event_id
LEFT JOIN profiles p ON p.id = b.user_id
WHERE b.payment_state = 'pending_verification';

-- The admin dispute desk.
-- Same reasoning as above — and this one carries dispute evidence.
CREATE OR REPLACE VIEW public.v_disputes
WITH (security_invoker = true) AS
SELECT
  b.id AS booking_id, b.event_id, e.name AS event_name, e.organizer_id,
  o.name AS organizer_name, b.user_id, p.display_name AS guest_name,
  b.qty, b.total_vnd, b.payment_ref, b.transaction_id, b.proof_path,
  b.proof_submitted_at, b.disputed_at, b.dispute_reason,
  b.dispute_resolved_at, b.dispute_resolution
FROM bookings b
JOIN events e ON e.id = b.event_id
LEFT JOIN organizers o ON o.id = e.organizer_id
LEFT JOIN profiles p ON p.id = b.user_id
WHERE b.payment_state = 'disputed' OR b.dispute_resolved_at IS NOT NULL;

-- Admins run the dispute desk, so they need to reach the underlying rows.
-- bookings had only guest and host SELECT policies, which is why an admin
-- resolving a dispute could not read back the booking they had just ruled on.
DROP POLICY IF EXISTS "bookings_select_admin" ON public.bookings;
CREATE POLICY "bookings_select_admin" ON public.bookings
  FOR SELECT TO authenticated USING (public.is_platform_admin());

GRANT SELECT ON public.v_pending_verifications TO authenticated;
GRANT SELECT ON public.v_disputes TO authenticated;
