-- Migration 122: uploaded payment QR codes (hosts + attendees' refund accounts)
--
-- Both Vietnam and the US pay by QR (VietQR / Zelle / Venmo / Cash App ...),
-- so a host can upload the QR they get paid on, and an attendee can attach
-- the QR they want a refund sent to. The app reads the QR's payload (Vision,
-- on the device) and, on long-press, hands it to the matching payment app.
--
-- ADDITIVE ONLY — nothing in the refund flow's invariants (071-078) is
-- weakened:
--   * refund_destinations keeps its required bank_name/account_number/
--     account_holder_name (save_refund_destination is NOT touched); the QR is
--     an attachment set through its own RPC.
--   * goc_refund_snapshot_valid() is unchanged — a QR never makes a snapshot
--     valid or invalid; it is just extra keys inside the snapshot jsonb.
--   * select_refund_destination() is redefined with the SAME body as 074 plus
--     the two QR keys in the snapshot it freezes.
--
-- APPLY with `supabase db push` before shipping the iOS build that uses it.

-- ---------------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------------
-- organizers.pay_qr_path already exists (001). The decoded payload is stored
-- next to it so payers never need to re-decode the image.
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS pay_qr_payload text DEFAULT '';

ALTER TABLE refund_destinations
  ADD COLUMN IF NOT EXISTS qr_path text,
  ADD COLUMN IF NOT EXISTS qr_payload text;

-- ---------------------------------------------------------------------------
-- 2. Storage — `pay-qr` (host QRs, private, organizer-scoped paths)
-- ---------------------------------------------------------------------------
-- Read: the organizer's owners, and anyone holding a booking with them. 005
-- only allowed confirmed/attended bookings, but a payer needs to SEE the QR
-- while their booking is still 'pending' (the hold they are paying for).
DROP POLICY IF EXISTS "pay_qr_organizer_owner_access" ON storage.objects;
CREATE POLICY "pay_qr_organizer_owner_access"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'pay-qr' AND (
    EXISTS (
      SELECT 1 FROM organizers o
      WHERE o.id = split_part((objects).name, '/', 1)
      AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    )
    OR
    EXISTS (
      SELECT 1 FROM bookings b
      JOIN events e ON b.event_id = e.id
      JOIN organizers o ON e.organizer_id = o.id
      WHERE o.id = split_part((objects).name, '/', 1)
      AND b.user_id = auth.uid()
      AND b.status IN ('pending', 'confirmed', 'attended')
    )
  )
);

-- A host replacing/removing their QR needs to delete the old object.
DROP POLICY IF EXISTS "pay_qr_organizer_owner_delete" ON storage.objects;
CREATE POLICY "pay_qr_organizer_owner_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'pay-qr' AND
  EXISTS (
    SELECT 1 FROM organizers o
    WHERE o.id = split_part((objects).name, '/', 1)
    AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);

-- ---------------------------------------------------------------------------
-- 3. Storage — `refund-qr` (attendee QRs, private, user-scoped paths
--    `<user_id>/<file>`)
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('refund-qr', 'refund-qr', false, 1048576, ARRAY['image/jpeg', 'image/png'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "refund_qr_owner_insert" ON storage.objects;
CREATE POLICY "refund_qr_owner_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'refund-qr' AND split_part((objects).name, '/', 1) = auth.uid()::text
);

DROP POLICY IF EXISTS "refund_qr_owner_delete" ON storage.objects;
CREATE POLICY "refund_qr_owner_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'refund-qr' AND split_part((objects).name, '/', 1) = auth.uid()::text
);

-- Read: the owner, and a host ONLY for a QR that is frozen into the
-- recipient_snapshot of one of their own events' refund claims — the same
-- "never a blanket read of a guest's saved accounts" rule as
-- refund_destinations' own host-read policy (074).
DROP POLICY IF EXISTS "refund_qr_read" ON storage.objects;
CREATE POLICY "refund_qr_read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'refund-qr' AND (
    split_part((objects).name, '/', 1) = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM refund_claims rc
      JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
      JOIN events e ON e.id = b.event_id
      JOIN organizers o ON o.id = e.organizer_id
      WHERE rc.recipient_snapshot->>'qr_path' = (objects).name
        AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    )
  )
);

-- ---------------------------------------------------------------------------
-- 4. set_organizer_pay_qr — host sets (or clears, with empty strings) the QR
--    guests pay to. Owner-only; the path must live under the organizer's own
--    folder in `pay-qr`.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_organizer_pay_qr(
  p_organizer text, p_path text DEFAULT '', p_payload text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM organizers o
    WHERE o.id = p_organizer AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF coalesce(p_path, '') <> '' AND split_part(p_path, '/', 1) <> p_organizer THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_PATH');
  END IF;

  UPDATE organizers
  SET pay_qr_path = coalesce(p_path, ''),
      pay_qr_payload = left(coalesce(p_payload, ''), 2000)
  WHERE id = p_organizer;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_organizer_pay_qr(text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_organizer_pay_qr(text, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. set_refund_destination_qr — attendee attaches (or clears) a QR on one of
--    their own saved refund accounts. Also refreshes the QR keys (ONLY those)
--    inside the snapshot of any still-open claim that already selected this
--    account, so a QR added after selecting reaches the host — the bank
--    details in the snapshot are never altered.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_refund_destination_qr(
  p_id uuid, p_qr_path text DEFAULT NULL, p_qr_payload text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id uuid;
  v_path text := NULLIF(trim(coalesce(p_qr_path, '')), '');
  v_payload text := NULLIF(left(trim(coalesce(p_qr_payload, '')), 2000), '');
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  SELECT user_id INTO v_user_id FROM refund_destinations WHERE id = p_id;
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;
  IF v_user_id <> auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF v_path IS NOT NULL AND split_part(v_path, '/', 1) <> auth.uid()::text THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_PATH');
  END IF;

  UPDATE refund_destinations
  SET qr_path = v_path, qr_payload = v_payload, updated_at = now()
  WHERE id = p_id;

  UPDATE refund_claims
  SET recipient_snapshot = coalesce(recipient_snapshot, '{}'::jsonb)
        || jsonb_build_object('qr_path', v_path, 'qr_payload', v_payload)
  WHERE selected_destination_id = p_id
    AND status IN ('owed', 'disputed')
    AND recipient_snapshot IS NOT NULL;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_refund_destination_qr(uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_refund_destination_qr(uuid, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. select_refund_destination — same as 074, plus the QR keys in the
--    snapshot it freezes.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.select_refund_destination(p_claim_id uuid, p_destination_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_dest refund_destinations%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  IF NOT FOUND OR v_booking.user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_claim.status NOT IN ('owed', 'disputed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;

  SELECT * INTO v_dest FROM refund_destinations WHERE id = p_destination_id;
  IF NOT FOUND OR v_dest.user_id IS DISTINCT FROM auth.uid() OR v_dest.confirmed_at IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'DESTINATION_NOT_FOUND');
  END IF;

  -- amount_vnd/status are never touched here — selecting a destination is
  -- purely a recipient choice, never a state transition.
  UPDATE refund_claims
  SET selected_destination_id = v_dest.id,
      recipient_snapshot = jsonb_build_object(
        'label', v_dest.label, 'bank_name', v_dest.bank_name,
        'account_number', v_dest.account_number, 'account_holder_name', v_dest.account_holder_name,
        'qr_path', v_dest.qr_path, 'qr_payload', v_dest.qr_payload
      )
  WHERE id = p_claim_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.select_refund_destination(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.select_refund_destination(uuid, uuid) TO authenticated;
