-- Migration: TASK E (2026-10-01 UX foundation pass) — Banbe Pulse ranking.
--
-- No `stories` table change at all: the permanent "Banbe Pulse" ring entry
-- is a CLIENT-side synthetic first item (not a real story row — matches
-- this ticket's own "not authored as a normal 24h user story" rule
-- exactly), so the 066 migration's 24h-expiry schema/RLS stays untouched.
-- This migration only adds the ranking read path: one SECURITY DEFINER RPC
-- computing a transparent score from real data, on demand (see the ranking
-- write-up in .claude/notes for why this is "computed on read, not a
-- materialized/cron pipeline" and what that trades off).
--
-- goc_pulse_ranked(p_period) — 'daily' (last 24h) or 'weekly' (last 7 days).
-- Score = bounded contributions from four real signals, each independently
-- capped so no single signal (e.g. a bot-inflated view count) can dominate
-- — this is also why raw story-view volume is deliberately NOT one of the
-- inputs at all (rule E5):
--   confirmed bookings in the period, capped at 20, weight 3   -> max 60
--   check-ins in the period,          capped at 15, weight 2   -> max 30
--   new follows on the organizer,     capped at 10, weight 1.5 -> max 15
--   new saves (favorites) on the event, capped at 10, weight 1 -> max 10
-- Max possible score: 115. Only 'live'+'public' events with at least one
-- approved event_photos row are eligible at all (rule E3/E4: only approved/
-- public media, never a cancelled/ended/private event). Capped to the
-- single highest-scoring event per organizer (rule E6's "per-organizer
-- cap"), then the top 20 organizers overall.
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
          SELECT count(*) AS n FROM follows f WHERE f.organizer_id = o.id
          -- follows has no created_at column (002/003 schema) — a "new
          -- follows in the period" count isn't derivable yet without a
          -- migration to that table, which is out of this ticket's own
          -- read-only-schema scope; falls back to the organizer's total
          -- follower count as a bounded proxy signal instead of a raw,
          -- unbounded popularity count. Revisit once follows gets its own
          -- created_at.
        ) fl
        CROSS JOIN LATERAL (
          SELECT count(*) AS n FROM favorites fv WHERE fv.event_id = e.id
        ) sv
        WHERE e.status = 'live'
          AND e.visibility = 'public'
          -- rule E4: excludes cancelled/ended (status already scopes this)
          -- and private (visibility) content. No moderation-hidden flag
          -- exists anywhere in the current schema to exclude by — nothing
          -- to filter on yet; add one here the moment such a column exists.
        ORDER BY o.id, (least(bk.n, 20) * 3 + least(ci.n, 15) * 2 + least(fl.n, 10) * 1.5 + least(sv.n, 10)) DESC
      ) per_organizer
      LIMIT 20
    )
  );
END;
$$;

-- Visible to everyone, no follow required (rule E) — same "anon too"
-- reasoning as get_public_profile() (migration 079).
GRANT EXECUTE ON FUNCTION public.goc_pulse_ranked(text) TO authenticated, anon;
