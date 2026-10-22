-- LOCAL TEST HARNESS ONLY — never deployed.
-- Seeds a realistic two-party refund dispute so migration 130's RPCs can be
-- exercised for real: a goer who reported a missing refund, the host who owns
-- the event, and the booking conversation the dispute must render inside.
--
-- Deliberately seeds TWO events and TWO bookings so the "right event, right
-- conversation" assertions have something wrong to be wrong about:
--   test_evt_a / booking_a — the disputed booking (conversation = thread_a)
--   test_evt_b / booking_b — an unrelated event the same guest also booked
--
-- IDs are namespaced (7a…/b…/c…/d…) because migration 010 already seeds demo
-- rows with the obvious 1111…/2222… ids, and ON CONFLICT DO NOTHING would
-- otherwise swallow these inserts silently.
--
-- Phones are set because the refund/reporting RPCs gate on a verified phone.

\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------- accounts
INSERT INTO auth.users (id, email, phone, phone_confirmed_at, raw_user_meta_data, confirmed_at)
VALUES
  ('7a000001-0000-4000-8000-000000000001', 'goer@test.dev',     '+84900000001', now(), '{"display_name":"Goe Test"}'::jsonb, now()),
  ('7a000002-0000-4000-8000-000000000002', 'host@test.dev',     '+84900000002', now(), '{"display_name":"Host Test"}'::jsonb, now()),
  ('7a000003-0000-4000-8000-000000000003', 'other@test.dev',    '+84900000003', now(), '{"display_name":"Other Goer"}'::jsonb, now()),
  ('7a000004-0000-4000-8000-000000000004', 'stranger@test.dev', '+84900000004', now(), '{"display_name":"Not A Party"}'::jsonb, now()),
  ('7a000005-0000-4000-8000-000000000005', 'admin@test.dev',    '+84900000009', now(), '{"display_name":"Admin Test"}'::jsonb, now())
ON CONFLICT (id) DO NOTHING;

-- `handle` is NOT NULL with a UNIQUE index on lower(handle).
INSERT INTO profiles (id, display_name, handle, role, phone, phone_verified)
VALUES
  ('7a000001-0000-4000-8000-000000000001', 'Goe Test',      'goe',    'participant', '+84900000001', true),
  ('7a000002-0000-4000-8000-000000000002', 'Host Test',      'hostt',  'organizer',    '+84900000002', true),
  ('7a000003-0000-4000-8000-000000000003', 'Other Goer',     'otherg', 'participant', '+84900000003', true),
  ('7a000004-0000-4000-8000-000000000004', 'Not A Party',    'strgr',  'participant', '+84900000004', true),
  ('7a000005-0000-4000-8000-000000000005', 'Admin Test',     'admnt',  'admin',        '+84900000009', true)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------- organizer + events
INSERT INTO organizers (id, name, owner_id, user_id)
VALUES ('test_org_a', 'Alpha Events', '7a000002-0000-4000-8000-000000000002', '7a000002-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO events (id, key, name, organizer_id, status, price_vnd, capacity, starts_at, seats_remaining)
VALUES
  ('test_evt_a', 'alpha-2026', 'Alpha Night Market', 'test_org_a', 'live', 150000, 100, now() + interval '30 days', 100),
  ('test_evt_b', 'beta-2026',  'Beta Jazz Evening',  'test_org_a', 'live',  90000, 100, now() + interval '40 days', 100)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------- bookings
-- booking_a: the disputed one — cancelled, so its conversation carries the
-- "Booking cancelled" system card the dispute must hang off.
INSERT INTO bookings (id, event_id, user_id, qty, total_vnd, code, status, created_at)
VALUES
  ('b0000001-0000-4000-8000-000000000001', 'test_evt_a', '7a000001-0000-4000-8000-000000000001', 2, 300000, 'BKA1', 'cancelled', now() - interval '10 days'),
  ('b0000002-0000-4000-8000-000000000002', 'test_evt_b', '7a000001-0000-4000-8000-000000000001', 1,  90000, 'BKB1', 'confirmed',    now() - interval '9 days')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------- the refund claim
-- Starts at 'host_marked_sent' (the state a goer actually disputes FROM), NOT
-- 'disputed': dispute_refund() short-circuits with already=true when the claim
-- is already disputed and would never create the thread, so seeding it as
-- 'disputed' would silently test nothing. 02_dispute.sql then raises it for
-- real through the production RPC.
INSERT INTO refund_claims (id, booking_id, reservation_id, amount_vnd, reason, status, host_marked_at, host_response_due_at, refund_due_at, note, created_at)
VALUES ('c0000001-0000-4000-8000-000000000001', 'b0000001-0000-4000-8000-000000000001', 'b0000001-0000-4000-8000-000000000001', 300000, 'host_cancelled', 'host_marked_sent', now() - interval '4 days', now() + interval '1 day', now() - interval '3 days', 'host said they transferred', now() - interval '10 days');

-- ---------------------------------------------------------------- the conversations
-- threads is UNIQUE(event_id, guest_id): one conversation per guest per event.
-- thread_a is the one the dispute must be found in; thread_b is the decoy.
INSERT INTO threads (id, event_id, guest_id, organizer_id)
VALUES
  ('d0000001-0000-4000-8000-000000000001', 'test_evt_a', '7a000001-0000-4000-8000-000000000001', 'test_org_a'),
  ('d0000002-0000-4000-8000-000000000002', 'test_evt_b', '7a000001-0000-4000-8000-000000000001', 'test_org_a')
ON CONFLICT (id) DO NOTHING;

-- The ordinary booking conversation, including the cancellation system card.
INSERT INTO messages (thread_id, sender_id, body, kind, created_at)
VALUES
  ('d0000001-0000-4000-8000-000000000001', '7a000001-0000-4000-8000-000000000001', 'xin chào, mình mua 2 vé', 'text', now() - interval '11 days'),
  ('d0000001-0000-4000-8000-000000000001', NULL, 'Booking cancelled', 'system', now() - interval '10 days'),
  ('d0000002-0000-4000-8000-000000000002', '7a000001-0000-4000-8000-000000000001', 'chào banbe', 'text', now() - interval '9 days');

-- ---------------------------------------------------------------- a PAYMENT dispute decoy
-- booking_b has an escalated payment dispute. It must NOT be attachable to the
-- refund dispute's card and must NOT be closable by a participant.
INSERT INTO dispute_threads (id, booking_id, refund_claim_id, kind, event_id, guest_id, organizer_id, resolution_note)
VALUES ('f0000001-0000-4000-8000-000000000001', 'b0000002-0000-4000-8000-000000000002', NULL, 'payment', 'test_evt_b', '7a000001-0000-4000-8000-000000000001', 'test_org_a', '')
ON CONFLICT (id) DO NOTHING;

COMMIT;

-- ---------------------------------------------------------------- feature switches
-- 187 seeds Rewards OFF; since 191 the client-callable rewards writes refuse while it is off, so the rewards
-- suites run with the switch on (the off case is asserted explicitly in 20_rewards_fixes_assert.sql).
DO $$ BEGIN
  IF to_regclass('public.app_feature_flags') IS NOT NULL THEN
    UPDATE app_feature_flags SET enabled = true WHERE key = 'rewards';
  END IF;
END $$;
