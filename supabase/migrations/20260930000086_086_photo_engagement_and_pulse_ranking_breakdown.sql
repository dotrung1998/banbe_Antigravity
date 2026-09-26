-- Migration: real per-photo engagement lookup (likes+shares, for ANY
-- event_photos row — not just the top-20 Pulse ranks migration 083's
-- get_pulse_photo_ranked() returns) + a transparent score breakdown on
-- goc_pulse_ranked() (migration 080).
--
-- Root cause this migration exists to fix: EventDetail's/Organizer's photo
-- grids and the full-screen PhotoViewer never had ANY way to read a real
-- photo's like/share counts or the current user's own liked state outside
-- Pulse's own top-20 ranked list — the only two functions that ever touched
-- `photo_likes`/`photo_shares` (toggle_photo_like, log_photo_share, both
-- 083) return only a boolean/void, and get_pulse_photo_ranked() only covers
-- whichever 20 photos currently rank. get_photo_engagement() below is the
-- missing general-purpose read path: given ANY set of real event_photos
-- ids, return each one's canonical aggregate counts + this user's own liked
-- state, straight from the same two tables Pulse itself reads — so a photo
-- shown in EventDetail/Organizer/PhotoViewer and the SAME photo shown in
-- Pulse can never disagree, because both surfaces now read the exact same
-- underlying rows.

-- ============ get_photo_engagement(p_photo_ids) ============
CREATE OR REPLACE FUNCTION public.get_photo_engagement(p_photo_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN jsonb_build_object(
    'success', true,
    'items', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'photo_id', p.id,
        'event_id', p.event_id,
        'like_count', lk.n,
        'share_count', sh.n,
        'liked_by_me', (auth.uid() IS NOT NULL AND EXISTS (
          SELECT 1 FROM photo_likes ml WHERE ml.event_photo_id = p.id AND ml.user_id = auth.uid()
        ))
      )), '[]'::jsonb)
      FROM event_photos p
      CROSS JOIN LATERAL (SELECT count(*) AS n FROM photo_likes l WHERE l.event_photo_id = p.id) lk
      CROSS JOIN LATERAL (SELECT count(*) AS n FROM photo_shares s WHERE s.event_photo_id = p.id) sh
      WHERE p.id = ANY(p_photo_ids)
    )
  );
END;
$$;
-- event_photos itself is openly readable (migration 001) and this returns
-- only aggregate counts + the CALLER's own liked state (never another
-- user's row) — safe for anon too, same reasoning as get_pulse_photo_ranked.
GRANT EXECUTE ON FUNCTION public.get_photo_engagement(uuid[]) TO authenticated, anon;

-- ============ goc_pulse_ranked(p_period) — transparent score breakdown ============
-- Same eligibility/ranking/cap logic as migration 080, unchanged. Adds the
-- RAW per-signal counts (not just the already-capped/weighted total score)
-- plus the event's own category/cat_label/included ("bao gồm") fields, so
-- the client can show WHY an event ranked where it did instead of a bare
-- number — never inventing a metric the query doesn't actually use.
CREATE OR REPLACE FUNCTION public.goc_pulse_ranked(p_period text DEFAULT 'daily')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_since timestamptz := CASE WHEN p_period = 'weekly' THEN now() - interval '7 days' ELSE now() - interval '1 day' END;
BEGIN
  RETURN jsonb_build_object(
    'success', true,
    'period', CASE WHEN p_period = 'weekly' THEN 'weekly' ELSE 'daily' END,
    'items', (
      SELECT coalesce(jsonb_agg(ranked ORDER BY (ranked->>'score')::numeric DESC, ranked->>'event_id' ASC) , '[]'::jsonb)
      FROM (
        SELECT DISTINCT ON (o.id) jsonb_build_object(
          'event_id', e.id,
          'event_name', e.name,
          'photo_path', ep.storage_path,
          'organizer_id', o.id,
          'organizer_name', o.name,
          'organizer_verified', o.verified,
          'category', e.category,
          'cat_label', e.cat_label,
          'included', e.included,
          'booking_count', bk.n,
          'checkin_count', ci.n,
          'follow_count', fl.n,
          'save_count', sv.n,
          'booking_score', least(bk.n, 20) * 3,
          'checkin_score', least(ci.n, 15) * 2,
          'follow_score', least(fl.n, 10) * 1.5,
          'save_score', least(sv.n, 10),
          'score', (
            least(bk.n, 20) * 3 + least(ci.n, 15) * 2 + least(fl.n, 10) * 1.5 + least(sv.n, 10)
          )
        ) AS ranked
        FROM events e
        JOIN organizers o ON o.id = e.organizer_id
        JOIN LATERAL (
          SELECT storage_path FROM event_photos p WHERE p.event_id = e.id ORDER BY p.sort_order ASC LIMIT 1
        ) ep ON true
        CROSS JOIN LATERAL (
          SELECT count(*) AS n FROM bookings b WHERE b.event_id = e.id AND b.status = 'confirmed' AND b.created_at >= v_since
        ) bk
        CROSS JOIN LATERAL (
          SELECT count(*) AS n FROM check_ins c WHERE c.event_id = e.id AND c.checked_in_at >= v_since
        ) ci
        CROSS JOIN LATERAL (
          -- Unchanged from 080: `follows` still has no created_at column, so
          -- this remains the organizer's total follower count as a bounded
          -- proxy, not a true "new follows in period" count. Surfaced to the
          -- client as `follow_count` verbatim — the breakdown UI must not
          -- claim this is period-scoped, since the query itself isn't.
          SELECT count(*) AS n FROM follows f WHERE f.organizer_id = o.id
        ) fl
        CROSS JOIN LATERAL (
          SELECT count(*) AS n FROM favorites fv WHERE fv.event_id = e.id
        ) sv
        WHERE e.status = 'live'
          AND e.visibility = 'public'
        ORDER BY o.id, (least(bk.n, 20) * 3 + least(ci.n, 15) * 2 + least(fl.n, 10) * 1.5 + least(sv.n, 10)) DESC
      ) per_organizer
      LIMIT 20
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.goc_pulse_ranked(text) TO authenticated, anon;
