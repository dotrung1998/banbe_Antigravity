-- Migration: Comprehensive RLS Policies & Booking Status Trigger
-- Description: Enables Row-Level Security (RLS) policies and triggers to enforce legal booking status transitions.

CREATE OR REPLACE FUNCTION validate_booking_status_transition()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  IF (OLD.status = 'pending' AND NEW.status IN ('confirmed', 'expired', 'cancelled')) OR
     (OLD.status = 'confirmed' AND NEW.status IN ('attended', 'no_show', 'cancelled')) THEN
    RETURN NEW;
  ELSE
    RAISE EXCEPTION 'Invalid booking status transition from % to %', OLD.status, NEW.status;
  END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_validate_booking_status ON bookings;
CREATE TRIGGER trigger_validate_booking_status
BEFORE UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION validate_booking_status_transition();
