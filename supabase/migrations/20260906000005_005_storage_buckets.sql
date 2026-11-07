-- Migration: Storage Buckets & Policies
-- Description: Creates event-photos (public) and pay-qr (private) buckets, and defines access policies.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES 
  ('event-photos', 'event-photos', true, 52428800, ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('pay-qr', 'pay-qr', false, 1048576, ARRAY['image/jpeg', 'image/png'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "event_photos_public_read" ON storage.objects;
CREATE POLICY "event_photos_public_read"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'event-photos');

DROP POLICY IF EXISTS "event_photos_host_insert" ON storage.objects;
CREATE POLICY "event_photos_host_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'event-photos' AND
  EXISTS (
    SELECT 1 FROM organizers o
    WHERE o.owner_id = auth.uid() OR o.user_id = auth.uid()
  )
);

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
      AND b.status IN ('confirmed', 'attended')
    )
  )
);

DROP POLICY IF EXISTS "pay_qr_organizer_owner_insert" ON storage.objects;
CREATE POLICY "pay_qr_organizer_owner_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'pay-qr' AND
  EXISTS (
    SELECT 1 FROM organizers o
    WHERE o.id = split_part((objects).name, '/', 1)
    AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);
