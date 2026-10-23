-- Aggregate-only, read-only. Returns counts; no row-level personal data.
WITH u AS (
  SELECT au.id, au.created_at, au.last_sign_in_at, p.phone, p.locale::text AS locale
  FROM auth.users au LEFT JOIN public.profiles p ON p.id = au.id
), mkt AS (
  SELECT u.id,
    CASE WHEN u.phone LIKE '+84%' OR u.phone LIKE '0%' THEN 'VN'
         WHEN u.phone LIKE '+1%' THEN 'US' ELSE 'unknown' END AS market
  FROM u
), active_days AS (   -- token refreshes ≈ days the app was actually open
  SELECT s.user_id, count(DISTINCT date_trunc('day', rt.created_at)) AS days,
         min(rt.created_at) AS first_at, max(rt.created_at) AS last_at
  FROM auth.refresh_tokens rt JOIN auth.sessions s ON s.id = rt.session_id
  GROUP BY s.user_id
)
SELECT jsonb_build_object(
  'users_total', (SELECT count(*) FROM u),
  'users_by_market', (SELECT jsonb_object_agg(market, n) FROM (SELECT market, count(*) n FROM mkt GROUP BY 1) x),
  'users_by_locale', (SELECT jsonb_object_agg(coalesce(locale,'null'), n) FROM (SELECT locale, count(*) n FROM u GROUP BY 1) x),
  'signed_in_7d', (SELECT count(*) FROM u WHERE last_sign_in_at > now() - interval '7 days'),
  'signed_in_30d', (SELECT count(*) FROM u WHERE last_sign_in_at > now() - interval '30 days'),
  'created_30d', (SELECT count(*) FROM u WHERE created_at > now() - interval '30 days'),
  'active_days_hist', (SELECT jsonb_object_agg(b, n) FROM (
      SELECT CASE WHEN days = 1 THEN '1' WHEN days <= 3 THEN '2-3' WHEN days <= 7 THEN '4-7' ELSE '8+' END b, count(*) n
      FROM active_days GROUP BY 1) x),
  'active_days_by_market', (SELECT jsonb_object_agg(market, d) FROM (
      SELECT m.market, jsonb_build_object('users', count(*), 'median_days', percentile_cont(0.5) WITHIN GROUP (ORDER BY a.days)) d
      FROM active_days a JOIN mkt m ON m.id = a.user_id GROUP BY 1) x),
  'events_by_country_status', (SELECT jsonb_object_agg(k, n) FROM (
      SELECT coalesce(country_code,'null') || ':' || status::text k, count(*) n FROM public.events GROUP BY 1) x),
  'bookings_by_status', (SELECT jsonb_object_agg(status::text, n) FROM (SELECT status, count(*) n FROM public.bookings GROUP BY 1) x),
  'bookers_distinct', (SELECT count(DISTINCT user_id) FROM public.bookings),
  'bookers_2plus_events', (SELECT count(*) FROM (SELECT user_id FROM public.bookings GROUP BY 1 HAVING count(DISTINCT event_id) >= 2) x),
  'booking_lead_hours_hist', (SELECT jsonb_object_agg(b, n) FROM (
      SELECT CASE WHEN h < 24 THEN '<24h' WHEN h < 72 THEN '1-3d' WHEN h < 168 THEN '3-7d' ELSE '>7d' END b, count(*) n
      FROM (SELECT extract(epoch FROM (e.starts_at - b.created_at))/3600 h FROM public.bookings b JOIN public.events e ON e.id = b.event_id WHERE e.starts_at IS NOT NULL) y
      GROUP BY 1) x),
  'check_ins', (SELECT count(*) FROM public.check_ins),
  'favorites', (SELECT count(*) FROM public.favorites),
  'favorites_distinct_users', (SELECT count(DISTINCT user_id) FROM public.favorites),
  'follows', (SELECT count(*) FROM public.follows),
  'messages_30d', (SELECT count(*) FROM public.messages WHERE created_at > now() - interval '30 days'),
  'message_senders_30d', (SELECT count(DISTINCT sender_id) FROM public.messages WHERE created_at > now() - interval '30 days'),
  'story_views', (SELECT count(*) FROM public.story_views),
  'photo_likes', (SELECT count(*) FROM public.photo_likes),
  'push_tokens', (SELECT count(*) FROM public.device_push_tokens),
  'notif_by_kind', (SELECT jsonb_object_agg(kind, d) FROM (
      SELECT kind, jsonb_build_object('sent', count(*), 'read', count(read_at),
        'median_min_to_read', round((percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (read_at - created_at))/60))::numeric, 1)) d
      FROM public.notifications GROUP BY kind) x),
  'activity_by_hour_vn', (SELECT jsonb_object_agg(h, n) FROM (
      SELECT extract(hour FROM rt.created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::int h, count(*) n FROM auth.refresh_tokens rt GROUP BY 1) x),
  'activity_by_dow_vn', (SELECT jsonb_object_agg(d, n) FROM (
      SELECT to_char(rt.created_at AT TIME ZONE 'Asia/Ho_Chi_Minh', 'Dy') d, count(*) n FROM auth.refresh_tokens rt GROUP BY 1) x)
) AS stats;
