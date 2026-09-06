-- Migration: Booking Lifecycle (ENUMs, bookings, refund_claims, check_ins, availability view)
-- Description: Creates booking-related ENUM types, tables for the booking lifecycle, and a live availability view.

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'booking_status') THEN
    CREATE TYPE booking_status AS ENUM ('pending', 'confirmed', 'cancelled', 'expired', 'no_show', 'attended');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'refund_status') THEN
    CREATE TYPE refund_status AS ENUM ('owed', 'host_marked_sent', 'guest_confirmed', 'disputed', 'waived');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'refund_reason') THEN
    CREATE TYPE refund_reason AS ENUM ('host_cancelled', 'guest_cancelled', 'dispute');
  END IF;
END $$;

-- ============ bookings ============
CREATE TABLE IF NOT EXISTS bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text REFERENCES events(id) ON DELETE CASCADE,
  user_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  qty int NOT NULL DEFAULT 1,
  total_vnd int NOT NULL DEFAULT 0,
  code text UNIQUE,
  status booking_status NOT NULL DEFAULT 'pending',
  expires_at timestamptz,
  paid_marked_at timestamptz,
  paid_method text,
  paid_marked_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  cancelled_at timestamptz,
  cancelled_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  cancel_reason text,
  guest_note text,
  confirmed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Backward compatibility view/alias for reservations
CREATE OR REPLACE VIEW reservations AS SELECT * FROM bookings;

-- ============ refund_claims ============
CREATE TABLE IF NOT EXISTS refund_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid REFERENCES bookings(id) ON DELETE CASCADE,
  reservation_id uuid REFERENCES bookings(id) ON DELETE CASCADE,
  amount_vnd int NOT NULL DEFAULT 0,
  reason refund_reason NOT NULL,
  status refund_status NOT NULL DEFAULT 'owed',
  host_marked_at timestamptz,
  guest_confirmed_at timestamptz,
  last_flagged_at timestamptz,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ============ check_ins ============
CREATE TABLE IF NOT EXISTS check_ins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid UNIQUE REFERENCES bookings(id) ON DELETE CASCADE,
  reservation_id uuid REFERENCES bookings(id) ON DELETE CASCADE,
  event_id text REFERENCES events(id) ON DELETE CASCADE,
  checked_in_at timestamptz NOT NULL DEFAULT now(),
  checked_at timestamptz DEFAULT now(),
  checked_in_by uuid REFERENCES profiles(id) ON DELETE SET NULL
);

-- Backward compatibility view for checkins
CREATE OR REPLACE VIEW checkins AS SELECT id, booking_id AS reservation_id, event_id, checked_in_at AS checked_at FROM check_ins;

-- ============ Indexes ============
CREATE INDEX IF NOT EXISTS idx_bookings_event_status ON bookings(event_id, status);
CREATE INDEX IF NOT EXISTS idx_bookings_user_id ON bookings(user_id);
CREATE INDEX IF NOT EXISTS idx_bookings_code ON bookings(code);

-- ============ v_event_availability View ============
CREATE OR REPLACE VIEW v_event_availability AS
SELECT
    e.id AS event_id,
    e.capacity,
    COALESCE(
        SUM(
            CASE
                WHEN b.status IN ('confirmed', 'attended') THEN b.qty
                WHEN b.status = 'pending' AND b.expires_at > now() THEN b.qty
                ELSE 0
            END
        ), 0
    ) AS live_claims,
    e.capacity - COALESCE(
        SUM(
            CASE
                WHEN b.status IN ('confirmed', 'attended') THEN b.qty
                WHEN b.status = 'pending' AND b.expires_at > now() THEN b.qty
                ELSE 0
            END
        ), 0
    ) AS seats_left
FROM events e
LEFT JOIN bookings b ON e.id = b.event_id
GROUP BY e.id, e.capacity;

-- ============ Row Level Security ============
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bookings_select_guest" ON bookings;
CREATE POLICY "bookings_select_guest" ON bookings FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "bookings_select_host" ON bookings;
CREATE POLICY "bookings_select_host" ON bookings FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM events e
    JOIN organizers o ON e.organizer_id = o.id
    WHERE e.id = bookings.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);
DROP POLICY IF EXISTS "bookings_insert_guest" ON bookings;
CREATE POLICY "bookings_insert_guest" ON bookings FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "bookings_update_guest" ON bookings;
CREATE POLICY "bookings_update_guest" ON bookings FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE refund_claims ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "refund_claims_select_guest" ON refund_claims;
CREATE POLICY "refund_claims_select_guest" ON refund_claims FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM bookings b
    WHERE (b.id = refund_claims.booking_id OR b.id = refund_claims.reservation_id) AND b.user_id = auth.uid()
  )
);
DROP POLICY IF EXISTS "refund_claims_select_host" ON refund_claims;
CREATE POLICY "refund_claims_select_host" ON refund_claims FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM bookings b
    JOIN events e ON b.event_id = e.id
    JOIN organizers o ON e.organizer_id = o.id
    WHERE (b.id = refund_claims.booking_id OR b.id = refund_claims.reservation_id) AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);

ALTER TABLE check_ins ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "check_ins_select_host" ON check_ins;
CREATE POLICY "check_ins_select_host" ON check_ins FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM bookings b
    JOIN events e ON b.event_id = e.id
    JOIN organizers o ON e.organizer_id = o.id
    WHERE (b.id = check_ins.booking_id OR b.id = check_ins.reservation_id) AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);
