BEGIN;

CREATE POLICY "bookings_insert_guest" ON public.bookings FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);
GRANT INSERT ON public.bookings TO authenticated;

COMMIT;
