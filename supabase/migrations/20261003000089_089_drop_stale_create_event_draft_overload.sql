-- 089: root-cause fix for a latent bug in migration 087 — it added
-- p_cover_image/p_included_items to create_event_draft via CREATE OR
-- REPLACE with a DIFFERENT parameter list than the original function,
-- which creates a new overload instead of replacing it, and never dropped
-- the original 11-param signature. Both overloads have lived side by side
-- since 087; any call that supplies only the ORIGINAL 11 named params
-- (omitting p_cover_image/p_included_items/p_intro, all optional) is
-- ambiguous between them ("could not choose the best candidate function"),
-- discovered while verifying migration 088's own p_intro round-trip.
DROP FUNCTION IF EXISTS create_event_draft(text, text, text, text, date, time, bigint, int, text, text, text);

-- Same latent bug, same root cause, in resubmit_event_for_review — its
-- original 9-param signature (before 087 added p_cover_image/
-- p_included_items) was never dropped either.
DROP FUNCTION IF EXISTS resubmit_event_for_review(text, text, text, text, text, date, time, bigint, int);
