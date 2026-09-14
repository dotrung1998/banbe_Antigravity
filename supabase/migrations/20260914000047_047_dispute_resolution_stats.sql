-- Requirement 2 from .claude/notes/05-notify-retention.md: an anonymized,
-- aggregated view for banbe's internal quality review that stays safe to
-- use even after a case's 72h retention window has expired — because it is
-- captured at resolution time onto its OWN permanent table, not derived
-- from dispute_threads (which is hard-deleted by
-- purge_resolved_dispute_threads()) or from any customer-identifiable data.
--
-- No name, ticket/booking id exposed to the aggregate reader, no chat
-- text, no transaction reference. `booking_id` is stored only so a stats
-- row can be looked up/upserted idempotently if resolve_dispute() is ever
-- retried for the same booking — an aggregate query should never select
-- it, and nothing here grants it back to guest/organizer/PII lookups (no
-- FK is even declared to bookings, deliberately, so this table carries no
-- join path back to a customer record once the source booking row itself
-- is gone).

CREATE TYPE public.dispute_reason_category AS ENUM (
  'proof_not_found',   -- organizer says the payment isn't in their records
  'wrong_amount',      -- amount mismatch between proof and expected total
  'duplicate_claim',   -- same proof/reference already used on another booking
  'expired_or_late',   -- proof submitted after the verification window
  'other'
);

CREATE TABLE IF NOT EXISTS public.dispute_resolution_stats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE, -- no FK: identity/idempotency key only, never joined back to bookings by the aggregate reader
  resolved_at timestamptz NOT NULL,
  resolution_kind text NOT NULL CHECK (resolution_kind IN ('ticket_issued', 'cancelled')),
  reason_category public.dispute_reason_category NOT NULL,
  time_to_resolution_seconds integer NOT NULL CHECK (time_to_resolution_seconds >= 0)
);

ALTER TABLE public.dispute_resolution_stats ENABLE ROW LEVEL SECURITY;

-- Admin-only, and read-only from the client's point of view — every write
-- goes through resolve_dispute() (SECURITY DEFINER) below, same pattern as
-- dispute_threads/dispute_messages.
DROP POLICY IF EXISTS "dispute_resolution_stats_select" ON public.dispute_resolution_stats;
CREATE POLICY "dispute_resolution_stats_select" ON public.dispute_resolution_stats FOR SELECT TO authenticated USING (
  public.is_platform_admin()
);

-- resolve_dispute() now takes the admin's chosen reason category and logs
-- the anonymized stats row alongside the existing resolution, in the same
-- transaction (so a stats row can never exist without its dispute actually
-- having been resolved, and vice versa within this call).
CREATE OR REPLACE FUNCTION public.resolve_dispute(
  p_booking uuid, p_uphold boolean, p_resolution text DEFAULT '',
  p_reason_category public.dispute_reason_category DEFAULT 'other'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_note text := left(trim(COALESCE(p_resolution, '')), 400);
  v_result jsonb;
  v_thread_id uuid;
  v_resolved_at timestamptz := now();
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

  UPDATE bookings SET dispute_resolved_at = v_resolved_at, dispute_resolution = v_note
  WHERE id = p_booking;

  IF p_uphold THEN
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

  UPDATE dispute_threads SET
    guest_id = v_b.user_id,
    organizer_id = (SELECT organizer_id FROM events WHERE id = v_b.event_id),
    resolved_at = v_resolved_at,
    resolution_kind = CASE WHEN p_uphold THEN 'ticket_issued' ELSE 'cancelled' END,
    resolution_note = v_note,
    purge_after = v_resolved_at + interval '72 hours'
  WHERE booking_id = p_booking;

  -- Anonymized aggregate row — no PII, survives the 72h dispute_threads
  -- purge because it lives on its own permanent table. v_b.disputed_at is
  -- set the moment the dispute was escalated (escalate_payment_dispute());
  -- falls back to 0 in the (should-never-happen) case a resolved dispute
  -- somehow has no disputed_at, rather than let a NULL subtraction fail
  -- the whole resolution.
  INSERT INTO dispute_resolution_stats (
    booking_id, resolved_at, resolution_kind, reason_category, time_to_resolution_seconds
  ) VALUES (
    p_booking, v_resolved_at,
    CASE WHEN p_uphold THEN 'ticket_issued' ELSE 'cancelled' END,
    p_reason_category,
    GREATEST(0, EXTRACT(EPOCH FROM (v_resolved_at - COALESCE(v_b.disputed_at, v_resolved_at)))::int)
  )
  ON CONFLICT (booking_id) DO UPDATE SET
    resolved_at = EXCLUDED.resolved_at,
    resolution_kind = EXCLUDED.resolution_kind,
    reason_category = EXCLUDED.reason_category,
    time_to_resolution_seconds = EXCLUDED.time_to_resolution_seconds;

  -- No longer claims the email was sent — this transaction has no idea
  -- whether it will be. api/dispute-resolved-email.js posts the actual
  -- delivery confirmation (or failure) as its own follow-up message once
  -- it knows the real outcome.
  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_b.event_id AND guest_id = v_b.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, NULL,
            'Tranh chấp đã được giải quyết.'
            || ' / Dispute resolved.',
            'system');
  END IF;

  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.resolve_dispute(uuid, boolean, text, public.dispute_reason_category) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_dispute(uuid, boolean, text, public.dispute_reason_category) TO authenticated;

-- The old 3-arg signature is superseded by the 4-arg one above (Postgres
-- allows overloads, but every caller is updated in this same change to
-- always pass a category — dropping the old signature keeps there from
-- being a silent "forgot to pass a category" fallback path).
DROP FUNCTION IF EXISTS public.resolve_dispute(uuid, boolean, text);
