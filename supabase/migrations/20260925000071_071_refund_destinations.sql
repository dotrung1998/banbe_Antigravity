-- Migration: refund_destinations — the goer's own bank account to receive
-- a host-initiated refund into. New table (didn't exist before); RLS-only
-- writes go through set_refund_destination() below (SECURITY DEFINER),
-- same convention as every other write path in this codebase — no direct
-- INSERT/UPDATE policy is granted to clients.

CREATE TABLE IF NOT EXISTS refund_destinations (
  user_id uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  bank_name text NOT NULL,
  account_number text NOT NULL,
  account_holder_name text NOT NULL,
  transfer_note text,
  confirmed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE refund_destinations ENABLE ROW LEVEL SECURITY;

-- Goer: read/write only their own destination. "Write" here means the
-- SECURITY DEFINER RPC below (which still runs as this policy's owner for
-- SELECT purposes after the fact) — no direct INSERT/UPDATE/DELETE policy
-- is granted, matching refund_claims' own no-direct-write convention.
DROP POLICY IF EXISTS "refund_destinations_select_own" ON refund_destinations;
CREATE POLICY "refund_destinations_select_own" ON refund_destinations FOR SELECT TO authenticated USING (
  auth.uid() = user_id
);

-- Organizer: read-only, and only for a refund claim that actually belongs
-- to one of their own events — never a blanket read of another user's bank
-- details.
DROP POLICY IF EXISTS "refund_destinations_select_host" ON refund_destinations;
CREATE POLICY "refund_destinations_select_host" ON refund_destinations FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    JOIN organizers o ON o.id = e.organizer_id
    WHERE b.user_id = refund_destinations.user_id
      AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);

-- No anon/public access at all — no policy is granted to `anon`, and RLS
-- defaults to deny.

-- ---------------------------------------------------------------------------
-- set_refund_destination() — goer adds/edits their own refund bank account.
-- Requires explicit confirmation (p_confirmed = true) before it ever writes
-- anything or sets confirmed_at, per this ticket's own "Require explicit
-- confirmation before saving" rule — the UI is expected to gate the call
-- behind its own confirm step too, but the server enforces it either way.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_refund_destination(
  p_bank_name text,
  p_account_number text,
  p_account_holder_name text,
  p_transfer_note text DEFAULT NULL,
  p_confirmed boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  IF trim(coalesce(p_bank_name, '')) = ''
     OR trim(coalesce(p_account_number, '')) = ''
     OR trim(coalesce(p_account_holder_name, '')) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_INPUT');
  END IF;

  IF NOT p_confirmed THEN
    RETURN jsonb_build_object('success', false, 'error', 'CONFIRMATION_REQUIRED');
  END IF;

  INSERT INTO refund_destinations (user_id, bank_name, account_number, account_holder_name, transfer_note, confirmed_at, updated_at)
  VALUES (auth.uid(), trim(p_bank_name), trim(p_account_number), trim(p_account_holder_name), NULLIF(trim(p_transfer_note), ''), now(), now())
  ON CONFLICT (user_id) DO UPDATE SET
    bank_name = EXCLUDED.bank_name,
    account_number = EXCLUDED.account_number,
    account_holder_name = EXCLUDED.account_holder_name,
    transfer_note = EXCLUDED.transfer_note,
    confirmed_at = now(),
    updated_at = now();

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_refund_destination(text, text, text, text, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_refund_destination(text, text, text, text, boolean) TO authenticated;
