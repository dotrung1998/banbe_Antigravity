-- Migration: Initial Seed Data for Testing and Demo

DELETE FROM event_photos;
DELETE FROM bookings;
DELETE FROM events;
DELETE FROM organizers;
DELETE FROM profiles;

INSERT INTO auth.users (id, instance_id, email, aud, role) VALUES
('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'user_a@example.com', 'authenticated', 'authenticated'),
('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'user_b@example.com', 'authenticated', 'authenticated'),
('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'org_c@example.com', 'authenticated', 'authenticated'),
('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'org_d@example.com', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO profiles (id, display_name, phone, phone_verified, avatar_url, locale, attended_count, no_show_count, created_at) VALUES
('11111111-1111-1111-1111-111111111111', 'Nguyen Van A', '0901234567', true, 'https://images.unsplash.com/photo-1494790108755-2616b612b786?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=60', 'vi', 12, 1, now()),
('22222222-2222-2222-2222-222222222222', 'Tran Thi B', '0909876543', false, 'https://images.unsplash.com/photo-1517841905240-472988babdf9?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=60', 'en', 5, 0, now()),
('33333333-3333-3333-3333-333333333333', 'Le Van C (Organizer)', '0912345678', true, 'https://images.unsplash.com/photo-1500648767791-3dcc7e77260a?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=60', 'vi', 0, 0, now()),
('44444444-4444-4444-4444-444444444444', 'Pham Thi D (Organizer)', '0987654321', true, 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?ixlib=rb-1.2.1&auto=format&fit=crop&w=500&q=60', 'vi', 0, 0, now())
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name, phone = EXCLUDED.phone;

INSERT INTO organizers (id, owner_id, name, instagram, about, hosting_since, verified, pay_methods, bank_name, bank_account_name, bank_account_no, momo_phone, pay_qr_path, pay_note, refund_pledge, disputes_open) VALUES
('org_001', '33333333-3333-3333-3333-333333333333', 'Tech Events Vietnam', '@techevents', 'Leading organizer of tech conferences and workshops in Vietnam.', '2020', true, ARRAY['bank', 'momo'], 'Vietcombank', 'Le Van C', '0123456789', '0912345678', 'pay-qr/org_001/qr.jpg', 'Payments accepted via Bank Transfer or Momo.', 'Full refund if event is cancelled by host.', 0),
('org_002', '44444444-4444-4444-4444-444444444444', 'Food & Travel Club', '@foodtravel', 'Exploring the best culinary spots and cultural journeys.', '2021', false, ARRAY['bank', 'cash'], 'Agribank', 'Pham Thi D', '987654321', '0987654321', 'pay-qr/org_002/qr.jpg', 'Please transfer before event starts.', 'Refunds handled case-by-case.', 0)
ON CONFLICT (id) DO NOTHING;

INSERT INTO events (id, organizer_id, slug, key, name, category, description, included, area, lat, lng, starts_at, price_vnd, capacity, palette, greeting, visibility, approval, hold_minutes, status, created_at) VALUES
('evt_001', 'org_001', 'react-summit-2024', 'react-summit-2024', 'React Summit 2024', 'Technology', 'A gathering of React enthusiasts and experts to discuss the future of frontend development.', 'Lunch, Swag Bag, Certificate', 'Ho Chi Minh City', 10.8231, 106.6297, '2024-10-15 09:00:00+07', 500000, 500, 'blue', 'Welcome to React Summit 2024! We are excited to have you join us.', 'public', 'instant', 30, 'live', now()),
('evt_002', 'org_001', 'nodejs-backend-masterclass', 'nodejs-backend-masterclass', 'Node.js Backend Masterclass', 'Technology', 'Deep dive into Node.js, Express, and building scalable backend services.', 'Lunch, Source Code Access', 'Hanoi', 21.0278, 105.8342, '2024-11-20 10:00:00+07', 1200000, 200, 'indigo', 'Master backend development with Node.js in this intensive workshop.', 'public', 'host_approves', 60, 'live', now()),
('evt_003', 'org_002', 'saigon-food-tour', 'saigon-food-tour', 'Saigon Food & Walking Tour', 'Food & Travel', 'Explore the hidden culinary gems of District 1, Ho Chi Minh City with a local guide.', 'Food tastings, Local guide', 'Ho Chi Minh City', 10.7769, 106.7009, '2024-09-28 14:00:00+07', 300000, 30, 'orange', 'Join us for an unforgettable culinary journey through Saigon.', 'public', 'instant', 15, 'draft', now()),
('evt_004', 'org_002', 'da-lat-adventure-weekend', 'da-lat-adventure-weekend', 'Da Lat Adventure Weekend', 'Travel', 'A weekend getaway in Da Lat featuring hiking, coffee tasting, and outdoor games.', 'Accommodation, Breakfast, Activities', 'Da Lat', 11.9407, 108.4452, '2024-12-07 08:00:00+07', 900000, 80, 'green', 'Escape the hustle of the city and enjoy a refreshing weekend in Da Lat.', 'invite', 'instant', 30, 'live', now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO event_photos (event_id, storage_path, sort_order) VALUES
('evt_001', 'event-photos/evt_001/cover.jpg', 0),
('evt_001', 'event-photos/evt_001/gallery_1.jpg', 1),
('evt_001', 'event-photos/evt_001/gallery_2.jpg', 2),
('evt_002', 'event-photos/evt_002/cover.jpg', 0),
('evt_002', 'event-photos/evt_002/gallery_1.jpg', 1),
('evt_003', 'event-photos/evt_003/cover.jpg', 0),
('evt_003', 'event-photos/evt_003/gallery_1.jpg', 1),
('evt_004', 'event-photos/evt_004/cover.jpg', 0),
('evt_004', 'event-photos/evt_004/gallery_1.jpg', 1),
('evt_004', 'event-photos/evt_004/gallery_2.jpg', 2)
ON CONFLICT (id) DO NOTHING;
