-- Migration 232 (note 101): admin switch `island_toasts`, seeded OFF.
--
-- On = web in-app notifications rise on a Dynamic-Island-style pill instead of the card stack (src/components/island,
-- src/lib/islandPrefs.js). Every signed-in person can then pick one of eight styles, top/bottom, title-only/full and
-- spring/calm at Account › Notifications › Island style, saved per browser. Admins get "Dynamic Island demo" in
-- Review & moderation: every notification case, one tap each, on sample copy (nothing saved or sent).
--
-- What this can and cannot be: iOS never lets a web page draw inside the physical Dynamic Island. dynaura draws a
-- web-native island in the same place with the same motion; in a Home Screen app it sits at the top of the app just
-- below the system island, and in a Safari tab it sits at the top of the page. No Live Activity / ActivityKit state
-- is created, and the iPhone app ignores this switch (it has its own native surfaces).
--
-- Client-only switch: no data changes. Rollback: supabase/rollbacks/20261231000222_222_revert_island_toasts_switch.sql
-- The FK from app_feature_flags.key to app_feature_flag_defs.key (migration 194) is why the def goes in first.

INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('island_toasts', 'Web: in-app notifications rise on a Dynamic-Island-style pill, with style choices and an admin demo', '232')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES ('island_toasts', false)
ON CONFLICT (key) DO NOTHING;
