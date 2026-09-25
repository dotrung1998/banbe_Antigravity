-- Migration: Banbe Pulse — a THIRD tab ranking individual event photos by
-- real engagement (likes + shares), separate from the existing event-level
-- ranking (migration 080, goc_pulse_ranked()). Two new tables, no reuse of
-- the local-only `s.photoLikes` (that one is `localStorage`-only, keyed by
-- raw photo URL, and only ever operates on the bundled STATIC demo
-- catalogue's photos — see 17-ux-foundation-release.md's 2026-10-03 fix
-- pass for the full trace confirming it has zero `supabase.*` calls and
-- zero overlap with real `event_photos` rows. This migration is the real,
-- durable signal that was missing.

-- ============ photo_likes ============
-- One row per (user, photo) — a plain heart toggle. `user_id` references
-- `profiles(id)`, matching `favorites`/`follows`' own convention (003), not
-- `auth.users` directly.
CREATE TABLE IF NOT EXISTS photo_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  event_photo_id uuid NOT NULL REFERENCES event_photos(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, event_photo_id)
);
CREATE INDEX IF NOT EXISTS idx_photo_likes_photo ON photo_likes(event_photo_id);

ALTER TABLE photo_likes ENABLE ROW LEVEL SECURITY;
-- Own rows only, both directions — a viewer needs to know THEIR OWN like
-- state (own-row SELECT), never who else liked a photo (no policy grants
-- reading another user's row; aggregate counts are read exclusively
-- through get_pulse_photo_ranked() below, a SECURITY DEFINER function that
-- returns counts, never raw rows).
DROP POLICY IF EXISTS "photo_likes_select_own" ON photo_likes;
CREATE POLICY "photo_likes_select_own" ON photo_likes FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "photo_likes_insert_own" ON photo_likes;
CREATE POLICY "photo_likes_insert_own" ON photo_likes FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "photo_likes_delete_own" ON photo_likes;
CREATE POLICY "photo_likes_delete_own" ON photo_likes FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ============ photo_shares ============
-- One row per completed share action (never per share-sheet OPEN — the
-- client only calls log_photo_share() below from inside a share sheet's
-- own completion callback / a copy-link success handler, matching this
-- migration's own explicit ask). No table-level INSERT/SELECT policy for
-- anon or authenticated at all — every write goes through log_photo_share()
-- (SECURITY DEFINER), every read through get_pulse_photo_ranked()'s
-- aggregate counts. `sharer_user_id` nullable: the app currently mandates
-- login everywhere (09-auth-onboarding.md), so this is always populated in
-- practice today, but the column doesn't hard-require it, matching this
-- ticket's own schema spec.
CREATE TABLE IF NOT EXISTS photo_shares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_photo_id uuid NOT NULL REFERENCES event_photos(id) ON DELETE CASCADE,
  sharer_user_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  channel text NOT NULL DEFAULT 'share',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_photo_shares_photo ON photo_shares(event_photo_id);

ALTER TABLE photo_shares ENABLE ROW LEVEL SECURITY;
-- Deliberately zero policies: RLS enabled with no grants means even the
-- table owner's default privileges don't let `anon`/`authenticated` touch
-- this table directly — the ONLY path in or out is the two SECURITY
-- DEFINER functions below.

-- ============ toggle_photo_like(p_event_photo_id) ============
-- Server-checks the CURRENT state and flips it — "one like per user per
-- photo enforced server-side" is structural (the UNIQUE index) rather than
-- trusted from whatever the client's own optimistic guess happens to be.
CREATE OR REPLACE FUNCTION public.toggle_photo_like(p_event_photo_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_liked boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM event_photos WHERE id = p_event_photo_id) THEN
    RAISE EXCEPTION 'PHOTO_NOT_FOUND';
  END IF;

  IF EXISTS (SELECT 1 FROM photo_likes WHERE user_id = auth.uid() AND event_photo_id = p_event_photo_id) THEN
    DELETE FROM photo_likes WHERE user_id = auth.uid() AND event_photo_id = p_event_photo_id;
    v_liked := false;
  ELSE
    INSERT INTO photo_likes (user_id, event_photo_id)
    VALUES (auth.uid(), p_event_photo_id)
    ON CONFLICT (user_id, event_photo_id) DO NOTHING;
    v_liked := true;
  END IF;

  RETURN v_liked;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.toggle_photo_like(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.toggle_photo_like(uuid) TO authenticated;

-- ============ log_photo_share(p_event_photo_id, p_channel) ============
-- Called ONLY from the moment a share genuinely completes (native share
-- sheet's own completion callback resolving `completed == true`, or a
-- copy-link action's own success path) — never from merely opening a share
-- sheet/menu. `p_channel` is a short free-text label ('native', 'copy',
-- …), not an enum — new channels can appear without a migration.
CREATE OR REPLACE FUNCTION public.log_photo_share(p_event_photo_id uuid, p_channel text DEFAULT 'share')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM event_photos WHERE id = p_event_photo_id) THEN
    RAISE EXCEPTION 'PHOTO_NOT_FOUND';
  END IF;
  INSERT INTO photo_shares (event_photo_id, sharer_user_id, channel)
  VALUES (p_event_photo_id, auth.uid(), left(coalesce(nullif(trim(p_channel), ''), 'share'), 40));
END;
$$;
REVOKE EXECUTE ON FUNCTION public.log_photo_share(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.log_photo_share(uuid, text) TO authenticated;

-- ============ get_pulse_photo_ranked(p_period) ============
-- 'daily' (last 24h) or 'weekly' (last 7 days) — same two windows and same
-- "count real activity within the window, capped and weighted, no extra
-- decay curve on top" philosophy as goc_pulse_ranked() (080): that
-- function's own "recency" signal IS the period window itself, not a
-- separate continuous decay function, and this one stays consistent with
-- that rather than introducing a second, incompatible notion of recency.
--   likes in the window,  capped at 20, weight 3 -> max 60
--   shares in the window, capped at 10, weight 4 -> max 40 (a completed
--     share is a stronger engagement signal than a like — it leaves the
--     app — so it's weighted higher per unit, same "transparent, bounded"
--     spirit, just a different constant)
-- Max possible score: 100. Same eligibility rule as event-level Pulse:
-- only `status = 'live' AND visibility = 'public'` events. Unlike
-- goc_pulse_ranked()'s per-ORGANIZER cap (it ranks organizers via their
-- best event), this ranks photos directly with no per-event/per-organizer
-- dedup — the ticket's own ask is individual photos, and a photo is
-- already the atomic unit here, so no separate diversity cap is needed.
-- Zero-engagement photos are NOT filtered out (same honesty rule as 080 —
-- an eligible photo with no real engagement yet still shows, at the bottom,
-- rather than silently hiding it), just naturally sorted last.
CREATE OR REPLACE FUNCTION public.get_pulse_photo_ranked(p_period text DEFAULT 'daily')
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
      SELECT coalesce(jsonb_agg(ranked ORDER BY sort_score DESC, ranked->>'photo_id' ASC), '[]'::jsonb)
      FROM (
        SELECT
          jsonb_build_object(
            'photo_id', p.id,
            'event_id', e.id,
            'event_name', e.name,
            'photo_path', p.storage_path,
            'organizer_id', o.id,
            'organizer_name', o.name,
            'organizer_verified', o.verified,
            'like_count', lkt.n,
            'share_count', sht.n,
            'score', (least(lk.n, 20) * 3 + least(sh.n, 10) * 4)
          ) AS ranked,
          (least(lk.n, 20) * 3 + least(sh.n, 10) * 4) AS sort_score
        FROM event_photos p
        JOIN events e ON e.id = p.event_id
        JOIN organizers o ON o.id = e.organizer_id
        CROSS JOIN LATERAL (
          SELECT count(*) AS n FROM photo_likes l WHERE l.event_photo_id = p.id AND l.created_at >= v_since
        ) lk
        CROSS JOIN LATERAL (
          SELECT count(*) AS n FROM photo_shares s WHERE s.event_photo_id = p.id AND s.created_at >= v_since
        ) sh
        CROSS JOIN LATERAL (
          SELECT count(*) AS n FROM photo_likes l WHERE l.event_photo_id = p.id
        ) lkt
        CROSS JOIN LATERAL (
          SELECT count(*) AS n FROM photo_shares s WHERE s.event_photo_id = p.id
        ) sht
        WHERE e.status = 'live' AND e.visibility = 'public'
        ORDER BY (least(lk.n, 20) * 3 + least(sh.n, 10) * 4) DESC, p.id ASC
        LIMIT 20
      ) top
    )
  );
END;
$$;

-- Visible to everyone, no follow/login required — same "anon too" reasoning
-- as goc_pulse_ranked() and get_public_profile() (a signed-out visitor can
-- browse Pulse same as any other public content; only liking/sharing
-- itself requires being signed in).
GRANT EXECUTE ON FUNCTION public.get_pulse_photo_ranked(text) TO authenticated, anon;
