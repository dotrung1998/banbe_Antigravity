-- 196 — F1 first-party measurement (docs/retention-delight-plan.md §4 F1, docs/impl/phase0-foundations.md).
--
-- * app_events: product events from our own apps only. No vendor, no third-party tracker. Signed-in only (anon cannot
--   write, so the shipped anon key cannot be used to flood it). Every event name and every property key is
--   whitelisted in app_event_names; values must be short scalars (ids, counts, buckets); anything else is dropped.
--   Never chat, bank, preference-answer or free-text content. Kept 13 months (daily purge).
-- * Switch `app_events` (seeded OFF): while off, log_app_events stores nothing (clients also stop sending).
-- * profiles.market ('VN' | 'US' | NULL): set once from the first booked or hosted event's country, never guessed.
-- * admin_retention_report(from, to): platform admins only, aggregate only, test accounts excluded, every group
--   under 20 people hidden ('<20'). Split by market.
--
-- Rollback: supabase/rollbacks/20261230000196_196_revert_first_party_measurement.sql (kept OUT of migrations/).

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('app_events', 'First-party product measurement (app_events). Off = nothing stored', '196')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('app_events', false) ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------- market
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS market text;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_market_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_market_check CHECK (market IS NULL OR market IN ('VN', 'US'));
COMMENT ON COLUMN public.profiles.market IS
  'VN | US, set once from the first booked or hosted event''s country (migration 196). NULL = not known yet.';

CREATE OR REPLACE FUNCTION public.profile_market_from_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_user uuid;
  v_cc text;
BEGIN
  IF TG_TABLE_NAME = 'bookings' THEN
    v_user := NEW.user_id;
    SELECT upper(e.country_code) INTO v_cc FROM events e WHERE e.id = NEW.event_id;
  ELSE
    SELECT coalesce(o.owner_id, o.user_id) INTO v_user FROM organizers o WHERE o.id = NEW.organizer_id;
    v_cc := upper(NEW.country_code);
  END IF;
  IF v_user IS NOT NULL AND v_cc IN ('VN', 'US') THEN
    UPDATE profiles SET market = v_cc WHERE id = v_user AND market IS NULL;
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'profile_market_from_event: %', SQLERRM;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.profile_market_from_event() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS bookings_profile_market ON public.bookings;
CREATE TRIGGER bookings_profile_market AFTER INSERT ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.profile_market_from_event();
DROP TRIGGER IF EXISTS events_profile_market ON public.events;
CREATE TRIGGER events_profile_market AFTER INSERT ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.profile_market_from_event();

-- Backfill: the earliest booking's event country, else the earliest hosted event's country.
UPDATE public.profiles p SET market = x.cc
  FROM (
    SELECT DISTINCT ON (b.user_id) b.user_id AS id, upper(e.country_code) AS cc
      FROM public.bookings b JOIN public.events e ON e.id = b.event_id
     WHERE upper(e.country_code) IN ('VN', 'US')
     ORDER BY b.user_id, b.created_at
  ) x
 WHERE p.id = x.id AND p.market IS NULL;
UPDATE public.profiles p SET market = x.cc
  FROM (
    SELECT DISTINCT ON (coalesce(o.owner_id, o.user_id)) coalesce(o.owner_id, o.user_id) AS id, upper(e.country_code) AS cc
      FROM public.events e JOIN public.organizers o ON o.id = e.organizer_id
     WHERE upper(e.country_code) IN ('VN', 'US') AND coalesce(o.owner_id, o.user_id) IS NOT NULL
     ORDER BY coalesce(o.owner_id, o.user_id), e.created_at
  ) x
 WHERE p.id = x.id AND p.market IS NULL;

-- ---------------------------------------------------------------- events + whitelist
CREATE TABLE IF NOT EXISTS public.app_event_names (
  name text PRIMARY KEY CONSTRAINT app_event_names_shape CHECK (name ~ '^[a-z][a-z0-9_]{1,48}$'),
  props text[] NOT NULL DEFAULT '{}',
  added_in text NOT NULL DEFAULT ''
);
ALTER TABLE public.app_event_names ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_event_names FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.app_event_names TO service_role;

-- The names the web (src/lib/analytics.js) and iOS (Lib/Analytics.swift) boundaries already emit, plus the core
-- retention signals. Keep in sync with tests/fixtures/app-events.json.
INSERT INTO public.app_event_names (name, props, added_in) VALUES
  ('app_opened', '{}', '196'),
  ('event_opened', '{event_id,source}', '196'),
  ('ticket_opened', '{day_bucket}', '196'),
  ('notification_opened', '{kind,source}', '196'),
  ('share_completed', '{channel,context}', '196'),
  ('follow_tapped', '{context}', '196'),
  ('onboarding_started', '{}', '196'),
  ('onboarding_question_viewed', '{question_id}', '196'),
  ('onboarding_question_answered', '{question_id,answer_count}', '196'),
  ('onboarding_question_skipped', '{question_id}', '196'),
  ('onboarding_completed', '{answered_questions,skipped_all}', '196'),
  ('personalized_results_viewed', '{match_bucket}', '196'),
  ('first_event_opened', '{}', '196'),
  ('first_event_saved', '{}', '196'),
  ('first_reservation_started', '{}', '196'),
  ('permission_prompted', '{permission}', '196'),
  ('permission_result', '{permission,result}', '196'),
  ('public_entry_viewed', '{}', '196'),
  ('public_entry_get_started', '{}', '196'),
  ('public_entry_login', '{}', '196'),
  ('public_story_opened', '{}', '196'),
  ('public_story_completed', '{}', '196'),
  ('public_story_skipped', '{step}', '196'),
  ('guest_browse_started', '{}', '196'),
  ('guest_signin_prompt_shown', '{context}', '196'),
  ('guest_signin_prompt_accepted', '{context}', '196'),
  ('create_event_started_blank', '{}', '196'),
  ('recipe_opened', '{}', '196'),
  ('recipe_fix_tapped', '{ingredient}', '196'),
  ('submit_recipe_score', '{bucket}', '196'),
  ('schedule_opened', '{}', '196'),
  ('schedule_mode_selected', '{mode}', '196'),
  ('schedule_day_selected', '{day_bucket}', '196'),
  ('schedule_conflict_shown', '{count_bucket}', '196'),
  ('banbe_schedule_add', '{}', '196'),
  ('banbe_schedule_remove', '{}', '196'),
  ('banbe_schedule_result', '{result}', '196'),
  ('system_calendar_editor_opened', '{}', '196'),
  ('system_calendar_editor_result', '{result}', '196'),
  ('rewards_badge_celebrated', '{code}', '196'),
  ('rewards_week_milestone', '{weeks}', '196'),
  ('rewards_goal_set', '{goal}', '196')
ON CONFLICT (name) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.app_events (
  id bigserial PRIMARY KEY,
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  name text NOT NULL REFERENCES public.app_event_names(name),
  props jsonb NOT NULL DEFAULT '{}'::jsonb,
  platform text NOT NULL CHECK (platform IN ('web', 'ios')),
  market text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS app_events_created_idx ON public.app_events (created_at);
CREATE INDEX IF NOT EXISTS app_events_user_created_idx ON public.app_events (user_id, created_at);
ALTER TABLE public.app_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_events FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.app_events TO service_role;
REVOKE ALL ON SEQUENCE public.app_events_id_seq FROM PUBLIC, anon, authenticated;

-- Batch insert from a signed-in client: up to 50 events, at most 600 stored per user per hour. Unknown names, unknown
-- property keys and non-scalar / long values are dropped silently (an old client never breaks a newer server).
CREATE OR REPLACE FUNCTION public.log_app_events(p_events jsonb, p_platform text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_market text;
  v_recent int;
  v_room int;
  v_stored int := 0;
  e jsonb;
  v_name text;
  v_allowed text[];
  v_props jsonb;
  k text;
  v jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.app_flag('app_events', false) THEN RETURN jsonb_build_object('success', false, 'error', 'DISABLED'); END IF;
  IF p_platform NOT IN ('web', 'ios') OR jsonb_typeof(p_events) <> 'array' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_VALUE');
  END IF;
  SELECT count(*) INTO v_recent FROM app_events WHERE user_id = v_uid AND created_at > now() - interval '1 hour';
  v_room := least(50, greatest(0, 600 - v_recent));
  SELECT market INTO v_market FROM profiles WHERE id = v_uid;

  FOR e IN SELECT x FROM jsonb_array_elements(p_events) x LIMIT v_room LOOP
    v_name := e->>'name';
    SELECT props INTO v_allowed FROM app_event_names WHERE name = v_name;
    IF NOT FOUND THEN CONTINUE; END IF;
    v_props := '{}'::jsonb;
    IF jsonb_typeof(e->'props') = 'object' THEN
      FOR k, v IN SELECT * FROM jsonb_each(e->'props') LOOP
        IF k = ANY (v_allowed)
           AND jsonb_typeof(v) IN ('string', 'number', 'boolean')
           AND length(v #>> '{}') <= 64 THEN
          v_props := v_props || jsonb_build_object(k, v);
        END IF;
      END LOOP;
    END IF;
    INSERT INTO app_events (user_id, name, props, platform, market) VALUES (v_uid, v_name, v_props, p_platform, v_market);
    v_stored := v_stored + 1;
  END LOOP;
  RETURN jsonb_build_object('success', true, 'stored', v_stored);
END;
$$;
REVOKE ALL ON FUNCTION public.log_app_events(jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.log_app_events(jsonb, text) TO authenticated;

-- 13 months, then gone.
CREATE OR REPLACE FUNCTION public.purge_old_app_events()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  DELETE FROM public.app_events WHERE created_at < now() - interval '13 months';
$$;
REVOKE ALL ON FUNCTION public.purge_old_app_events() FROM PUBLIC, anon, authenticated;
SELECT cron.schedule('bb_purge_app_events', '17 3 * * *', $cmd$ SELECT public.purge_old_app_events(); $cmd$);

-- ---------------------------------------------------------------- report
-- Accounts left out of every report: the phone-test exemption list, admins, test addresses, and an explicit list
-- (service role only) seeded with the two known test logins (notes 05, 37).
CREATE TABLE IF NOT EXISTS public.report_excluded_users (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  reason text NOT NULL DEFAULT 'test account',
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.report_excluded_users ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.report_excluded_users FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.report_excluded_users TO service_role;
INSERT INTO public.report_excluded_users (user_id, reason)
SELECT id, 'known test login' FROM auth.users WHERE lower(email) IN ('banbetestadmin@gmail.com', 'dotrung1998@gmail.com')
ON CONFLICT (user_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.report_test_user_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT user_id FROM public.account_phone_test_exempt
  UNION SELECT user_id FROM public.report_excluded_users
  UNION SELECT id FROM public.profiles WHERE role = 'admin'
  UNION SELECT id FROM auth.users
   WHERE lower(email) LIKE '%@test.dev' OR lower(email) LIKE '%@example.%' OR lower(email) LIKE 'banbetest%';
$$;
REVOKE ALL ON FUNCTION public.report_test_user_ids() FROM PUBLIC, anon, authenticated;

-- '<20' for any group smaller than 20 people; the number otherwise.
CREATE OR REPLACE FUNCTION public.report_k(n bigint)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT CASE WHEN n < 20 THEN to_jsonb('<20'::text) ELSE to_jsonb(n) END $$;
REVOKE ALL ON FUNCTION public.report_k(bigint) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_retention_report(p_from date DEFAULT NULL, p_to date DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_from timestamptz := coalesce(p_from, (now() - interval '90 days')::date)::timestamptz;
  v_to timestamptz := (coalesce(p_to, now()::date) + 1)::timestamptz;
  v_out jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  WITH people AS (
    SELECT p.id, coalesce(p.market, 'unknown') AS market, u.created_at
      FROM profiles p JOIN auth.users u ON u.id = p.id
     WHERE p.id NOT IN (SELECT public.report_test_user_ids())
  ), active AS (       -- a day with any first-party event, a booking or a check-in
    SELECT user_id, (created_at AT TIME ZONE 'UTC')::date AS day FROM app_events WHERE created_at >= v_from AND created_at < v_to
    UNION SELECT user_id, (created_at AT TIME ZONE 'UTC')::date FROM bookings WHERE created_at >= v_from AND created_at < v_to
  ), attended AS (
    SELECT b.user_id, b.event_id, min(c.checked_in_at) AS at
      FROM check_ins c JOIN bookings b ON b.id = c.booking_id GROUP BY b.user_id, b.event_id
  ), nth AS (
    SELECT user_id, at, row_number() OVER (PARTITION BY user_id ORDER BY at) AS k FROM attended
  ), cohort AS (
    SELECT pe.id, pe.market,
           EXISTS (SELECT 1 FROM active a WHERE a.user_id = pe.id AND a.day BETWEEN (pe.created_at::date + 7) AND (pe.created_at::date + 13)) AS d7,
           EXISTS (SELECT 1 FROM active a WHERE a.user_id = pe.id AND a.day BETWEEN (pe.created_at::date + 30) AND (pe.created_at::date + 36)) AS d30
      FROM people pe WHERE pe.created_at >= v_from AND pe.created_at < v_to
  ), by_market AS (
    SELECT m.market,
      (SELECT count(*) FROM people pe WHERE pe.market = m.market) AS people,
      (SELECT count(DISTINCT a.user_id) FROM active a JOIN people pe ON pe.id = a.user_id WHERE pe.market = m.market) AS active_people,
      (SELECT count(*) FROM cohort c WHERE c.market = m.market) AS new_people,
      (SELECT count(*) FROM cohort c WHERE c.market = m.market AND c.d7) AS d7_returned,
      (SELECT count(*) FROM cohort c WHERE c.market = m.market AND c.d30) AS d30_returned,
      (SELECT count(*) FROM nth n JOIN people pe ON pe.id = n.user_id WHERE n.k = 1 AND pe.market = m.market AND n.at >= v_from AND n.at < v_to) AS first_attenders,
      (SELECT count(*) FROM nth n1 JOIN nth n2 ON n2.user_id = n1.user_id AND n2.k = 2 JOIN people pe ON pe.id = n1.user_id
         WHERE n1.k = 1 AND pe.market = m.market AND n1.at >= v_from AND n1.at < v_to AND n2.at <= n1.at + interval '60 days') AS second_within_60d,
      (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (n2.at - n1.at)) / 86400)
         FROM nth n1 JOIN nth n2 ON n2.user_id = n1.user_id AND n2.k = 2 JOIN people pe ON pe.id = n1.user_id
        WHERE n1.k = 1 AND pe.market = m.market) AS days_to_second_median,
      (SELECT count(*) FROM nth n1 JOIN nth n2 ON n2.user_id = n1.user_id AND n2.k = 2 JOIN people pe ON pe.id = n1.user_id
        WHERE n1.k = 1 AND pe.market = m.market) AS second_attenders
    FROM (VALUES ('VN'), ('US'), ('unknown')) m(market)
  ), notif AS (
    SELECT n.kind, count(*) AS sent, count(n.read_at) AS read,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (n.read_at - n.created_at)) / 60)
             FILTER (WHERE n.read_at IS NOT NULL) AS read_minutes_median,
           count(DISTINCT n.recipient_id) AS people
      FROM notifications n
     WHERE n.created_at >= v_from AND n.created_at < v_to
       AND n.recipient_id NOT IN (SELECT public.report_test_user_ids())
     GROUP BY n.kind
  )
  SELECT jsonb_build_object(
    'success', true,
    'from', v_from::date, 'to', (v_to - interval '1 day')::date,
    'k_min', 20,
    'markets', (SELECT jsonb_agg(jsonb_build_object(
        'market', b.market,
        'people', public.report_k(b.people),
        'active_people', public.report_k(b.active_people),
        'new_people', public.report_k(b.new_people),
        'd7_returned', public.report_k(b.d7_returned),
        'd30_returned', public.report_k(b.d30_returned),
        'd7_rate', CASE WHEN b.new_people >= 20 AND b.d7_returned >= 20 THEN round(b.d7_returned::numeric / b.new_people, 3) END,
        'd30_rate', CASE WHEN b.new_people >= 20 AND b.d30_returned >= 20 THEN round(b.d30_returned::numeric / b.new_people, 3) END,
        'first_attenders', public.report_k(b.first_attenders),
        'second_within_60d', public.report_k(b.second_within_60d),
        'second_within_60d_rate', CASE WHEN b.first_attenders >= 20 AND b.second_within_60d >= 20
                                       THEN round(b.second_within_60d::numeric / b.first_attenders, 3) END,
        'days_to_second_median', CASE WHEN b.second_attenders >= 20 THEN round(b.days_to_second_median::numeric, 1) END
      ) ORDER BY b.market) FROM by_market b),
    'notifications', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'kind', x.kind, 'sent', public.report_k(x.sent), 'read', public.report_k(x.read),
        'read_minutes_median', CASE WHEN x.people >= 20 AND x.read >= 20 THEN round(x.read_minutes_median::numeric, 1) END
      ) ORDER BY x.kind) FROM notif x WHERE x.people >= 20), '[]'::jsonb),
    'notification_kinds_hidden', (SELECT count(*) FROM notif x WHERE x.people < 20)
  ) INTO v_out;
  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_retention_report(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_retention_report(date, date) TO authenticated;
