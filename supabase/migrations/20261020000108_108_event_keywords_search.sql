-- Keyword-search fix (2026-09-29) — Map's own search box (MapExplore.jsx's
-- `searchQuery` filter) only ever matched an event's literal `name`/`area`,
-- so an event genuinely relevant to a search term (a cuisine, a vibe, an
-- occasion word) that didn't happen to appear in its name or district was
-- invisible to that search, even though it should have been discoverable.
-- Purely additive: a new nullable-defaulted column plus one new,
-- independent SECURITY DEFINER RPC — does NOT touch create_event_draft or
-- resubmit_event_for_review's existing (already large, multiply-extended)
-- bodies at all, to keep this change's blast radius small.
--
-- Like migration 107, this file has NOT been applied/verified against a
-- live database from this environment — no supabase CLI, no psql, no `pg`
-- driver, no DB connection string available here. Review before deploying.

ALTER TABLE events ADD COLUMN IF NOT EXISTS keywords text[] NOT NULL DEFAULT '{}';

-- Cheap to add now, before the column has much real data to reindex later.
CREATE INDEX IF NOT EXISTS events_keywords_gin_idx ON events USING gin (keywords);

-- Backfill for every existing real event: as many honest, DERIVED keywords
-- as can be reconstructed from data the row already has — category label,
-- district, every word of its name, and each "Bao gồm" item's label. Never
-- invents anything not already present on the row. Idempotent by construction
-- (recomputes the same way every run) — safe to re-run, and skipped entirely
-- for a row a host has already customized (keywords <> '{}').
UPDATE events e SET keywords = (
  SELECT COALESCE(array_agg(DISTINCT kw), '{}')
  FROM (
    SELECT unnest(
      array_remove(
        ARRAY[e.cat_label, e.area]
        || regexp_split_to_array(COALESCE(e.name, ''), '\s+')
        || COALESCE((SELECT array_agg(item->>'label') FROM jsonb_array_elements(COALESCE(e.included_items, '[]'::jsonb)) AS item), '{}'),
        NULL
      )
    ) AS kw
  ) words
  WHERE length(trim(kw)) > 0
)
WHERE e.keywords = '{}';

CREATE OR REPLACE FUNCTION public.set_event_keywords(
  p_event_id text, p_keywords text[]
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rows int;
  -- Same trim/cap-count/cap-length nicety-on-the-client-real-gate-here
  -- convention this file's neighbours (migration 107's included-items
  -- validation) already use — a generous cap, just enough to stop an
  -- unbounded payload, never a meaningful limit a real host would hit.
  v_keywords text[] := (
    SELECT COALESCE(array_agg(DISTINCT trim(k)), '{}')
    FROM unnest(COALESCE(p_keywords, '{}')) AS k
    WHERE length(trim(k)) > 0 AND length(trim(k)) <= 60
  );
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF array_length(v_keywords, 1) > 20 THEN v_keywords := v_keywords[1:20]; END IF;

  UPDATE events e SET keywords = v_keywords
  FROM organizers o
  WHERE e.id = p_event_id AND o.id = e.organizer_id
    AND (o.owner_id = auth.uid() OR o.user_id = auth.uid());
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;

  RETURN jsonb_build_object('success', true, 'keywords', to_jsonb(v_keywords));
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_event_keywords(text, text[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_event_keywords(text, text[]) TO authenticated;
