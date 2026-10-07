-- Migration 166: host announcements to ticket-holders (quick notifications during the event).
--  * messages.announcement_category: non-null marks a host announcement (chat renders it red).
--  * event_announcements: audit + rate-limit log (organizer/admin read-only).
--  * send_event_announcement(): host/admin only, window = 24h before start .. 12h after start
--    (mirrors src/lib/eventReminder.js), max 10 per event per hour. Writes one chat message per
--    confirmed ticket-holder (creating the host<->guest thread if needed).
--  * notify_new_message(): announcements notify with kind 'event_announcement' (distinct from
--    'new_message') so clients can style them differently.

ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS announcement_category text;

CREATE TABLE IF NOT EXISTS public.event_announcements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  sender_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  category text NOT NULL,
  template_id text,
  body text NOT NULL,
  recipient_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS event_announcements_event_created_idx ON public.event_announcements (event_id, created_at DESC);
ALTER TABLE public.event_announcements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "event_announcements_select_host" ON public.event_announcements;
CREATE POLICY "event_announcements_select_host" ON public.event_announcements FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.events e JOIN public.organizers o ON o.id = e.organizer_id
          WHERE e.id = event_announcements.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid()))
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
);

CREATE OR REPLACE FUNCTION public.send_event_announcement(
  p_event text, p_category text, p_body text, p_template_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ev events%ROWTYPE;
  v_body text := btrim(COALESCE(p_body, ''));
  v_cat text := lower(btrim(COALESCE(p_category, '')));
  r record;
  v_thread uuid;
  v_sent int := 0;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF v_cat NOT IN ('timing','arrival','venue','safety','wrapup','custom') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_CATEGORY');
  END IF;
  IF char_length(v_body) < 1 OR char_length(v_body) > 300 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_BODY');
  END IF;

  SELECT * INTO v_ev FROM events WHERE id = p_event OR slug = p_event OR key = p_event;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND'); END IF;

  IF NOT EXISTS (SELECT 1 FROM organizers o WHERE o.id = v_ev.organizer_id AND (o.owner_id = v_uid OR o.user_id = v_uid))
     AND NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = v_uid AND p.role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_ev.status <> 'live' OR v_ev.starts_at IS NULL
     OR now() < v_ev.starts_at - interval '24 hours' OR now() > v_ev.starts_at + interval '12 hours' THEN
    RETURN jsonb_build_object('success', false, 'error', 'OUTSIDE_WINDOW');
  END IF;

  IF (SELECT count(*) FROM event_announcements WHERE event_id = v_ev.id AND created_at > now() - interval '1 hour') >= 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'RATE_LIMITED');
  END IF;

  FOR r IN
    SELECT DISTINCT COALESCE(b.claimed_by_user_id, b.user_id) AS guest_id
    FROM bookings b
    WHERE b.event_id = v_ev.id AND b.status = 'confirmed'
      AND COALESCE(b.claimed_by_user_id, b.user_id) IS NOT NULL
      AND COALESCE(b.claimed_by_user_id, b.user_id) <> v_uid
  LOOP
    INSERT INTO threads (event_id, guest_id, organizer_id) VALUES (v_ev.id, r.guest_id, v_ev.organizer_id)
      ON CONFLICT (event_id, guest_id) DO NOTHING;
    SELECT id INTO v_thread FROM threads WHERE event_id = v_ev.id AND guest_id = r.guest_id;
    INSERT INTO messages (thread_id, sender_id, body, kind, announcement_category)
      VALUES (v_thread, v_uid, v_body, 'text', v_cat);
    v_sent := v_sent + 1;
  END LOOP;

  INSERT INTO event_announcements (event_id, sender_id, category, template_id, body, recipient_count)
    VALUES (v_ev.id, v_uid, v_cat, left(p_template_id, 40), v_body, v_sent);

  RETURN jsonb_build_object('success', true, 'sent', v_sent);
END;
$$;
REVOKE ALL ON FUNCTION public.send_event_announcement(text, text, text, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_event_announcement(text, text, text, text) TO authenticated;

-- Same as migration 021, plus the announcement branch (guest-bound only; an announcement is
-- always sent by the host, so the guest->organizer branch is unchanged).
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
    IF NEW.announcement_category IS NOT NULL THEN
      INSERT INTO public.notifications (recipient_id, kind, title, body, data)
      VALUES (v_thread.guest_id, 'event_announcement', 'Thông báo từ host', v_preview,
              jsonb_build_object('thread_id', NEW.thread_id, 'event_id', v_thread.event_id, 'category', NEW.announcement_category));
    ELSE
      INSERT INTO public.notifications (recipient_id, kind, title, body, data)
      VALUES (v_thread.guest_id, 'new_message', 'Tin nhắn mới', v_preview,
              jsonb_build_object('thread_id', NEW.thread_id, 'event_id', v_thread.event_id));
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
