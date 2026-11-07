-- Migration 139: cancelling a booking stops its seat hold.
--
-- cancel_booking() sets status = 'cancelled' but never touched payment_state or
-- hold_expires_at, so a goer still waiting to pay (payment_state 'holding') kept
-- a live countdown, a QR to pay and a "holding a seat" to do item after the host
-- cancelled. The deadline is now cleared the moment a booking becomes cancelled
-- (trigger, so every cancellation path is covered, not just one RPC), and
-- already cancelled bookings are backfilled. Nothing else about the booking
-- (amount, status, refund claim, payment_state) is changed.

CREATE OR REPLACE FUNCTION public.goc_clear_hold_on_cancel()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status::text = 'cancelled' AND NEW.hold_expires_at IS NOT NULL THEN
    NEW.hold_expires_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bookings_clear_hold_on_cancel ON public.bookings;
CREATE TRIGGER bookings_clear_hold_on_cancel
  BEFORE INSERT OR UPDATE OF status, hold_expires_at ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.goc_clear_hold_on_cancel();

UPDATE public.bookings SET hold_expires_at = NULL
WHERE status::text = 'cancelled' AND hold_expires_at IS NOT NULL;
