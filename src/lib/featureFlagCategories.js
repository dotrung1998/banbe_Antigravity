// Admin > Feature switches, grouped (note 64). iOS twin: apps/ios/BanbeApp/Lib/FeatureFlagCategories.swift — the
// unit test tests/unit/featureFlagCategories.test.mjs checks both lists match and cover every flag exactly once.
//
// `onboarding_version` is not a flag key: it is the one control for onboarding_v2 + onboarding_v3 (migration 202).
// `admin_event_wipe` only exists on iOS (a testing-phase tool, note 54), so web never lists it.

export const ONBOARDING_CONTROL = 'onboarding_version';
export const CONTROL_KEYS = { [ONBOARDING_CONTROL]: ['onboarding_v2', 'onboarding_v3'] };

export const FLAG_CATEGORIES = [
  { key: 'onboarding', vi: 'Giới thiệu & khám phá', en: 'Onboarding & discovery', flags: [ONBOARDING_CONTROL, 'intent_foryou', 'market_share'] },
  { key: 'rewards', vi: 'Phần thưởng & gắn kết', en: 'Rewards & engagement', flags: ['rewards', 'rewards_v2'] },
  { key: 'notifications', vi: 'Thông báo & giữ chân', en: 'Notifications & retention', flags: ['push_enabled', 'event_reminders', 'follow_alerts', 'weekly_digest', 'live_activity'] },
  { key: 'events', vi: 'Sự kiện & tổng kết', en: 'Events & recaps', flags: ['event_recap', 'host_recap'] },
  { key: 'types', vi: 'Loại sự kiện', en: 'Event types', flags: ['event_type_profiles'] },
  { key: 'platform', vi: 'Nền tảng & đo lường', en: 'Platform & measurement', flags: ['app_events'] },
];

/** The flag keys a category row stands for (a control expands to its keys). */
export const keysOf = row => CONTROL_KEYS[row] || [row];
