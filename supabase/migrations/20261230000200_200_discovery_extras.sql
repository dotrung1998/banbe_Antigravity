-- 200 — Phase 3 server pieces (docs/impl/phase3-extras.md).
--
-- L5 weekly "This weekend" digest: PROMOTIONAL, so it is opt-in twice over and fully inert today:
--   * switch `weekly_digest` seeded OFF (needs legal review: Decree 91/2020, CAN-SPAM; docs/policy-retention-draft.md);
--   * per person `notification_preferences.digest_opt_in`, default false, changed only by the person;
--   * every change is logged append-only in notification_consent_log (Decree 91 asks to keep consent records ≥ 1 year);
--   * sent Thursday 18:00–18:59 on the person's own clock, at most once per ISO week, NEVER when there is nothing real
--     to show (no live public events this weekend in their market). Push only with the separate promo_push opt-in (194).
-- L6/L7/L8 are client features; their switches are defined here so admins can see and flip them:
--   intent_foryou (L6), live_activity (L7, iOS Lock Screen card), market_share (L8, Zalo/SMS share targets). All OFF.
--
-- Rollback: supabase/rollbacks/20261230000200_200_revert_discovery_extras.sql (kept OUT of migrations/).

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('weekly_digest', 'L5: opt-in Thursday digest of this weekend''s events (promotional; legal review first)', '200'),
  ('intent_foryou', 'L6: For You wording from the onboarding goal (stated answers only)', '200'),
  ('live_activity', 'L7: event-day card on the iPhone Lock Screen (local Live Activity)', '200'),
  ('market_share', 'L8: Zalo (Vietnam) and Text-a-friend (US) share targets', '200')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES
  ('weekly_digest', false), ('intent_foryou', false), ('live_activity', false), ('market_share', false)
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------- consent
ALTER TABLE public.notification_preferences ADD COLUMN IF NOT EXISTS digest_opt_in boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS public.notification_consent_log (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  consent text NOT NULL CHECK (consent IN ('digest_opt_in', 'promo_push')),
  enabled boolean NOT NULL,
  source text NOT NULL DEFAULT 'app',
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.notification_consent_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_consent_log FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.notification_consent_log TO service_role;
REVOKE ALL ON SEQUENCE public.notification_consent_log_id_seq FROM PUBLIC, anon, authenticated;

-- Append-only: no client or server path updates or deletes a consent record (account deletion cascades).
CREATE OR REPLACE FUNCTION public.notification_consent_log_append_only()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'APPEND_ONLY'; END;
$$;
DROP TRIGGER IF EXISTS notification_consent_log_append_only ON public.notification_consent_log;
CREATE TRIGGER notification_consent_log_append_only BEFORE UPDATE ON public.notification_consent_log
  FOR EACH ROW EXECUTE FUNCTION public.notification_consent_log_append_only();

-- promo_push (194) also gets its consent record from now on. Same signature and result as 194.
CREATE OR REPLACE FUNCTION public.set_my_promo_push(p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF p_enabled IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE'); END IF;
  INSERT INTO notification_preferences (user_id, promo_push, updated_at) VALUES (auth.uid(), p_enabled, now())
  ON CONFLICT (user_id) DO UPDATE SET promo_push = EXCLUDED.promo_push, updated_at = now();
  INSERT INTO notification_consent_log (user_id, consent, enabled) VALUES (auth.uid(), 'promo_push', p_enabled);
  RETURN jsonb_build_object('success', true, 'promo_push', p_enabled);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_my_digest_opt_in(p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF p_enabled IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE'); END IF;
  IF p_enabled AND NOT public.app_flag('weekly_digest', false) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AVAILABLE');   -- turning OFF always works
  END IF;
  INSERT INTO notification_preferences (user_id, digest_opt_in, updated_at) VALUES (auth.uid(), p_enabled, now())
  ON CONFLICT (user_id) DO UPDATE SET digest_opt_in = EXCLUDED.digest_opt_in, updated_at = now();
  INSERT INTO notification_consent_log (user_id, consent, enabled) VALUES (auth.uid(), 'digest_opt_in', p_enabled);
  RETURN jsonb_build_object('success', true, 'digest_opt_in', p_enabled);
END;
$$;
REVOKE ALL ON FUNCTION public.set_my_digest_opt_in(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_digest_opt_in(boolean) TO authenticated;

-- Same keys as 194 plus digest_opt_in (old clients ignore the extra key).
CREATE OR REPLACE FUNCTION public.get_my_notification_preferences()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  r notification_preferences%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT * INTO r FROM notification_preferences p WHERE p.user_id = auth.uid();
  RETURN jsonb_build_object('success', true,
    'promo_push', coalesce(r.promo_push, false),
    'digest_opt_in', coalesce(r.digest_opt_in, false));
END;
$$;

-- ---------------------------------------------------------------- digest
CREATE TABLE IF NOT EXISTS public.weekly_digest_log (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  iso_week text NOT NULL,
  events_count int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, iso_week)
);
ALTER TABLE public.weekly_digest_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.weekly_digest_log FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.weekly_digest_log TO service_role;

-- The weekend (Fri 00:00 → Mon 00:00) that a local Thursday belongs to, as instants in that zone.
CREATE OR REPLACE FUNCTION public.digest_candidates(p_user uuid, p_now timestamptz)
RETURNS TABLE (event_id text, name text, starts_at timestamptz, score int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH z AS (SELECT public.user_local_zone(p_user) AS tz),
  w AS (
    SELECT ((date_trunc('week', (p_now AT TIME ZONE z.tz))::date + 4) AT TIME ZONE z.tz) AS fri,
           ((date_trunc('week', (p_now AT TIME ZONE z.tz))::date + 7) AT TIME ZONE z.tz) AS mon
      FROM z
  ),
  me AS (
    SELECT coalesce(p.market, 'VN') AS market,
           coalesce((SELECT array_agg(x) FROM jsonb_array_elements_text(ep.event_preferences->'interests') x), '{}') AS interests
      FROM profiles p LEFT JOIN profile_event_preferences ep ON ep.user_id = p.id WHERE p.id = p_user
  )
  SELECT e.id, e.name, e.starts_at,
         (CASE WHEN EXISTS (SELECT 1 FROM follows f WHERE f.user_id = p_user AND f.organizer_id = e.organizer_id) THEN 2 ELSE 0 END
          + CASE WHEN e.cat_key = ANY (me.interests) THEN 1 ELSE 0 END)::int
    FROM events e, w, me
   WHERE e.status = 'live' AND e.visibility = 'public' AND e.cancelled_at IS NULL
     AND e.starts_at >= greatest(w.fri, p_now) AND e.starts_at < w.mon
     AND upper(coalesce(e.country_code, 'VN')) = me.market
     AND NOT EXISTS (SELECT 1 FROM bookings b WHERE b.event_id = e.id AND b.user_id = p_user AND b.cancelled_at IS NULL)
   ORDER BY 4 DESC, e.starts_at
   LIMIT 20
$$;
REVOKE ALL ON FUNCTION public.digest_candidates(uuid, timestamptz) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.send_weekly_digests(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  u record;
  v_local timestamp;
  v_week text;
  v_n int;
  v_first text;
  v_sent int := 0;
BEGIN
  IF NOT public.app_flag('weekly_digest', false) THEN RETURN 0; END IF;
  FOR u IN SELECT np.user_id FROM notification_preferences np WHERE np.digest_opt_in LOOP
    CONTINUE WHEN public.kind_muted(u.user_id, 'weekly_digest');
    v_local := p_now AT TIME ZONE public.user_local_zone(u.user_id);
    CONTINUE WHEN extract(isodow FROM v_local) <> 4 OR extract(hour FROM v_local) <> 18;
    v_week := to_char(v_local, 'IYYY-IW');
    CONTINUE WHEN EXISTS (SELECT 1 FROM weekly_digest_log l WHERE l.user_id = u.user_id AND l.iso_week = v_week);
    SELECT count(*), (array_agg(c.name ORDER BY c.score DESC, c.starts_at))[1] INTO v_n, v_first
      FROM public.digest_candidates(u.user_id, p_now) c;
    CONTINUE WHEN v_n = 0;      -- nothing real to say: say nothing
    INSERT INTO weekly_digest_log (user_id, iso_week, events_count) VALUES (u.user_id, v_week, v_n);
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (u.user_id, 'weekly_digest', 'Cuối tuần này',
            CASE WHEN v_n = 1 THEN v_first || ' diễn ra cuối tuần này.'
                 ELSE v_n || ' sự kiện cuối tuần này, có ' || v_first || '.' END,
            jsonb_build_object('screen', 'this_weekend', 'count', v_n));
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END;
$$;
REVOKE ALL ON FUNCTION public.send_weekly_digests(timestamptz) FROM PUBLIC, anon, authenticated;
SELECT cron.schedule('bb_weekly_digest', '3 * * * *', $cmd$ SELECT public.send_weekly_digests(); $cmd$);

INSERT INTO public.notification_i18n_titles (vi, en) VALUES ($q$Cuối tuần này$q$, $q$This weekend$q$)
ON CONFLICT (vi) DO UPDATE SET en = EXCLUDED.en;
INSERT INTO public.notification_i18n_body_rules (pos, vi_pattern, en_replacement) VALUES
  (220, $q$^([0-9]+) sự kiện cuối tuần này, có (.*)\.$$q$, $q$\1 events this weekend, including \2.$q$),
  (221, $q$^(.*) diễn ra cuối tuần này\.$$q$, $q$\1 is on this weekend.$q$)
ON CONFLICT (pos) DO UPDATE SET vi_pattern = EXCLUDED.vi_pattern, en_replacement = EXCLUDED.en_replacement;
