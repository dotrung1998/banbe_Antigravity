// Tracks which version of the policy a user's consent (profiles.policy_
// accepted_at/.policy_version, migration 055) refers to. Bump this string
// whenever the policy text in src/screens/Policy.jsx materially changes —
// existing users are NOT re-prompted automatically by a version bump alone
// (that would need its own re-consent flow); this is proof-of-consent
// bookkeeping, per banbe_User_Policy.md's B1/B3 PDPL requirement.
export const POLICY_VERSION = '2026-09-18';
