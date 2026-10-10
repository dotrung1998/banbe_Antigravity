-- 176: sync the "Cancelled / expired" list's hidden rows across devices.
-- Until now "Delete" (and the 30-day auto-clear) only hid a row on the device used, so web and
-- iOS disagreed. This stores only the per-user "hidden" fact; the booking row itself (the record
-- behind any refund claim) is never touched.
CREATE TABLE IF NOT EXISTS public.ticket_list_hidden (
  user_id    uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  hidden_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, booking_id)
);

ALTER TABLE public.ticket_list_hidden ENABLE ROW LEVEL SECURITY;

CREATE POLICY ticket_list_hidden_select ON public.ticket_list_hidden
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY ticket_list_hidden_insert ON public.ticket_list_hidden
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY ticket_list_hidden_delete ON public.ticket_list_hidden
  FOR DELETE TO authenticated USING (user_id = auth.uid());

REVOKE ALL ON public.ticket_list_hidden FROM PUBLIC, anon;
GRANT SELECT, INSERT, DELETE ON public.ticket_list_hidden TO authenticated;
