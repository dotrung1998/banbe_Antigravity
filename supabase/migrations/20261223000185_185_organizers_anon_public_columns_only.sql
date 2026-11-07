-- 185 — Signed-out visitors (anon) may read only an organizer's PUBLIC profile columns.
--
-- Problem (note 48, "SECURITY: pre-existing"): `organizers_select_public` (001) is `TO anon, authenticated
-- USING (true)` and anon holds Supabase's default table-level SELECT, so anyone holding the shipped anon key could
-- read every organizer's bank_name, bank_account_name, bank_account_no, momo_phone, pay_qr_path, pay_qr_payload,
-- pay_note, billing_address, tax_code, alert_phone, telegram_chat_id, owner_id and user_id.
--
-- Fix: replace anon's table-wide SELECT with a column grant of public profile fields only. Rows stay visible
-- (the policy is unchanged); private columns are simply not selectable by anon. Columns added in the future are
-- NOT granted to anon by default (fail closed) — grant them here explicitly if they are genuinely public.
--
-- Prerequisite (same migration, so they can never be applied apart): `events_select_public` (113) checked host
-- access with an inline `EXISTS (SELECT 1 FROM organizers o ... o.owner_id = auth.uid() OR o.user_id = auth.uid())`.
-- Postgres checks column privileges inside policy subqueries too, so once anon loses owner_id/user_id every
-- signed-out read of `events` (and of `event_photos`, whose policy reads `events`) would fail with
-- "permission denied for table organizers". The policy now calls `public.is_event_host(events.id)` instead:
-- the SAME condition (organizer owner_id/user_id = auth.uid()), already SECURITY DEFINER and anon-callable
-- (113), already used by event_invites and the private-photo storage policies without recursion.
--
-- Unchanged on purpose:
-- - `authenticated` keeps full SELECT (guest payment screens read the host's bank/QR columns — a separate,
--   product-level decision, see note 49).
-- - Every SECURITY DEFINER RPC (get_public_profile, get_organizer_profile, get_organizer_team, Pulse,
--   get_published_share_card, get_survey_public, …) is unaffected by column grants.
-- - service_role (api/*, cron, scripts) bypasses grants.
--
-- Signed-out reads this must keep working (audit, note 49):
--   web loadWeekendEvents/loadDiscoveryEvents/loadRealEventsById   organizers: id, name
--   web Map fetchLiveEvents, iOS loadMapEvents                      events -> organizers(name)
--   api/photo-share.js (anon client)                                events -> organizers(name, verified)
--   iOS loadOrganizerProfile                                        organizers: avatar_r2_ref
--   iOS resolveOrganizerID                                          organizers: id  (filtered by name)
--
-- Rollback (if ever needed — run by hand, do not add as a migration):
--   GRANT SELECT ON public.organizers TO anon;
--   (and, optionally, restore 113's inline EXISTS in events_select_public)

BEGIN;

-- 1. events: same host condition, no direct read of organizers' private columns.
DROP POLICY IF EXISTS "events_select_public" ON public.events;
CREATE POLICY "events_select_public" ON public.events FOR SELECT TO anon, authenticated USING (
  (status IN ('live', 'ended', 'cancelled') AND visibility = 'public')
  OR public.is_event_host(events.id)
);

-- 2. organizers: anon keeps the public profile only.
REVOKE SELECT ON public.organizers FROM anon;
GRANT SELECT (
  id, name, verified, organizer_type, hosting_since,
  about, bio, intro_long, social_links, ig_handle, instagram,
  avatar_path, avatar_r2_ref
) ON public.organizers TO anon;

COMMIT;

-- Verification (run after `supabase db push`, as anon via the REST API with the anon key):
--   GET /rest/v1/organizers?select=id,name&limit=1                  -> 200
--   GET /rest/v1/organizers?select=bank_account_no&limit=1          -> 401/403 "permission denied"
--   GET /rest/v1/organizers?select=*&limit=1                         -> permission denied (select=* needs every column)
--   GET /rest/v1/events?select=id,name,organizers(name)&limit=1      -> 200 (embed still works)
--   GET /rest/v1/event_photos?select=id&limit=1                      -> 200
