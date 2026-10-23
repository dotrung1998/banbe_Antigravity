-- Retention baseline (plan §2d). ONE read-only, counts-only query, authorized by the owner on 2026-10-23.
-- Output: rows (section, grp, n, value). No ids, emails, phones, names or content ever leave the database.
-- Test accounts are excluded (phone-test exemption list, admins, the known test logins, @test.dev / example
-- addresses). Any group smaller than 20 prints as '<20' and its derived value is hidden.
-- Market: phone prefix (+84 → VN, +1 → US), else the country of the events the person booked, else 'unknown'.
-- "Active day" = a day with at least one session token refresh (the app was open), the only open-signal we have.
SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY;
WITH test_users AS (
  SELECT user_id AS id FROM public.account_phone_test_exempt
  UNION SELECT id FROM public.profiles WHERE role = 'admin'
  UNION SELECT id FROM auth.users
   WHERE lower(email) IN ('banbetestadmin@gmail.com', 'dotrung1998@gmail.com')
      OR lower(email) LIKE '%@test.dev' OR lower(email) LIKE '%@example.%'
), real_users AS (
  SELECT u.id, u.created_at, u.last_sign_in_at, p.phone
    FROM auth.users u JOIN public.profiles p ON p.id = u.id
   WHERE u.id NOT IN (SELECT id FROM test_users)
), booked_country AS (
  SELECT b.user_id, max(upper(e.country_code)) AS cc
    FROM public.bookings b JOIN public.events e ON e.id = b.event_id GROUP BY b.user_id
), mkt AS (
  SELECT r.id,
         CASE WHEN r.phone LIKE '+84%' OR r.phone LIKE '0%' THEN 'VN'
              WHEN r.phone LIKE '+1%' THEN 'US'
              WHEN bc.cc IN ('VN', 'US') THEN bc.cc
              ELSE 'unknown' END AS market
    FROM real_users r LEFT JOIN booked_country bc ON bc.user_id = r.id
), active AS (
  SELECT rt.user_id::uuid AS user_id, date_trunc('day', rt.created_at) AS day, rt.created_at
    FROM auth.refresh_tokens rt
   WHERE rt.user_id ~ '^[0-9a-f-]{36}$' AND rt.user_id::uuid IN (SELECT id FROM real_users)
), active_days AS (
  SELECT user_id, count(DISTINCT day) AS days FROM active GROUP BY user_id
), rows AS (
  SELECT 'users' AS section, 'all' AS grp, count(*) AS n, NULL::numeric AS value FROM real_users
  UNION ALL SELECT 'users', 'market:' || market, count(*), NULL FROM mkt GROUP BY market
  UNION ALL SELECT 'users', 'signed_in_7d', count(*), NULL FROM real_users WHERE last_sign_in_at > now() - interval '7 days'
  UNION ALL SELECT 'users', 'signed_in_30d', count(*), NULL FROM real_users WHERE last_sign_in_at > now() - interval '30 days'
  UNION ALL SELECT 'users', 'created_30d', count(*), NULL FROM real_users WHERE created_at > now() - interval '30 days'
  UNION ALL SELECT 'active_days', b, count(*), NULL FROM (
      SELECT CASE WHEN days = 1 THEN '1' WHEN days <= 3 THEN '2-3' WHEN days <= 7 THEN '4-7' ELSE '8+' END AS b FROM active_days) x GROUP BY b
  UNION ALL SELECT 'active_days_median', 'market:' || m.market, count(*), percentile_cont(0.5) WITHIN GROUP (ORDER BY a.days)::numeric
      FROM active_days a JOIN mkt m ON m.id = a.user_id GROUP BY m.market
  UNION ALL SELECT 'active_by_hour_local_vn', lpad(extract(hour FROM created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::text, 2, '0'), count(*), NULL FROM active GROUP BY 2
  UNION ALL SELECT 'active_by_weekday_local_vn', to_char(created_at AT TIME ZONE 'Asia/Ho_Chi_Minh', 'ID-Dy'), count(*), NULL FROM active GROUP BY 2
  UNION ALL SELECT 'bookings', 'status:' || b.status::text, count(*), NULL FROM public.bookings b WHERE b.user_id IN (SELECT id FROM real_users) GROUP BY b.status
  UNION ALL SELECT 'bookings', 'distinct_bookers', count(DISTINCT b.user_id), NULL FROM public.bookings b WHERE b.user_id IN (SELECT id FROM real_users)
  UNION ALL SELECT 'bookings', 'bookers_2plus_events', count(*), NULL FROM (
      SELECT user_id FROM public.bookings WHERE user_id IN (SELECT id FROM real_users) GROUP BY user_id HAVING count(DISTINCT event_id) >= 2) x
  UNION ALL SELECT 'booking_lead', b, count(*), NULL FROM (
      SELECT CASE WHEN h < 24 THEN '<24h' WHEN h < 72 THEN '1-3d' WHEN h < 168 THEN '3-7d' ELSE '>7d' END AS b
        FROM (SELECT extract(epoch FROM (e.starts_at - b.created_at)) / 3600 AS h
                FROM public.bookings b JOIN public.events e ON e.id = b.event_id
               WHERE e.starts_at IS NOT NULL AND b.user_id IN (SELECT id FROM real_users)) y) x GROUP BY b
  UNION ALL SELECT 'check_ins', 'all', count(*), NULL FROM public.check_ins c JOIN public.bookings b ON b.id = c.booking_id WHERE b.user_id IN (SELECT id FROM real_users)
  UNION ALL SELECT 'saves', 'all', count(*), NULL FROM public.favorites WHERE user_id IN (SELECT id FROM real_users)
  UNION ALL SELECT 'saves', 'distinct_savers', count(DISTINCT user_id), NULL FROM public.favorites WHERE user_id IN (SELECT id FROM real_users)
  UNION ALL SELECT 'follows', 'all', count(*), NULL FROM public.follows WHERE user_id IN (SELECT id FROM real_users)
  UNION ALL SELECT 'messages_30d', 'all', count(*), NULL FROM public.messages WHERE sender_id IN (SELECT id FROM real_users) AND created_at > now() - interval '30 days'
  UNION ALL SELECT 'story_views', 'all', count(*), NULL FROM public.story_views WHERE viewer_id IN (SELECT id FROM real_users)
  UNION ALL SELECT 'photo_likes', 'all', count(*), NULL FROM public.photo_likes WHERE user_id IN (SELECT id FROM real_users)
  UNION ALL SELECT 'push_tokens', 'all', count(*), NULL FROM public.device_push_tokens WHERE user_id IN (SELECT id FROM real_users)
  UNION ALL SELECT 'notif_read_minutes_median', 'kind:' || kind, count(read_at),
      percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (read_at - created_at)) / 60)::numeric
      FROM public.notifications WHERE recipient_id IN (SELECT id FROM real_users) AND read_at IS NOT NULL GROUP BY kind
  UNION ALL SELECT 'notif_sent', 'kind:' || kind, count(*), NULL FROM public.notifications WHERE recipient_id IN (SELECT id FROM real_users) GROUP BY kind
)
SELECT section, grp,
       CASE WHEN n < 20 THEN '<20' ELSE n::text END AS n,
       CASE WHEN n < 20 OR value IS NULL THEN NULL ELSE round(value, 1)::text END AS value
  FROM rows ORDER BY section, grp;
