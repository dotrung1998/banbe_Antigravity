-- Migration: multiple refund destinations per goer + a recipient snapshot
-- on the claim itself.
--
-- refund_destinations (071) was one row per user_id (its own PRIMARY KEY).
-- Extended here to many rows per user: adds `id` (the new PRIMARY KEY),
-- `label`, `is_default`. Existing data is preserved — each user's existing
-- single row becomes their default, label left NULL (goer can name it
-- later).
--
-- refund_claims gets `selected_destination_id` + `recipient_snapshot` — the
-- goer's EXPLICIT choice of destination for THAT claim, snapshotted at
-- selection time so a later edit/delete of the underlying
-- refund_destinations row can never alter what a host already sees for an
-- in-flight claim (product rule B's own "Snapshot recipient details"
-- requirement). Host-facing reads (Refund Center) should prefer this
-- snapshot over a live join from here on.

ALTER TABLE refund_destinations
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS label text,
  ADD COLUMN IF NOT EXISTS is_default boolean NOT NULL DEFAULT true;

UPDATE refund_destinations SET id = gen_random_uuid() WHERE id IS NULL;
ALTER TABLE refund_destinations ALTER COLUMN id SET NOT NULL;

ALTER TABLE refund_destinations DROP CONSTRAINT IF EXISTS refund_destinations_pkey;
ALTER TABLE refund_destinations ADD PRIMARY KEY (id);

-- user_id is no longer unique/PK on its own (many rows per user now), but
-- still required and still the column every RLS policy scopes by.
ALTER TABLE refund_destinations ALTER COLUMN user_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_refund_destinations_one_default
  ON refund_destinations(user_id) WHERE is_default;

ALTER TABLE refund_claims
  ADD COLUMN IF NOT EXISTS selected_destination_id uuid REFERENCES refund_destinations(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS recipient_snapshot jsonb;

-- Backfill: any currently active (owed/disputed) claim whose guest already
-- has a confirmed destination gets that destination selected + snapshotted
-- now, so it keeps working immediately after this migration instead of
-- silently losing its recipient the moment the RLS policy below tightens.
UPDATE refund_claims rc
SET selected_destination_id = rd.id,
    recipient_snapshot = jsonb_build_object(
      'label', rd.label, 'bank_name', rd.bank_name,
      'account_number', rd.account_number, 'account_holder_name', rd.account_holder_name
    )
FROM bookings b, refund_destinations rd
WHERE b.id = COALESCE(rc.booking_id, rc.reservation_id)
  AND rd.user_id = b.user_id AND rd.is_default = true AND rd.confirmed_at IS NOT NULL
  AND rc.status IN ('owed', 'disputed')
  AND rc.selected_destination_id IS NULL;

-- ---------------------------------------------------------------------------
-- RLS — rewritten host-read policy: an organizer can now read a
-- refund_destinations row ONLY when it is the one actually selected on one
-- of their own event's claims (via selected_destination_id), never any of
-- the guest's other saved accounts. The goer's own full read/write access
-- (via the RPCs below) is unchanged.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "refund_destinations_select_host" ON refund_destinations;
CREATE POLICY "refund_destinations_select_host" ON refund_destinations FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    JOIN organizers o ON o.id = e.organizer_id
    WHERE rc.selected_destination_id = refund_destinations.id
      AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);
-- "refund_destinations_select_own" (071) is untouched — still auth.uid() = user_id.

-- ---------------------------------------------------------------------------
-- save_refund_destination() — add (p_id NULL) or edit (p_id given) one of
-- the goer's own destinations. Replaces set_refund_destination() (071),
-- which assumed exactly one row per user; dropped below.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_refund_destination(
  p_id uuid DEFAULT NULL,
  p_label text DEFAULT NULL,
  p_bank_name text DEFAULT '',
  p_account_number text DEFAULT '',
  p_account_holder_name text DEFAULT '',
  p_transfer_note text DEFAULT NULL,
  p_set_default boolean DEFAULT false,
  p_confirmed boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_existing_user_id uuid;
  v_make_default boolean;
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

  IF p_id IS NOT NULL THEN
    SELECT user_id INTO v_existing_user_id FROM refund_destinations WHERE id = p_id;
    IF v_existing_user_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
    END IF;
    IF v_existing_user_id <> auth.uid() THEN
      RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
    END IF;
  END IF;

  -- The very first destination a goer ever adds is always their default —
  -- there's no meaningful "non-default only account" state.
  v_make_default := p_set_default OR NOT EXISTS (SELECT 1 FROM refund_destinations WHERE user_id = auth.uid());

  IF v_make_default THEN
    UPDATE refund_destinations SET is_default = false WHERE user_id = auth.uid() AND is_default = true AND id IS DISTINCT FROM p_id;
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO refund_destinations (id, user_id, label, bank_name, account_number, account_holder_name, transfer_note, is_default, confirmed_at, updated_at)
    VALUES (gen_random_uuid(), auth.uid(), NULLIF(trim(p_label), ''), trim(p_bank_name), trim(p_account_number), trim(p_account_holder_name), NULLIF(trim(p_transfer_note), ''), v_make_default, now(), now())
    RETURNING id INTO v_id;
  ELSE
    UPDATE refund_destinations
    SET label = NULLIF(trim(p_label), ''),
        bank_name = trim(p_bank_name),
        account_number = trim(p_account_number),
        account_holder_name = trim(p_account_holder_name),
        transfer_note = NULLIF(trim(p_transfer_note), ''),
        is_default = v_make_default,
        confirmed_at = now(),
        updated_at = now()
    WHERE id = p_id;
    v_id := p_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.save_refund_destination(uuid, text, text, text, text, text, boolean, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_refund_destination(uuid, text, text, text, text, text, boolean, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- delete_refund_destination() — owner-only. Always allowed: any claim
-- already pointed at this destination keeps its own recipient_snapshot
-- (a plain jsonb copy, not a live join), and selected_destination_id just
-- goes NULL (ON DELETE SET NULL) — nothing already selected ever loses its
-- displayed recipient.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_refund_destination(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id uuid;
  v_was_default boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT user_id, is_default INTO v_user_id, v_was_default FROM refund_destinations WHERE id = p_id;
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'already', true);
  END IF;
  IF v_user_id <> auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  DELETE FROM refund_destinations WHERE id = p_id;

  -- Promote the most-recently-updated remaining account to default so the
  -- goer is never left with saved accounts and no default at all.
  IF v_was_default THEN
    UPDATE refund_destinations SET is_default = true
    WHERE id = (SELECT id FROM refund_destinations WHERE user_id = v_user_id ORDER BY updated_at DESC LIMIT 1);
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_refund_destination(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_refund_destination(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- set_default_refund_destination() — owner-only.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_default_refund_destination(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id uuid;
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

  UPDATE refund_destinations SET is_default = false WHERE user_id = auth.uid() AND is_default = true;
  UPDATE refund_destinations SET is_default = true WHERE id = p_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_default_refund_destination(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_default_refund_destination(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- select_refund_destination() — the goer's EXPLICIT confirmation of which
-- saved account a specific claim should be refunded into. Snapshots the
-- recipient onto the claim itself (product rule B).
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
        'account_number', v_dest.account_number, 'account_holder_name', v_dest.account_holder_name
      )
  WHERE id = p_claim_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.select_refund_destination(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.select_refund_destination(uuid, uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.set_refund_destination(text, text, text, text, boolean);

-- ---------------------------------------------------------------------------
-- create_and_confirm_refund_batch() (073) — re-defined to require a
-- selected_destination_id (not just "any confirmed destination exists" —
-- the goer must have explicitly picked one for THIS claim) and to copy the
-- claim's own recipient_snapshot onto each batch item, so a batch's own
-- audit record never depends on a live join either. amount_vnd is read
-- once per row and only ever written back as itself (never zeroed) —
-- everything else about this function (069/072's authorization/eligibility
-- shape) is unchanged.
-- ---------------------------------------------------------------------------
ALTER TABLE refund_batch_items ADD COLUMN IF NOT EXISTS recipient_snapshot jsonb;

CREATE OR REPLACE FUNCTION public.create_and_confirm_refund_batch(p_claim_ids uuid[], p_note text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer_id text;
  v_batch_id uuid := gen_random_uuid();
  v_total int := 0;
  v_applied int := 0;
  v_skipped int := 0;
  v_row record;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  IF p_claim_ids IS NULL OR array_length(p_claim_ids, 1) IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_CLAIMS_SELECTED');
  END IF;

  IF EXISTS (
    SELECT 1 FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    LEFT JOIN organizers o ON o.id = e.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    WHERE rc.id = ANY(p_claim_ids) AND o.id IS NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  SELECT o.id INTO v_organizer_id
  FROM refund_claims rc
  JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
  JOIN events e ON e.id = b.event_id
  JOIN organizers o ON o.id = e.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  WHERE rc.id = p_claim_ids[1];

  INSERT INTO refund_batches (id, organizer_id, created_by, note, total_amount_vnd, recipient_count)
  VALUES (v_batch_id, v_organizer_id, auth.uid(), NULLIF(trim(p_note), ''), 0, 0);

  FOR v_row IN
    SELECT rc.id, rc.amount_vnd, rc.status, rc.selected_destination_id, rc.recipient_snapshot, b.user_id, e.name AS event_name
    FROM refund_claims rc
    JOIN bookings b ON b.id = COALESCE(rc.booking_id, rc.reservation_id)
    JOIN events e ON e.id = b.event_id
    WHERE rc.id = ANY(p_claim_ids)
    FOR UPDATE OF rc
  LOOP
    IF v_row.status NOT IN ('owed', 'disputed') OR v_row.selected_destination_id IS NULL THEN
      INSERT INTO refund_batch_items (batch_id, claim_id, amount_vnd, applied, recipient_snapshot)
      VALUES (v_batch_id, v_row.id, v_row.amount_vnd, false, v_row.recipient_snapshot);
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    UPDATE refund_claims SET status = 'host_marked_sent', host_marked_at = now() WHERE id = v_row.id;
    INSERT INTO refund_batch_items (batch_id, claim_id, amount_vnd, applied, recipient_snapshot)
    VALUES (v_batch_id, v_row.id, v_row.amount_vnd, true, v_row.recipient_snapshot);
    v_total := v_total + v_row.amount_vnd;
    v_applied := v_applied + 1;

    IF v_row.user_id IS NOT NULL THEN
      INSERT INTO public.notifications (recipient_id, kind, title, body, data)
      VALUES (
        v_row.user_id, 'refund_marked_sent',
        'Người tổ chức đã báo hoàn tiền',
        COALESCE(v_row.event_name, 'Sự kiện') || ' báo đã hoàn '
          || replace(to_char(v_row.amount_vnd, 'FM999G999G999'), ',', '.') || '₫ cho bạn.',
        jsonb_build_object('claim_id', v_row.id, 'amount_vnd', v_row.amount_vnd, 'batch_id', v_batch_id)
      );
    END IF;
  END LOOP;

  UPDATE refund_batches SET total_amount_vnd = v_total, recipient_count = v_applied WHERE id = v_batch_id;

  RETURN jsonb_build_object(
    'success', true, 'batch_id', v_batch_id,
    'applied_count', v_applied, 'skipped_count', v_skipped, 'total_amount_vnd', v_total
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_and_confirm_refund_batch(uuid[], text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_and_confirm_refund_batch(uuid[], text) TO authenticated;
