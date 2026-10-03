-- Host refund proof: when marking a refund sent, the host can attach a photo/PDF
-- of the transfer receipt. The goer sees it on the "confirm refund received"
-- card. Optional by design (the host may not have one), so the existing
-- note-only and batch flows keep working unchanged.
--
-- Storage: private 'refund-proof' bucket, objects at `<claim_id>/<file>`.
-- Host (owner of the claim's event organizer) uploads; host and the booking's
-- guest can read.

ALTER TABLE public.refund_claims ADD COLUMN IF NOT EXISTS proof_path text;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('refund-proof', 'refund-proof', false, 5242880,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "refund_proof_host_insert" ON storage.objects;
CREATE POLICY "refund_proof_host_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'refund-proof' AND EXISTS (
    SELECT 1 FROM public.refund_claims rc
    JOIN public.bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN public.events e ON e.id = b.event_id
    JOIN public.organizers o ON o.id = e.organizer_id
    WHERE rc.id::text = split_part((objects).name, '/', 1)
      AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);

DROP POLICY IF EXISTS "refund_proof_read" ON storage.objects;
CREATE POLICY "refund_proof_read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'refund-proof' AND EXISTS (
    SELECT 1 FROM public.refund_claims rc
    JOIN public.bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN public.events e ON e.id = b.event_id
    LEFT JOIN public.organizers o ON o.id = e.organizer_id
    WHERE rc.id::text = split_part((objects).name, '/', 1)
      AND (b.user_id = auth.uid() OR o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);

-- New signature (extra optional arg) — drop the old one so PostgREST has a
-- single unambiguous mark_refund_sent.
DROP FUNCTION IF EXISTS public.mark_refund_sent(uuid, text);

CREATE OR REPLACE FUNCTION public.mark_refund_sent(p_claim_id uuid, p_note text DEFAULT '', p_proof_path text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim refund_claims%ROWTYPE;
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_host boolean;
  v_note text := trim(p_note);
  v_proof text := NULLIF(left(trim(COALESCE(p_proof_path, '')), 400), '');
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_claim FROM refund_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CLAIM_NOT_FOUND');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = COALESCE(v_claim.booking_id, v_claim.reservation_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  SELECT EXISTS(
    SELECT 1 FROM organizers o
    WHERE o.id = v_event.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) INTO v_is_host;
  IF NOT v_is_host THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- The proof object must live under this claim's own folder (the storage
  -- policy enforces the same on upload).
  IF v_proof IS NOT NULL AND split_part(v_proof, '/', 1) <> p_claim_id::text THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_PROOF_PATH');
  END IF;

  IF v_claim.status = 'host_marked_sent' THEN
    RETURN jsonb_build_object('success', true, 'status', v_claim.status, 'already', true, 'claim', to_jsonb(v_claim));
  END IF;
  IF v_claim.status NOT IN ('owed', 'disputed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_STATE', 'status', v_claim.status);
  END IF;
  IF v_claim.amount_vnd IS NULL OR v_claim.amount_vnd <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_AMOUNT');
  END IF;

  -- Never allow this transition without a real, persisted recipient
  -- snapshot — a bare selected_destination_id with no valid snapshot
  -- content is treated the same as having none at all.
  IF v_claim.selected_destination_id IS NULL OR NOT goc_refund_snapshot_valid(v_claim.recipient_snapshot) THEN
    RETURN jsonb_build_object('success', false, 'error', 'REFUND_DESTINATION_REQUIRED');
  END IF;

  UPDATE refund_claims
  SET status = 'host_marked_sent',
      host_marked_at = now(),
      proof_path = COALESCE(v_proof, proof_path),
      note = CASE WHEN v_note <> ''
                  THEN COALESCE(note || E'\n', '') || 'Host note: ' || v_note
                  ELSE note END
  WHERE id = p_claim_id
  RETURNING * INTO v_claim;

  IF v_booking.user_id IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_booking.user_id, 'refund_marked_sent',
      'Người tổ chức đã báo hoàn tiền',
      COALESCE(v_event.name, 'Sự kiện') || ' báo đã hoàn '
        || replace(to_char(v_claim.amount_vnd, 'FM999G999G999'), ',', '.') || '₫ cho bạn.',
      jsonb_build_object('claim_id', v_claim.id, 'booking_id', v_booking.id, 'event_id', v_event.id, 'amount_vnd', v_claim.amount_vnd, 'has_proof', v_claim.proof_path IS NOT NULL)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'host_marked_sent', 'claim', to_jsonb(v_claim));
END;
$$;

-- NOTE: only the 3-arg signature is revoked/granted here. The old
-- (uuid, text) form is dropped above, so referencing it in a REVOKE would
-- raise 42883 (function does not exist).
REVOKE EXECUTE ON FUNCTION public.mark_refund_sent(uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_refund_sent(uuid, text, text) TO authenticated;
