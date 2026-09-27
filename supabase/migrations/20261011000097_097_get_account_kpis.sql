-- 097: Account extension (2026-09-27, Stage 3) — one SECURITY DEFINER RPC,
-- reused for on-screen KPI cards, CSV, PDF and JSON export alike (the
-- ticket's own "reuse one metrics payload" rule) so those never disagree.
--
-- Scope/authorization:
--   'personal' — always the CALLER's own data (auth.uid()), never another
--     user's.
--   'host' — the caller's OWN organizer only. p_organizer_id must be one
--     the caller actually owns (organizers.owner_id/user_id = auth.uid());
--     anything else is rejected, never silently substituted (multi-org
--     accounts must pass their real organizer_id, per the ticket's own
--     "never silently substitute the first org" rule from the prior
--     ticket, which applies just as much to this one).
--   'admin' — requires is_platform_admin(); only operational aggregates
--     (event/dispute counts and ages), never a specific user's payment
--     documents/receipts/bank details/message bodies — this function
--     never selects payment_documents, chat/dispute message bodies, or
--     refund_claims.recipient_snapshot at all, for any scope.
--
-- Canonical definitions (kept consistent with existing views/RPCs so a
-- number here never disagrees with the screen it was already shown on):
--   confirmed booking = bookings.status IN ('confirmed','attended') AND
--     payment_state = 'confirmed' (026's own state machine) — cancelled/
--     expired/holding/pending_verification/disputed excluded.
--   published event = events.status IN ('live','ended') — same rule
--     get_public_profile/get_organizer_profile already use (091/095).
--   outstanding refund = refund_claims.status IN ('owed','host_marked_sent')
--     — explicitly NOT 'guest_confirmed': host_marked_sent means the host
--     SAYS they sent it, not that the guest has confirmed receiving it
--     (069's own state machine) — never conflated here.
--   overdue refund = status = 'owed' AND refund_due_at < now() (072's own
--     deadline column).
--
-- A metric with no real timestamp to bucket by (saved events, outstanding
-- refunds, upcoming events — all point-in-time backlogs, not "how many
-- happened in this range") omits `series` entirely rather than fabricate a
-- trend — the client shows value + table only for those.

CREATE OR REPLACE FUNCTION public.get_account_kpis(
  p_scope text,
  p_start timestamptz,
  p_end timestamptz,
  p_organizer_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean;
  v_org_id text;
  v_metrics jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF p_start IS NULL OR p_end IS NULL OR p_end < p_start THEN
    RETURN jsonb_build_object('success', false, 'error', 'BAD_RANGE');
  END IF;

  SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = v_uid;

  IF p_scope = 'personal' THEN
    WITH
    confirmed AS (
      SELECT b.id, b.created_at, b.qty, e.name AS event_name
      FROM bookings b JOIN events e ON e.id = b.event_id
      WHERE b.user_id = v_uid AND b.status IN ('confirmed','attended') AND b.payment_state = 'confirmed'
        AND b.created_at BETWEEN p_start AND p_end
    ),
    attended AS (
      SELECT ci.id, ci.checked_in_at, e.name AS event_name
      FROM check_ins ci
      JOIN bookings b ON b.id = ci.booking_id
      JOIN events e ON e.id = b.event_id
      WHERE b.user_id = v_uid AND ci.checked_in_at BETWEEN p_start AND p_end
    ),
    saved AS (
      SELECT f.event_id, e.name AS event_name
      FROM favorites f JOIN events e ON e.id = f.event_id
      WHERE f.user_id = v_uid
    ),
    upcoming AS (
      SELECT b.id, e.starts_at, e.name AS event_name
      FROM bookings b JOIN events e ON e.id = b.event_id
      WHERE b.user_id = v_uid AND b.status IN ('confirmed','attended')
        AND e.status IN ('live','ended') AND e.starts_at > now()
    ),
    refunds AS (
      SELECT rc.id, rc.amount_vnd, rc.status, rc.created_at, e.name AS event_name
      FROM refund_claims rc
      JOIN bookings b ON b.id = rc.booking_id
      JOIN events e ON e.id = b.event_id
      WHERE b.user_id = v_uid AND rc.status IN ('owed','host_marked_sent')
    )
    SELECT jsonb_build_array(
      jsonb_build_object(
        'key', 'saved_events', 'label', 'Sự kiện đã lưu', 'unit', 'count',
        'value', (SELECT count(*) FROM saved),
        'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object('event_id', event_id, 'event_name', event_name)), '[]'::jsonb) FROM saved)
      ),
      jsonb_build_object(
        'key', 'confirmed_bookings', 'label', 'Đặt chỗ đã xác nhận', 'unit', 'count',
        'value', (SELECT count(*) FROM confirmed),
        'series', (SELECT coalesce(jsonb_agg(jsonb_build_object('d', d, 'v', v) ORDER BY d), '[]'::jsonb) FROM (
          SELECT d::date AS d, count(c.id) AS v FROM generate_series(p_start::date, p_end::date, interval '1 day') d
          LEFT JOIN confirmed c ON c.created_at::date = d::date GROUP BY d
        ) s),
        'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'event_name', event_name, 'qty', qty, 'at', created_at) ORDER BY created_at DESC), '[]'::jsonb) FROM confirmed)
      ),
      jsonb_build_object(
        'key', 'attended_events', 'label', 'Đã tham dự', 'unit', 'count',
        'value', (SELECT count(*) FROM attended),
        'series', (SELECT coalesce(jsonb_agg(jsonb_build_object('d', d, 'v', v) ORDER BY d), '[]'::jsonb) FROM (
          SELECT d::date AS d, count(a.id) AS v FROM generate_series(p_start::date, p_end::date, interval '1 day') d
          LEFT JOIN attended a ON a.checked_in_at::date = d::date GROUP BY d
        ) s),
        'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'event_name', event_name, 'at', checked_in_at) ORDER BY checked_in_at DESC), '[]'::jsonb) FROM attended)
      ),
      jsonb_build_object(
        'key', 'upcoming_events', 'label', 'Sắp diễn ra', 'unit', 'count',
        'value', (SELECT count(*) FROM upcoming),
        'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'event_name', event_name, 'starts_at', starts_at) ORDER BY starts_at ASC), '[]'::jsonb) FROM upcoming)
      ),
      jsonb_build_object(
        'key', 'outstanding_refunds', 'label', 'Hoàn tiền đang chờ', 'unit', 'vnd',
        'value', (SELECT coalesce(sum(amount_vnd), 0) FROM refunds),
        'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'event_name', event_name, 'amount_vnd', amount_vnd, 'status', status, 'since', created_at) ORDER BY created_at ASC), '[]'::jsonb) FROM refunds)
      )
    ) INTO v_metrics;

    RETURN jsonb_build_object('success', true, 'scope', 'personal', 'range', jsonb_build_object('start', p_start, 'end', p_end), 'metrics', v_metrics);

  ELSIF p_scope = 'host' THEN
    IF p_organizer_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'ORGANIZER_ID_REQUIRED');
    END IF;
    SELECT o.id INTO v_org_id FROM organizers o
    WHERE o.id = p_organizer_id AND (o.owner_id = v_uid OR o.user_id = v_uid);
    IF v_org_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
    END IF;

    WITH
    confirmed AS (
      SELECT b.id, b.created_at, b.qty, b.total_vnd, e.name AS event_name
      FROM bookings b JOIN events e ON e.id = b.event_id
      WHERE e.organizer_id = v_org_id AND b.status IN ('confirmed','attended') AND b.payment_state = 'confirmed'
        AND b.created_at BETWEEN p_start AND p_end
    ),
    checkins AS (
      SELECT ci.id, ci.checked_in_at, e.name AS event_name
      FROM check_ins ci
      JOIN bookings b ON b.id = ci.booking_id
      JOIN events e ON e.id = b.event_id
      WHERE e.organizer_id = v_org_id AND ci.checked_in_at BETWEEN p_start AND p_end
    ),
    refunds AS (
      SELECT rc.id, rc.amount_vnd, rc.status, rc.refund_due_at, rc.created_at, e.name AS event_name
      FROM refund_claims rc
      JOIN bookings b ON b.id = rc.booking_id
      JOIN events e ON e.id = b.event_id
      WHERE e.organizer_id = v_org_id AND rc.status = 'owed'
    )
    SELECT jsonb_build_array(
      jsonb_build_object(
        'key', 'published_events', 'label', 'Sự kiện đã công khai', 'unit', 'count',
        'value', (SELECT count(*) FROM events WHERE organizer_id = v_org_id AND status IN ('live','ended'))
      ),
      jsonb_build_object(
        'key', 'upcoming_events', 'label', 'Sắp diễn ra', 'unit', 'count',
        'value', (SELECT count(*) FROM events WHERE organizer_id = v_org_id AND status = 'live' AND starts_at > now())
      ),
      jsonb_build_object(
        'key', 'confirmed_seats', 'label', 'Chỗ đã xác nhận', 'unit', 'count',
        'value', (SELECT coalesce(sum(qty), 0) FROM confirmed),
        'series', (SELECT coalesce(jsonb_agg(jsonb_build_object('d', d, 'v', v) ORDER BY d), '[]'::jsonb) FROM (
          SELECT d::date AS d, coalesce(sum(c.qty), 0) AS v FROM generate_series(p_start::date, p_end::date, interval '1 day') d
          LEFT JOIN confirmed c ON c.created_at::date = d::date GROUP BY d
        ) s),
        'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'event_name', event_name, 'qty', qty, 'at', created_at) ORDER BY created_at DESC), '[]'::jsonb) FROM confirmed)
      ),
      jsonb_build_object(
        'key', 'check_ins', 'label', 'Đã check-in', 'unit', 'count',
        'value', (SELECT count(*) FROM checkins),
        'series', (SELECT coalesce(jsonb_agg(jsonb_build_object('d', d, 'v', v) ORDER BY d), '[]'::jsonb) FROM (
          SELECT d::date AS d, count(c.id) AS v FROM generate_series(p_start::date, p_end::date, interval '1 day') d
          LEFT JOIN checkins c ON c.checked_in_at::date = d::date GROUP BY d
        ) s)
      ),
      jsonb_build_object(
        -- Deliberately NOT "doanh thu banbe"/"revenue" — see the ticket's
        -- own instruction — just the sum of confirmed booking amounts.
        'key', 'confirmed_payment_amount', 'label', 'Số tiền thanh toán đã xác nhận', 'unit', 'vnd',
        'value', (SELECT coalesce(sum(total_vnd), 0) FROM confirmed),
        'series', (SELECT coalesce(jsonb_agg(jsonb_build_object('d', d, 'v', v) ORDER BY d), '[]'::jsonb) FROM (
          SELECT d::date AS d, coalesce(sum(c.total_vnd), 0) AS v FROM generate_series(p_start::date, p_end::date, interval '1 day') d
          LEFT JOIN confirmed c ON c.created_at::date = d::date GROUP BY d
        ) s)
      ),
      jsonb_build_object(
        'key', 'refunds_owed', 'label', 'Hoàn tiền còn nợ', 'unit', 'vnd',
        'value', (SELECT coalesce(sum(amount_vnd), 0) FROM refunds),
        'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'event_name', event_name, 'amount_vnd', amount_vnd, 'due_at', refund_due_at, 'overdue', (refund_due_at IS NOT NULL AND refund_due_at < now())) ORDER BY refund_due_at ASC NULLS LAST), '[]'::jsonb) FROM refunds)
      ),
      jsonb_build_object(
        'key', 'refunds_overdue', 'label', 'Hoàn tiền quá hạn', 'unit', 'count',
        'value', (SELECT count(*) FROM refunds WHERE refund_due_at IS NOT NULL AND refund_due_at < now())
      )
    ) INTO v_metrics;

    RETURN jsonb_build_object('success', true, 'scope', 'host', 'organizer_id', v_org_id, 'range', jsonb_build_object('start', p_start, 'end', p_end), 'metrics', v_metrics);

  ELSIF p_scope = 'admin' THEN
    IF NOT coalesce(v_is_admin, false) THEN
      RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
    END IF;

    WITH
    pending_reviews AS (
      SELECT id, name, submitted_at FROM events WHERE status = 'review'
    ),
    open_disputes AS (
      SELECT b.id, b.disputed_at, e.name AS event_name FROM bookings b
      JOIN events e ON e.id = b.event_id
      WHERE b.payment_state = 'disputed'
      UNION ALL
      SELECT rc.id, rc.disputed_at, e.name AS event_name FROM refund_claims rc
      JOIN bookings b ON b.id = rc.booking_id JOIN events e ON e.id = b.event_id
      WHERE rc.status = 'disputed'
    ),
    new_events AS (SELECT id, created_at FROM events WHERE created_at BETWEEN p_start AND p_end),
    new_bookings AS (SELECT id, created_at FROM bookings WHERE created_at BETWEEN p_start AND p_end)
    SELECT jsonb_build_array(
      jsonb_build_object(
        'key', 'pending_event_reviews', 'label', 'Sự kiện chờ duyệt', 'unit', 'count',
        'value', (SELECT count(*) FROM pending_reviews),
        'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'event_name', name, 'submitted_at', submitted_at, 'age_days', extract(epoch FROM now() - submitted_at) / 86400) ORDER BY submitted_at ASC NULLS LAST), '[]'::jsonb) FROM pending_reviews)
      ),
      jsonb_build_object(
        'key', 'unresolved_disputes', 'label', 'Tranh chấp chưa xử lý', 'unit', 'count',
        'value', (SELECT count(*) FROM open_disputes),
        'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'event_name', event_name, 'disputed_at', disputed_at, 'age_days', extract(epoch FROM now() - disputed_at) / 86400) ORDER BY disputed_at ASC NULLS LAST), '[]'::jsonb) FROM open_disputes)
      ),
      jsonb_build_object(
        'key', 'backlog_avg_age_days', 'label', 'Tuổi trung bình hàng chờ (ngày)', 'unit', 'days',
        'value', (SELECT coalesce(round(avg(age)::numeric, 1), 0) FROM (
          SELECT extract(epoch FROM now() - submitted_at) / 86400 AS age FROM pending_reviews
          UNION ALL
          SELECT extract(epoch FROM now() - disputed_at) / 86400 FROM open_disputes
        ) ages)
      ),
      jsonb_build_object(
        'key', 'platform_new_events', 'label', 'Sự kiện mới toàn nền tảng', 'unit', 'count',
        'value', (SELECT count(*) FROM new_events),
        'series', (SELECT coalesce(jsonb_agg(jsonb_build_object('d', d, 'v', v) ORDER BY d), '[]'::jsonb) FROM (
          SELECT d::date AS d, count(n.id) AS v FROM generate_series(p_start::date, p_end::date, interval '1 day') d
          LEFT JOIN new_events n ON n.created_at::date = d::date GROUP BY d
        ) s)
      ),
      jsonb_build_object(
        'key', 'platform_new_bookings', 'label', 'Đặt chỗ mới toàn nền tảng', 'unit', 'count',
        'value', (SELECT count(*) FROM new_bookings),
        'series', (SELECT coalesce(jsonb_agg(jsonb_build_object('d', d, 'v', v) ORDER BY d), '[]'::jsonb) FROM (
          SELECT d::date AS d, count(n.id) AS v FROM generate_series(p_start::date, p_end::date, interval '1 day') d
          LEFT JOIN new_bookings n ON n.created_at::date = d::date GROUP BY d
        ) s)
      )
    ) INTO v_metrics;

    RETURN jsonb_build_object('success', true, 'scope', 'admin', 'range', jsonb_build_object('start', p_start, 'end', p_end), 'metrics', v_metrics);

  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'BAD_SCOPE');
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.get_account_kpis(text, timestamptz, timestamptz, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_account_kpis(text, timestamptz, timestamptz, text) TO authenticated;
