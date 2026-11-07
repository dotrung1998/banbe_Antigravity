-- DRY RUN ONLY. Shows what an OPTIONAL legacy backfill of rewards WOULD grant, using exactly the
-- live rules (eligibility, one award per distinct event, monthly coin cap). It writes nothing:
-- the whole script runs in a READ ONLY transaction, and no apply path exists in the repo.
-- Migration 165 never back-fills by itself; run this only to inform a product decision, with a
-- service-role/superuser connection (rewards_* helpers are not callable by app roles).
--   psql "$DATABASE_URL" -f scripts/rewards-backfill-preview.sql
BEGIN READ ONLY;

\echo '--- attendance awards a backfill would create (cap applied per local month)'
WITH hist AS (
  SELECT DISTINCT ON (d.user_id, d.event_id)
         d.user_id, d.event_id, c.checked_in_at,
         date_trunc('month', c.checked_in_at AT TIME ZONE public.rewards_tz()) AS month_local
    FROM public.check_ins c
    CROSS JOIN LATERAL public.rewards_desired_sources(c.booking_id) d
   WHERE c.booking_id IS NOT NULL
   ORDER BY d.user_id, d.event_id, c.checked_in_at
), plan AS (
  SELECT h.*, row_number() OVER (PARTITION BY h.user_id, h.month_local ORDER BY h.checked_in_at) AS nth_in_month,
         (public.rewards_rules() ->> 'attendance_coins')::int AS coins,
         (public.rewards_rules() ->> 'attendance_coin_cap_per_month')::int AS cap
    FROM hist h
)
SELECT count(DISTINCT user_id) AS users,
       count(*) AS distinct_user_events,
       COALESCE(sum(CASE WHEN nth_in_month <= cap THEN coins ELSE 0 END), 0) AS coins_total,
       count(*) FILTER (WHERE nth_in_month > cap) AS events_over_cap_paying_zero
  FROM plan;

\echo '--- preference-onboarding awards (completed with answers, marker set) a backfill would create'
SELECT count(*) AS users,
       count(*) * COALESCE((public.rewards_rules() ->> 'onboarding_coins')::int, 0) AS coins_total
  FROM public.profile_event_preferences p
 WHERE p.prefs_onboarded_version > 0 AND p.event_preferences IS NOT NULL;

\echo '--- badges that would be earned by attendance alone'
WITH hist AS (
  SELECT DISTINCT ON (d.user_id, d.event_id)
         d.user_id, d.event_id, c.checked_in_at,
         date_trunc('month', c.checked_in_at AT TIME ZONE public.rewards_tz()) AS month_local
    FROM public.check_ins c
    CROSS JOIN LATERAL public.rewards_desired_sources(c.booking_id) d
   WHERE c.booking_id IS NOT NULL
   ORDER BY d.user_id, d.event_id, c.checked_in_at
), plan AS (
  SELECT h.*, row_number() OVER (PARTITION BY h.user_id, h.month_local ORDER BY h.checked_in_at) AS nth_in_month,
         (public.rewards_rules() ->> 'attendance_coins')::int AS coins,
         (public.rewards_rules() ->> 'attendance_coin_cap_per_month')::int AS cap
    FROM hist h
)
SELECT badge, count(*) AS users FROM (
  SELECT user_id, 'first_outing' AS badge FROM plan GROUP BY user_id HAVING count(*) >= 1
  UNION ALL SELECT user_id, 'regular' FROM plan GROUP BY user_id HAVING count(*) >= 5
  UNION ALL SELECT user_id, 'community_regular' FROM plan GROUP BY user_id HAVING count(*) >= 10
  UNION ALL SELECT p.user_id, 'explorer' FROM plan p JOIN public.events e ON e.id = p.event_id
            WHERE e.cat_key IS NOT NULL AND e.cat_key <> '' GROUP BY p.user_id HAVING count(DISTINCT e.cat_key) >= 3
) b GROUP BY badge ORDER BY badge;

\echo '--- top 20 accounts by coins (ids only; no names or emails)'
WITH hist AS (
  SELECT DISTINCT ON (d.user_id, d.event_id)
         d.user_id, d.event_id, c.checked_in_at,
         date_trunc('month', c.checked_in_at AT TIME ZONE public.rewards_tz()) AS month_local
    FROM public.check_ins c
    CROSS JOIN LATERAL public.rewards_desired_sources(c.booking_id) d
   WHERE c.booking_id IS NOT NULL
   ORDER BY d.user_id, d.event_id, c.checked_in_at
), plan AS (
  SELECT h.*, row_number() OVER (PARTITION BY h.user_id, h.month_local ORDER BY h.checked_in_at) AS nth_in_month,
         (public.rewards_rules() ->> 'attendance_coins')::int AS coins,
         (public.rewards_rules() ->> 'attendance_coin_cap_per_month')::int AS cap
    FROM hist h
)
SELECT user_id, count(*) AS events, sum(CASE WHEN nth_in_month <= cap THEN coins ELSE 0 END) AS coins
  FROM plan GROUP BY user_id ORDER BY coins DESC, user_id LIMIT 20;

ROLLBACK;
