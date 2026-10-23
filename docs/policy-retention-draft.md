# Policy and legal notes for the retention-plan features (INTERNAL, not user-facing)

User-facing text for each feature lives in `src/screens/Policy.jsx` ⇄ `apps/ios/BanbeApp/Views/PolicyView.swift`,
shown only while that feature's switch is on (content keys in `src/lib/contentFlags.js` ⇄ `Lib/ContentFlags.swift`).
The policy version (`src/lib/policy.js`, 2026-10-06) is NOT changed and no consent gate is triggered by this run.

## The blocking rule: B12 promises renewed consent
Policy B12 says: "If we change the purposes of processing or the kinds of data collected, we ask for your consent
again in the app before the change applies." So any switch below that adds a NEW kind of data or a NEW purpose must
stay OFF until the owner decides on a policy-version bump + a re-consent flow (there is none yet, note 09).

| Switch | New data or purpose? | Can be turned on without re-consent? |
|---|---|---|
| `push_enabled` | No new kind: device tokens are already in B2, notices are purpose (4). Adds device time zone + Apple as a processor (B5). | TODO(lawyer): likely yes (Apple as sub-processor should be listed; text ready, gated). |
| `app_events` | Yes: usage events, purpose (7) | **No** — needs re-consent per B12. TODO(lawyer): legal basis under PDPL 91/2025 (consent vs legitimate interest is narrow in VN); CCPA notice at collection for US users. |
| reminders (L1) | No: purpose (4) "notices about your bookings and events" | Yes (transactional, opt-out per kind). |
| `event_recap` feedback (L2) | Yes: private feedback answers + optional note | **No** — needs re-consent per B12. TODO(lawyer): note text is free text shared with the host (B4 who-sees-what). |
| `host_recap` (L3) | Aggregates to hosts (turnout, repeat count, feedback ≥3) | TODO(lawyer): aggregates only, k ≥ 3 for feedback; likely within B4 if described. |
| `follow_alerts` (L4) | New use of follows (notifications about new events) | TODO(lawyer): is it "notices about your events" or marketing? Built opt-out per kind; treat as marketing in the US (CAN-SPAM for email) if counsel says so. |
| `weekly_digest` (L5) | Promotional messaging | **No** without opt-in: Decree 91/2020 (prior consent, unsubscribe, ≤3 ads/24h, 07:00–22:00, keep consent records 1 year) and CAN-SPAM (unsubscribe, physical address — needs the company address, currently a placeholder). |

## Other open items
- TODO(lawyer): age minimum 16 (migration 197) matches policy A1; confirm the US position (COPPA applies under 13;
  some US states set 16 for certain processing).
- TODO(lawyer): interview consent wording and 30-day retention of recordings (`docs/interview-guide.md`).
- BLOCKED (owner facts, not legal judgement): company legal name ("CÓMPANY" placeholder), registered address,
  enterprise code, contact email, Vietnamese SMS provider. Only the effective date was filled (6 October 2026, the
  date of policy version 2026-10-06).
- Fact to fix with the next policy version: B5 says Google sends email; the code uses Resend (Gmail only as fallback).
