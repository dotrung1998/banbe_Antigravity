# Phase 3 — L5–L9: implementation plan (2026-10-23)

All behind switches that start OFF (owner brief: promotional messaging and anything needing consent or legal review
must be fully inert until the owner switches it on). Server: migration 200. Clients: web + iOS together.

| Item | What ships | Switch (seed) | Why off |
|---|---|---|---|
| L5 weekly digest | Opt-in toggle in Notifications settings (off by default, can't opt in while the switch is off); Thursday 18:00 local in-app notice "This weekend" opening the This-weekend rail; never empty; once a week; push only with promo opt-in; consent log append-only ≥ 1 year | `weekly_digest` OFF | promotional: Decree 91/2020 + CAN-SPAM review, company address placeholder |
| L6 intent For You | Home For You section title + one "because you said…" line from the onboarding GOAL (meet people / learn / experiences / networking); stated answers only, no behaviour inference, no % match | `intent_foryou` OFF | product check before showing |
| L7 day-of card | Web: on event day the Next-up banner shows the ticket QR one tap away. iOS: Live Activity extension (ActivityKit), started locally on event day for a confirmed ticket, updated locally, ended after the start + 12 h; no remote updates | `live_activity` OFF | needs a real-device check; Lock Screen shows event info |
| L8 market sharing | Share sheet gains "Zalo" (VN events: zalo.me share link) and "Text a friend" (US events: `sms:` with the link) next to the system share; `share_completed` measured | `market_share` OFF | product check |
| L9 Rewards | Preparation only: `docs/impl/rewards-switch-on.md` checklist. `rewards` and `rewards_v2` NOT changed | — | owner + lawyer |
