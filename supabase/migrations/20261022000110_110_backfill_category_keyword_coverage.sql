-- Search-matcher fix (Issue 2, 2026-09-30) — live-DB audit
-- (scratchpad `audit_search.mjs`, service-role read, snapshot at
-- `scratchpad/audit_rows_snapshot.json`) found migration 108's own
-- backfill only ever fires `WHERE e.keywords = '{}'` — a row that already
-- had ANY keywords (including two real live rows seeded with organizer-
-- typed keywords unrelated to their category, e.g. `['Bi','Trung']` on
-- `test-6faea2`) was skipped entirely and never got its category terms
-- added. Combined with a real client-side bug (also fixed this pass,
-- GocContext.jsx `createSubmit`/AppState+Data.swift `createSubmit`): a
-- non-blank organizer-typed keywords field used to REPLACE the category
-- default rather than supplement it, so this gap could keep recurring for
-- every future event where an organizer types their own keywords.
--
-- This migration is a one-time, idempotent SUPPLEMENT: for every event
-- whose `keywords` does not already contain its own category label/key
-- (case/diacritic-insensitive), append the category label + key — never
-- removes or reorders an organizer's existing entries, never touches a
-- row that already has its category covered. Safe to re-run.
--
-- NOTE: the primary fix for "Supp" vs the "Supper club" chip is the
-- matcher itself (src/lib/search.js / Lib/Search.swift), which no longer
-- depends on `keywords` for category coverage at all — this backfill is
-- defense-in-depth for any OTHER code path that reads `keywords` directly
-- (and keeps the column itself honest/inspectable), not a required fix.
UPDATE events e
SET keywords = (
  SELECT COALESCE(array_agg(DISTINCT kw ORDER BY kw), '{}')
  FROM (
    SELECT unnest(e.keywords) AS kw
    UNION
    SELECT unnest(array_remove(ARRAY[e.cat_label, e.cat_key], NULL)) AS kw
  ) combined
  WHERE length(trim(kw)) > 0
)
WHERE e.cat_label IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM unnest(e.keywords) AS k
    WHERE lower(k) = lower(e.cat_label) OR lower(k) = lower(e.cat_key)
  );
