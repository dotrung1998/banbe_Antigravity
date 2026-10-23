-- 199 — Phase 2 core loops (docs/impl/phase2-core-loops.md): L1 event reminders, L2 guest recap + private feedback,
-- L3 host recap (+ follows.created_at), L4 bundled follow-host alerts.
--
-- Switches (app_feature_flag_defs, 194): event_reminders ON (transactional, in-app, opt-out per kind);
-- event_recap, host_recap, follow_alerts OFF (new data or new use of data: policy B12, docs/policy-retention-draft.md).
-- Everything here only INSERTS notifications (localized by 142's trigger, queued for push by 194 when push is on,
-- quiet hours and mutes honoured there); nothing sends email.
--
-- Rollback: supabase/rollbacks/20261230000199_199_revert_core_loops.sql (kept OUT of migrations/).

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('event_reminders', 'L1: day-before and ~3h-before reminders for ticket holders (in-app; push when push is on)', '199'),
  ('event_recap', 'L2: "event has ended" recap for guests + private feedback to the host', '199'),
  ('host_recap', 'L3: host recap after an event (turnout, new followers, repeat guests, feedback)', '199'),
  ('follow_alerts', 'L4: one bundled alert a day when hosts you follow publish', '199')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES
  ('event_reminders', true), ('event_recap', false), ('host_recap', false), ('follow_alerts', false)
ON CONFLICT (key) DO NOTHING;

-- A booking that is a real ticket for its holder.
CREATE OR REPLACE FUNCTION public.booking_is_ticket(p_status booking_status)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_status IN ('confirmed', 'attended') $$;
REVOKE ALL ON FUNCTION public.booking_is_ticket(booking_status) FROM PUBLIC, anon, authenticated;

-- "19:00" in Vietnam, "7:00 PM" in the US, always in the event's own zone (195).
CREATE OR REPLACE FUNCTION public.event_local_time_text(p_starts_at timestamptz, p_tz text, p_country text)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT to_char(p_starts_at AT TIME ZONE coalesce(p_tz, 'Asia/Ho_Chi_Minh'),
                 CASE WHEN upper(coalesce(p_country, '')) = 'US' THEN 'FMHH12:MI AM' ELSE 'HH24:MI' END)
$$;
REVOKE ALL ON FUNCTION public.event_local_time_text(timestamptz, text, text) FROM PUBLIC, anon, authenticated;

-- Is this kind muted by this person (062's list, enforced on the server)?
CREATE OR REPLACE FUNCTION public.kind_muted(p_user uuid, p_kind text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = p_user AND p_kind = ANY (coalesce(p.muted_notification_kinds, '{}'::text[])))
$$;
REVOKE ALL ON FUNCTION public.kind_muted(uuid, text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- L1 reminders
CREATE TABLE IF NOT EXISTS public.event_reminder_log (
  booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('event_reminder_day', 'event_reminder_soon')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (booking_id, kind)
);
ALTER TABLE public.event_reminder_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.event_reminder_log FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.event_reminder_log TO service_role;

CREATE OR REPLACE FUNCTION public.send_event_reminders(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  r record;
  v_sent int := 0;
  v_kind text;
  v_venue text;
  v_time text;
BEGIN
  IF NOT public.app_flag('event_reminders', true) THEN RETURN 0; END IF;
  FOR r IN
    SELECT b.id AS booking_id, b.user_id, e.id AS event_id, e.name, e.starts_at, e.tz, e.country_code,
           nullif(trim(coalesce(nullif(trim(e.area), ''), e.city)), '') AS venue,
           CASE WHEN e.starts_at BETWEEN p_now + interval '23 hours' AND p_now + interval '25 hours' THEN 'event_reminder_day'
                WHEN e.starts_at BETWEEN p_now + interval '150 minutes' AND p_now + interval '210 minutes' THEN 'event_reminder_soon' END AS kind
      FROM bookings b JOIN events e ON e.id = b.event_id
     WHERE public.booking_is_ticket(b.status) AND b.cancelled_at IS NULL AND b.user_id IS NOT NULL
       AND e.status = 'live' AND e.cancelled_at IS NULL AND e.starts_at IS NOT NULL
       AND e.starts_at BETWEEN p_now + interval '150 minutes' AND p_now + interval '25 hours'
       AND b.created_at < p_now - interval '30 minutes'
  LOOP
    v_kind := r.kind;
    CONTINUE WHEN v_kind IS NULL;
    CONTINUE WHEN EXISTS (SELECT 1 FROM event_reminder_log l WHERE l.booking_id = r.booking_id AND l.kind = v_kind);
    INSERT INTO event_reminder_log (booking_id, kind) VALUES (r.booking_id, v_kind);
    CONTINUE WHEN public.kind_muted(r.user_id, v_kind);
    v_time := public.event_local_time_text(r.starts_at, r.tz, r.country_code);
    v_venue := CASE WHEN r.venue IS NULL THEN '' ELSE ' tại ' || r.venue END;
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (r.user_id, v_kind,
            CASE v_kind WHEN 'event_reminder_day' THEN 'Sự kiện ngày mai' ELSE 'Sắp bắt đầu' END,
            r.name || ' bắt đầu lúc ' || v_time || CASE v_kind WHEN 'event_reminder_day' THEN ' ngày mai' ELSE '' END
              || v_venue || '. Vé của bạn có trong ứng dụng.',
            jsonb_build_object('event_id', r.event_id, 'booking_id', r.booking_id));
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END;
$$;
REVOKE ALL ON FUNCTION public.send_event_reminders(timestamptz) FROM PUBLIC, anon, authenticated;
SELECT cron.schedule('bb_event_reminders', '*/10 * * * *', $cmd$ SELECT public.send_event_reminders(); $cmd$);

-- ---------------------------------------------------------------- L2 recap + feedback
CREATE TABLE IF NOT EXISTS public.event_feedback (
  event_id text NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating smallint NOT NULL CHECK (rating IN (-1, 1)),
  note text NOT NULL DEFAULT '' CHECK (length(note) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, user_id)
);
ALTER TABLE public.event_feedback ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.event_feedback FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.event_feedback TO service_role;

-- Private to the host, never public. A guest with a ticket may answer for 14 days after the start.
CREATE OR REPLACE FUNCTION public.submit_event_feedback(p_event_id text, p_rating int, p_note text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ev events%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.app_flag('event_recap', false) THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AVAILABLE'); END IF;
  IF p_rating NOT IN (-1, 1) OR length(coalesce(p_note, '')) > 500 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  SELECT * INTO v_ev FROM events WHERE id = p_event_id;
  IF NOT FOUND OR v_ev.status <> 'ended' OR v_ev.starts_at IS NULL OR v_ev.starts_at < now() - interval '14 days' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_OPEN');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM bookings b WHERE b.event_id = p_event_id AND b.user_id = v_uid
                   AND public.booking_is_ticket(b.status) AND b.cancelled_at IS NULL) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_TICKET');
  END IF;
  INSERT INTO event_feedback (event_id, user_id, rating, note) VALUES (p_event_id, v_uid, p_rating, trim(coalesce(p_note, '')))
  ON CONFLICT (event_id, user_id) DO UPDATE SET rating = EXCLUDED.rating, note = EXCLUDED.note, updated_at = now();
  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.submit_event_feedback(text, int, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_event_feedback(text, int, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_event_feedback(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  r event_feedback%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT * INTO r FROM event_feedback WHERE event_id = p_event_id AND user_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('success', true, 'feedback', NULL); END IF;
  RETURN jsonb_build_object('success', true, 'feedback', jsonb_build_object('rating', r.rating, 'note', r.note));
END;
$$;
REVOKE ALL ON FUNCTION public.get_my_event_feedback(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_event_feedback(text) TO authenticated;

-- Host side: nothing until 3 or more guests answered; then counts and notes without names, in random order.
CREATE OR REPLACE FUNCTION public.event_feedback_summary_of(p_event_id text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT CASE WHEN count(*) < 3 THEN jsonb_build_object('responses', count(*), 'hidden', true)
         ELSE jsonb_build_object('responses', count(*), 'hidden', false,
                'up', count(*) FILTER (WHERE rating = 1), 'down', count(*) FILTER (WHERE rating = -1),
                'notes', coalesce((SELECT jsonb_agg(n.note ORDER BY random()) FROM public.event_feedback n
                                    WHERE n.event_id = p_event_id AND length(n.note) > 0), '[]'::jsonb))
         END
    FROM public.event_feedback WHERE event_id = p_event_id
$$;
REVOKE ALL ON FUNCTION public.event_feedback_summary_of(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_event_feedback_summary(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.is_event_host(p_event_id) THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  RETURN jsonb_build_object('success', true) || public.event_feedback_summary_of(p_event_id);
END;
$$;
REVOKE ALL ON FUNCTION public.get_event_feedback_summary(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_event_feedback_summary(text) TO authenticated;

-- ---------------------------------------------------------------- L3 host recap
-- Existing follows have no known date: they stay NULL (never counted as "new"); new follows get now().
ALTER TABLE public.follows ADD COLUMN IF NOT EXISTS created_at timestamptz;
ALTER TABLE public.follows ALTER COLUMN created_at SET DEFAULT now();

CREATE OR REPLACE FUNCTION public.get_host_event_recap(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_ev events%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.is_event_host(p_event_id) THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED'); END IF;
  IF NOT public.app_flag('host_recap', false) THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AVAILABLE'); END IF;
  SELECT * INTO v_ev FROM events WHERE id = p_event_id;
  RETURN jsonb_build_object(
    'success', true,
    'event_id', v_ev.id, 'status', v_ev.status, 'capacity', v_ev.capacity,
    'confirmed_seats', (SELECT coalesce(sum(b.qty), 0) FROM bookings b WHERE b.event_id = p_event_id
                          AND public.booking_is_ticket(b.status) AND b.cancelled_at IS NULL),
    'checked_in', (SELECT count(*) FROM check_ins c JOIN bookings b ON b.id = c.booking_id WHERE b.event_id = p_event_id),
    'new_followers', (SELECT count(*) FROM follows f WHERE f.organizer_id = v_ev.organizer_id
                        AND f.created_at IS NOT NULL AND f.created_at >= coalesce(v_ev.submitted_at, v_ev.created_at)),
    'repeat_guests', (SELECT count(DISTINCT b.user_id) FROM bookings b
                        WHERE b.event_id = p_event_id AND public.booking_is_ticket(b.status) AND b.cancelled_at IS NULL
                          AND EXISTS (SELECT 1 FROM bookings b2 JOIN events e2 ON e2.id = b2.event_id
                                       WHERE b2.user_id = b.user_id AND e2.organizer_id = v_ev.organizer_id
                                         AND e2.id <> p_event_id AND public.booking_is_ticket(b2.status)
                                         AND e2.starts_at < v_ev.starts_at)),
    'photos', (SELECT count(*) FROM event_photos p WHERE p.event_id = p_event_id),
    'feedback', public.event_feedback_summary_of(p_event_id)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_host_event_recap(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_host_event_recap(text) TO authenticated;

-- ---------------------------------------------------------------- L2 + L3 on "ended"
CREATE OR REPLACE FUNCTION public.events_on_ended()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_host uuid;
BEGIN
  IF public.app_flag('event_recap', false) THEN
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    SELECT DISTINCT b.user_id, 'event_recap', 'Sự kiện đã kết thúc',
           NEW.name || ' đã kết thúc. Xem ảnh, theo dõi host và cho host biết cảm nhận của bạn.',
           jsonb_build_object('event_id', NEW.id)
      FROM bookings b
     WHERE b.event_id = NEW.id AND public.booking_is_ticket(b.status) AND b.cancelled_at IS NULL AND b.user_id IS NOT NULL
       AND NOT public.kind_muted(b.user_id, 'event_recap');
  END IF;
  IF public.app_flag('host_recap', false) THEN
    SELECT coalesce(o.owner_id, o.user_id) INTO v_host FROM organizers o WHERE o.id = NEW.organizer_id;
    IF v_host IS NOT NULL AND NOT public.kind_muted(v_host, 'host_event_recap') THEN
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (v_host, 'host_event_recap', 'Tổng kết sự kiện',
              NEW.name || ' đã kết thúc. Xem tổng kết và tổ chức lại nếu bạn muốn.',
              jsonb_build_object('event_id', NEW.id));
    END IF;
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'events_on_ended: %', SQLERRM;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.events_on_ended() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS events_on_ended ON public.events;
CREATE TRIGGER events_on_ended AFTER UPDATE OF status ON public.events
  FOR EACH ROW WHEN (NEW.status = 'ended' AND OLD.status IS DISTINCT FROM 'ended')
  EXECUTE FUNCTION public.events_on_ended();

-- ---------------------------------------------------------------- L4 follow alerts
CREATE TABLE IF NOT EXISTS public.follow_alert_queue (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_id text NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, event_id)
);
ALTER TABLE public.follow_alert_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.follow_alert_queue FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.follow_alert_queue TO service_role;

CREATE OR REPLACE FUNCTION public.events_queue_follow_alerts()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF public.app_flag('follow_alerts', false) THEN
    INSERT INTO follow_alert_queue (user_id, event_id)
    SELECT f.user_id, NEW.id FROM follows f
     WHERE f.organizer_id = NEW.organizer_id
       AND f.user_id NOT IN (SELECT o.owner_id FROM organizers o WHERE o.id = NEW.organizer_id AND o.owner_id IS NOT NULL
                             UNION SELECT o.user_id FROM organizers o WHERE o.id = NEW.organizer_id AND o.user_id IS NOT NULL)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'events_queue_follow_alerts: %', SQLERRM;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.events_queue_follow_alerts() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS events_queue_follow_alerts ON public.events;
CREATE TRIGGER events_queue_follow_alerts AFTER UPDATE OF status ON public.events
  FOR EACH ROW WHEN (NEW.status = 'live' AND OLD.status IS DISTINCT FROM 'live' AND NEW.visibility = 'public')
  EXECUTE FUNCTION public.events_queue_follow_alerts();

-- The person's own clock: their Rewards zone if set, else their newest device's zone, else their market's.
CREATE OR REPLACE FUNCTION public.user_local_zone(p_user uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT coalesce(
    (SELECT s.tz FROM public.reward_user_settings s WHERE s.user_id = p_user AND s.tz IS NOT NULL),
    (SELECT t.timezone FROM public.device_push_tokens t WHERE t.user_id = p_user AND t.timezone IS NOT NULL ORDER BY t.updated_at DESC LIMIT 1),
    CASE (SELECT p.market FROM public.profiles p WHERE p.id = p_user) WHEN 'US' THEN 'America/New_York' ELSE 'Asia/Ho_Chi_Minh' END)
$$;
REVOKE ALL ON FUNCTION public.user_local_zone(uuid) FROM PUBLIC, anon, authenticated;

-- Hourly: at most one bundled alert per person per 24 h, between 09:00 and 20:00 on their clock, upcoming events only.
CREATE OR REPLACE FUNCTION public.send_follow_alerts(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  u record;
  v_sent int := 0;
  v_hour int;
  v_n int;
  v_first record;
  v_hosts text;
BEGIN
  -- Stale rows go first: events that started, ended, were cancelled or hidden.
  DELETE FROM follow_alert_queue q USING events e
   WHERE e.id = q.event_id AND (e.status <> 'live' OR e.visibility <> 'public' OR e.cancelled_at IS NOT NULL
                                OR e.starts_at IS NULL OR e.starts_at <= p_now);
  IF NOT public.app_flag('follow_alerts', false) THEN RETURN 0; END IF;
  FOR u IN SELECT DISTINCT q.user_id FROM follow_alert_queue q LOOP
    IF public.kind_muted(u.user_id, 'follow_alert') THEN
      DELETE FROM follow_alert_queue WHERE user_id = u.user_id;
      CONTINUE;
    END IF;
    v_hour := extract(hour FROM p_now AT TIME ZONE public.user_local_zone(u.user_id));
    CONTINUE WHEN v_hour < 9 OR v_hour >= 20;
    CONTINUE WHEN EXISTS (SELECT 1 FROM notifications n WHERE n.recipient_id = u.user_id AND n.kind = 'follow_alert'
                            AND n.created_at > p_now - interval '24 hours');
    SELECT count(*) INTO v_n FROM follow_alert_queue WHERE user_id = u.user_id;
    SELECT e.id, e.name, o.name AS host INTO v_first
      FROM follow_alert_queue q JOIN events e ON e.id = q.event_id JOIN organizers o ON o.id = e.organizer_id
     WHERE q.user_id = u.user_id ORDER BY e.starts_at LIMIT 1;
    SELECT string_agg(DISTINCT o.name, ', ') INTO v_hosts
      FROM follow_alert_queue q JOIN events e ON e.id = q.event_id JOIN organizers o ON o.id = e.organizer_id
     WHERE q.user_id = u.user_id;
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (u.user_id, 'follow_alert', 'Mới từ host bạn theo dõi',
            CASE WHEN v_n = 1 THEN v_first.host || ': ' || v_first.name || '.'
                 ELSE v_n || ' sự kiện mới từ ' || v_hosts || '.' END,
            jsonb_build_object('event_id', v_first.id, 'count', v_n));
    DELETE FROM follow_alert_queue WHERE user_id = u.user_id;
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END;
$$;
REVOKE ALL ON FUNCTION public.send_follow_alerts(timestamptz) FROM PUBLIC, anon, authenticated;
SELECT cron.schedule('bb_follow_alerts', '7 * * * *', $cmd$ SELECT public.send_follow_alerts(); $cmd$);

-- ---------------------------------------------------------------- English (142's tables)
INSERT INTO public.notification_i18n_titles (vi, en) VALUES
  ($q$Sự kiện ngày mai$q$, $q$Your event is tomorrow$q$),
  ($q$Sắp bắt đầu$q$, $q$Starting soon$q$),
  ($q$Sự kiện đã kết thúc$q$, $q$Your event has ended$q$),
  ($q$Tổng kết sự kiện$q$, $q$Event recap$q$),
  ($q$Mới từ host bạn theo dõi$q$, $q$New from hosts you follow$q$)
ON CONFLICT (vi) DO UPDATE SET en = EXCLUDED.en;
INSERT INTO public.notification_i18n_body_rules (pos, vi_pattern, en_replacement) VALUES
  (210, $q$^(.*) bắt đầu lúc ([0-9:APM ]+) ngày mai tại (.*)\. Vé của bạn có trong ứng dụng\.$$q$, $q$\1 starts tomorrow at \2 at \3. Your ticket is in the app.$q$),
  (211, $q$^(.*) bắt đầu lúc ([0-9:APM ]+) ngày mai\. Vé của bạn có trong ứng dụng\.$$q$, $q$\1 starts tomorrow at \2. Your ticket is in the app.$q$),
  (212, $q$^(.*) bắt đầu lúc ([0-9:APM ]+) tại (.*)\. Vé của bạn có trong ứng dụng\.$$q$, $q$\1 starts at \2 at \3. Your ticket is in the app.$q$),
  (213, $q$^(.*) bắt đầu lúc ([0-9:APM ]+)\. Vé của bạn có trong ứng dụng\.$$q$, $q$\1 starts at \2. Your ticket is in the app.$q$),
  (214, $q$^(.*) đã kết thúc\. Xem ảnh, theo dõi host và cho host biết cảm nhận của bạn\.$$q$, $q$\1 has ended. See the photos, follow the host and tell them how it went.$q$),
  (215, $q$^(.*) đã kết thúc\. Xem tổng kết và tổ chức lại nếu bạn muốn\.$$q$, $q$\1 has ended. See the recap and run it again if you like.$q$),
  (216, $q$^([0-9]+) sự kiện mới từ (.*)\.$$q$, $q$\1 new events from \2.$q$)
ON CONFLICT (pos) DO UPDATE SET vi_pattern = EXCLUDED.vi_pattern, en_replacement = EXCLUDED.en_replacement;
