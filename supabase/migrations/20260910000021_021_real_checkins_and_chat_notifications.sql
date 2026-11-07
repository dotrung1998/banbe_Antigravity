-- Migration: wire check-in and chat to real accounts, with notifications.
--
-- 1. profiles_select_for_organizer: an organizer could already read the
--    *bookings* for their own events (bookings_select_host), but not the
--    guest's *profile* row behind it — profiles was select-own only. That
--    meant a real check-in list or chat thread had a real guest id but no
--    name to show. This adds exactly that one extra read path: an organizer
--    may read the profile of anyone who has booked one of their events, or
--    who is on the other end of one of their chat threads.
--
-- 2. check_in_guest() now writes an in-app notification to the guest who was
--    just checked in, in the same transaction as the status flip — so a
--    check-in can never happen without the guest being told.
--
-- 3. A trigger on `messages` writes an in-app notification to whichever side
--    of the thread did *not* just send the message. This covers every
--    insert path (direct client insert or a future RPC) rather than relying
--    on the client to remember to notify.
--
-- Email delivery for both is handled outside the database by
-- api/notify-check-in.js and api/notify-chat-message.js, which re-derive
-- their recipient from the database using the caller's verified session
-- rather than trusting the client — the same pattern as
-- api/notify-name-change.js.

DROP POLICY IF EXISTS "profiles_select_for_organizer" ON public.profiles;
CREATE POLICY "profiles_select_for_organizer" ON public.profiles FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.bookings b
    JOIN public.events e ON e.id = b.event_id
    JOIN public.organizers o ON o.id = e.organizer_id
    WHERE b.user_id = profiles.id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
  OR EXISTS (
    SELECT 1 FROM public.threads t
    JOIN public.organizers o ON o.id = t.organizer_id
    WHERE t.guest_id = profiles.id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);

CREATE OR REPLACE FUNCTION public.check_in_guest(p_reservation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_event events%ROWTYPE;
  v_is_host boolean;
  v_is_admin boolean;
  v_checkin_id uuid;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_reservation_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
  END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;

  SELECT EXISTS(
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_booking.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) INTO v_is_host;

  SELECT EXISTS(
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ) INTO v_is_admin;

  IF NOT v_is_host AND NOT v_is_admin THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;

  IF v_booking.status NOT IN ('confirmed', 'attended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking is not eligible for check-in');
  END IF;

  INSERT INTO check_ins (booking_id, reservation_id, event_id, checked_in_by)
  VALUES (v_booking.id, v_booking.id, v_booking.event_id, auth.uid())
  ON CONFLICT (booking_id) DO NOTHING
  RETURNING id INTO v_checkin_id;

  IF v_checkin_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Guest already checked in');
  END IF;

  UPDATE bookings SET status = 'attended' WHERE id = v_booking.id;
  IF v_booking.user_id IS NOT NULL THEN
    UPDATE profiles SET attended_count = COALESCE(attended_count, 0) + 1 WHERE id = v_booking.user_id;

    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_booking.user_id,
      'checked_in',
      'Bạn đã được điểm danh',
      COALESCE(v_event.name, 'Sự kiện') || ' vừa xác nhận bạn đã có mặt.',
      jsonb_build_object('event_id', v_booking.event_id, 'booking_id', v_booking.id)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'booking_id', v_booking.id);
END;
$$;
REVOKE EXECUTE ON FUNCTION check_in_guest FROM anon;
GRANT EXECUTE ON FUNCTION check_in_guest TO authenticated;

CREATE OR REPLACE FUNCTION public.notify_new_message()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_thread threads%ROWTYPE;
  v_sender_name text;
  v_preview text;
BEGIN
  SELECT * INTO v_thread FROM threads WHERE id = NEW.thread_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  SELECT NULLIF(trim(display_name), '') INTO v_sender_name FROM profiles WHERE id = NEW.sender_id;
  v_sender_name := COALESCE(v_sender_name, 'Một người dùng');
  v_preview := v_sender_name || ': ' || left(NEW.body, 140);

  IF NEW.sender_id = v_thread.guest_id THEN
    -- Guest sent it — notify whichever profile(s) actually own the organizer.
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    SELECT DISTINCT uid, 'new_message', 'Tin nhắn mới', v_preview,
           jsonb_build_object('thread_id', NEW.thread_id, 'event_id', v_thread.event_id)
    FROM (
      SELECT owner_id AS uid FROM organizers WHERE id = v_thread.organizer_id AND owner_id IS NOT NULL
      UNION
      SELECT user_id AS uid FROM organizers WHERE id = v_thread.organizer_id AND user_id IS NOT NULL
    ) recipients
    WHERE uid <> NEW.sender_id;
  ELSIF v_thread.guest_id IS NOT NULL THEN
    -- Organizer (or admin) sent it — notify the guest.
    INSERT INTO public.notifications (recipient_id, kind, title, body, data)
    VALUES (
      v_thread.guest_id, 'new_message', 'Tin nhắn mới', v_preview,
      jsonb_build_object('thread_id', NEW.thread_id, 'event_id', v_thread.event_id)
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_message_created ON public.messages;
CREATE TRIGGER on_message_created
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_message();
