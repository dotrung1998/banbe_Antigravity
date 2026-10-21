// "Before you go" pop-up in front of account deletion (owner, 2026-10-21; from "We Studied 393 Cancel Flows. This
// Wins People Back."): show what the person would lose, ask why, and offer the one fix that matches the reason —
// with deletion always one plain tap away (no confirmshaming). Pure logic, unit-tested.
// iOS twin: apps/ios/BanbeApp/Lib/AccountRetention.swift — change both together.

/** Same codes the server's `delete_account` accepts as `reasonCode`. */
export const DELETE_REASONS = [
  { code: 'not_using', vi: 'Tôi không còn dùng banbe nữa', en: "I don't use banbe anymore" },
  { code: 'privacy', vi: 'Lo ngại về quyền riêng tư', en: 'Privacy concerns' },
  { code: 'found_alternative', vi: 'Tôi dùng ứng dụng khác', en: 'I use a different app' },
  { code: 'too_many_notifications', vi: 'Quá nhiều thông báo/email', en: 'Too many notifications/emails' },
  { code: 'other', vi: 'Khác', en: 'Other' },
  { code: 'prefer_not_say', vi: 'Không muốn cung cấp', en: 'Prefer not to say' },
];

/** Kinds "quieter notifications" mutes: only the broadcast kind; every transactional kind stays on. */
export const QUIETED_NOTIFICATION_KINDS = ['event_announcement'];

/** The fix offered for a leaving reason; null when no reason is picked. */
export function retentionOffer(reason) {
  switch (reason) {
    case 'too_many_notifications': return 'quieterNotifications';
    case 'not_using': return 'retuneForYou';
    case 'privacy': return 'reviewPrivacy';
    case 'found_alternative': case 'other': case 'prefer_not_say': return 'takeABreak';
    default: return null;
  }
}

/** What deleting would take away, most valuable first. Zero rows are left out; coins only while the Rewards
 *  feature switch is on (note 51). */
export function lossRows({ bookedEvents = 0, savedEvents = 0, followedHosts = 0, coins = null, rewardsEnabled = false, hostedEvents = 0 }) {
  const rows = [
    { kind: 'bookedEvents', count: bookedEvents },
    { kind: 'hostedEvents', count: hostedEvents },
    { kind: 'savedEvents', count: savedEvents },
    { kind: 'followedHosts', count: followedHosts },
  ];
  if (rewardsEnabled && coins != null) rows.push({ kind: 'coins', count: coins });
  return rows.filter(r => r.count > 0);
}
