-- Migration 217: admin switch `ticket_demo`, seeded OFF.
-- On = ADMIN accounts see a "Ticket demo" entry that opens the ticket screen on built-in sample bookings (holding, awaiting
-- payment, under review, upcoming, today, checked in, ended, cancelled, expired), to show the feature to colleagues.
-- Everything stays on the device: no booking is created, nothing reaches the server. Client-only switch.

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('ticket_demo', 'Tickets: admins can open the ticket screen on sample bookings in every status (nothing is saved)', '217')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('ticket_demo', false)
ON CONFLICT (key) DO NOTHING;
