-- Migration 136: a refund claim uses the goer's DEFAULT refund account
-- automatically, instead of waiting for them to pick one.
--
-- Until now selected_destination_id / recipient_snapshot were only ever written
-- by select_refund_destination() (the goer tapping a choice), so a goer who had
-- already saved a default account still saw "choose an account" and the host
-- saw "the guest hasn't chosen a refund destination yet".
--
-- Additive on 074. The snapshot has exactly the shape select_refund_destination()
-- writes (label, bank_name, account_number, account_holder_name) so every
-- consumer (goc_refund_snapshot_valid, mark_refund_sent, the batch runner) is
-- unaffected. Rules:
--   * only a CONFIRMED default account is used;
--   * an explicit choice is never overwritten (only claims with no selection);
--   * only claims still owed or disputed are touched;
--   * the goer can still change it afterwards with select_refund_destination().
-- Nothing here changes a claim's status or amount.

CREATE OR REPLACE FUNCTION public.goc_default_destination_snapshot(p_user uuid)
RETURNS TABLE (destination_id uuid, snapshot jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT d.id,
         jsonb_build_object('label', d.label, 'bank_name', d.bank_name,
                            'account_number', d.account_number,
                            'account_holder_name', d.account_holder_name)
  FROM refund_destinations d
  WHERE d.user_id = p_user AND d.is_default AND d.confirmed_at IS NOT NULL
  LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION public.goc_default_destination_snapshot(uuid) FROM PUBLIC, anon, authenticated;

-- 1. New claims.
CREATE OR REPLACE FUNCTION public.goc_refund_claim_default_destination()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user uuid;
  v_dest uuid;
  v_snap jsonb;
BEGIN
  IF NEW.selected_destination_id IS NOT NULL OR NEW.status::text NOT IN ('owed', 'disputed') THEN
    RETURN NEW;
  END IF;
  SELECT b.user_id INTO v_user FROM bookings b WHERE b.id = COALESCE(NEW.booking_id, NEW.reservation_id);
  IF v_user IS NULL THEN RETURN NEW; END IF;
  SELECT destination_id, snapshot INTO v_dest, v_snap FROM public.goc_default_destination_snapshot(v_user);
  IF v_dest IS NOT NULL THEN
    NEW.selected_destination_id := v_dest;
    NEW.recipient_snapshot := v_snap;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS refund_claims_default_destination ON public.refund_claims;
CREATE TRIGGER refund_claims_default_destination
  BEFORE INSERT ON public.refund_claims
  FOR EACH ROW EXECUTE FUNCTION public.goc_refund_claim_default_destination();

-- 2. A goer who sets (or changes) their default AFTER a claim exists: open
--    claims with no selection adopt it. Claims that already have a choice keep it.
CREATE OR REPLACE FUNCTION public.goc_apply_default_destination_to_open_claims()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.is_default AND NEW.confirmed_at IS NOT NULL THEN
    UPDATE refund_claims rc
    SET selected_destination_id = NEW.id,
        recipient_snapshot = jsonb_build_object('label', NEW.label, 'bank_name', NEW.bank_name,
                                                'account_number', NEW.account_number,
                                                'account_holder_name', NEW.account_holder_name)
    FROM bookings b
    WHERE b.id = COALESCE(rc.booking_id, rc.reservation_id)
      AND b.user_id = NEW.user_id
      AND rc.selected_destination_id IS NULL
      AND rc.status::text IN ('owed', 'disputed');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS refund_destinations_apply_default ON public.refund_destinations;
CREATE TRIGGER refund_destinations_apply_default
  AFTER INSERT OR UPDATE OF is_default, confirmed_at ON public.refund_destinations
  FOR EACH ROW EXECUTE FUNCTION public.goc_apply_default_destination_to_open_claims();

-- 3. Existing open claims with no selection and a default account on file.
UPDATE refund_claims rc
SET selected_destination_id = d.id,
    recipient_snapshot = jsonb_build_object('label', d.label, 'bank_name', d.bank_name,
                                            'account_number', d.account_number,
                                            'account_holder_name', d.account_holder_name)
FROM bookings b, refund_destinations d
WHERE b.id = COALESCE(rc.booking_id, rc.reservation_id)
  AND d.user_id = b.user_id AND d.is_default AND d.confirmed_at IS NOT NULL
  AND rc.selected_destination_id IS NULL
  AND rc.status::text IN ('owed', 'disputed');
