-- Rollback for migration 165 (rewards, badges, streak, cosmetic unlocks).
-- NOT in the migration chain. DESTROYS every ledger entry, badge, streak day and unlock.
-- Keychains that use a reward design are reset to the free default first, then the original
-- (164) save_my_keychain and design CHECK are restored. Bookings/check-ins are untouched.
BEGIN;
UPDATE public.profile_keychains SET design_id = 'sky-star' WHERE design_id IN ('rwd-comet','rwd-lantern','rwd-crown');
DROP TRIGGER IF EXISTS profile_keychains_require_unlock ON public.profile_keychains;
DROP FUNCTION IF EXISTS public.profile_keychains_require_unlock();
ALTER TABLE public.profile_keychains DROP CONSTRAINT IF EXISTS profile_keychains_design_id_check;
ALTER TABLE public.profile_keychains ADD CONSTRAINT profile_keychains_design_id_check CHECK (design_id IN (
  'sky-star','sky-moon','sky-cloud','love-heart','love-ribbon','love-bow',
  'bloom-flower','bloom-tulip','bloom-strawberry','bloom-lemon','cafe-cup','cafe-note','cafe-vinyl',
  'pals-cat','pals-bear','pals-paw','trip-ticket','trip-plane','trip-compass','trip-suitcase',
  'banbe-b','banbe-stub','banbe-spark','banbe-wave','custom'));
-- save_my_keychain: re-apply migration 164's definition (it only differs by the reward-id list and the lock check).

DROP TRIGGER IF EXISTS rewards_checkin_ins ON public.check_ins;
DROP TRIGGER IF EXISTS rewards_checkin_del ON public.check_ins;
DROP TRIGGER IF EXISTS rewards_seat_checkin ON public.booking_attendees;
DROP TRIGGER IF EXISTS rewards_event_status ON public.events;
DROP TRIGGER IF EXISTS rewards_onboarding ON public.profile_event_preferences;
DROP TRIGGER IF EXISTS favorites_stamp_created_at ON public.favorites;
DROP FUNCTION IF EXISTS public.favorites_stamp_created_at();
ALTER TABLE public.favorites DROP COLUMN IF EXISTS created_at;

DROP FUNCTION IF EXISTS public.get_my_reward_summary();
DROP FUNCTION IF EXISTS public.get_my_rewards();
DROP FUNCTION IF EXISTS public.get_my_unlocked_cosmetics();
DROP FUNCTION IF EXISTS public.redeem_reward(text);
DROP FUNCTION IF EXISTS public.record_active_day(text, text);
DROP FUNCTION IF EXISTS public.rewards_trg_checkin();
DROP FUNCTION IF EXISTS public.rewards_trg_seat_checkin();
DROP FUNCTION IF EXISTS public.rewards_trg_event_status();
DROP FUNCTION IF EXISTS public.rewards_trg_onboarding();
DROP FUNCTION IF EXISTS public.rewards_sync_booking(uuid);
DROP FUNCTION IF EXISTS public.rewards_desired_sources(uuid);
DROP FUNCTION IF EXISTS public.rewards_invalidate_if_orphan(uuid, text);
DROP FUNCTION IF EXISTS public.rewards_validate_attendance(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.rewards_reverse_attendance(uuid, text);
DROP FUNCTION IF EXISTS public.rewards_award_attendance(uuid, text, int);
DROP FUNCTION IF EXISTS public.rewards_streak_of(uuid);
DROP FUNCTION IF EXISTS public.rewards_refresh_badges(uuid);
DROP FUNCTION IF EXISTS public.rewards_badge_progress_of(text, jsonb);
DROP FUNCTION IF EXISTS public.rewards_badge_counts(uuid);
DROP FUNCTION IF EXISTS public.rewards_attendee_eligible(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.rewards_event_owner_ids(text);
DROP FUNCTION IF EXISTS public.rewards_add_entry(uuid, text, int, text, uuid, text, jsonb);
DROP FUNCTION IF EXISTS public.rewards_balance(uuid);
DROP FUNCTION IF EXISTS public.rewards_lock_user(uuid);

DROP TABLE IF EXISTS public.reward_unlocks, public.reward_catalog, public.reward_user_badges, public.reward_badge_defs,
  public.reward_active_days, public.reward_attendance_sources, public.reward_attendances, public.reward_ledger,
  public.reward_rule_versions CASCADE;
DROP FUNCTION IF EXISTS public.reward_ledger_append_only();
DROP FUNCTION IF EXISTS public.rewards_local_date(timestamptz);
DROP FUNCTION IF EXISTS public.rewards_tz();
DROP FUNCTION IF EXISTS public.rewards_rules();
COMMIT;
