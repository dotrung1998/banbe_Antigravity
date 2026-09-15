# banbe

## Ticket escrow flow — stage notes

- [.claude/notes/01-hold-payment.md](.claude/notes/01-hold-payment.md) — hold slot (30min) + payment window: WORKING
- [.claude/notes/02-confirm-qr.md](.claude/notes/02-confirm-qr.md) — organizer 1h confirm / QR issuance: PARTIALLY WORKING (no auto-confirm)
- [.claude/notes/03-dispute-chat.md](.claude/notes/03-dispute-chat.md) — "not found" branch + temporary dispute chat: WORKING (stage boundary mismatch vs code — see file)
- [.claude/notes/04-admin-escalation.md](.claude/notes/04-admin-escalation.md) — raise to banbe admin + admin decision: WORKING
- [.claude/notes/05-notify-retention.md](.claude/notes/05-notify-retention.md) — email+PDF notification + 72h soft-delete retention: MOSTLY WORKING (real send verified via `tests/dispute-flow-e2e.spec.js`; PDF attachment specifically still unverified on Vercel)
- [.claude/notes/06-design-tokens.md](.claude/notes/06-design-tokens.md) — iOS-vs-web design token diff + shared `alert` color token: canonical values, read before re-diffing colors
- [.claude/notes/07-notifications.md](.claude/notes/07-notifications.md) — in-app toast + real push: BROKEN (no proactive surfacing at all) before this pass, fixed for in-app; push blocked on a real APNs key
- [.claude/notes/09-auth-onboarding.md](.claude/notes/09-auth-onboarding.md) — mandatory login + policy consent + splash-before-login: WORKING (web + iOS); policy version-bump question still open, see file
