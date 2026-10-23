# Phase 1 — quick wins Q1–Q8: implementation plan (2026-10-23)

Plan items: `docs/retention-delight-plan.md` §4 Phase 1. Web + iOS together; celebrations once per milestone per device,
Reduce Motion and VoiceOver respected; no countdowns, no "hurry", no loss framing.

| Item | Server | Web | iOS | Switch |
|---|---|---|---|---|
| Q1 "Your ticket is ready" | — | Confirmed.jsx: first view of a newly confirmed ticket → short ticket reveal (ConfettiBurst, reduced motion = fade), then calm next steps (calendar, give a ticket, address) | ConfirmedView: same + `Haptics.success` + VoiceOver announcement | none (in-app, transactional) |
| Q2 honest wait | 198 `get_host_confirmation_time` (n ≥ 5 or nothing) | awaiting-confirmation card: "what happens next", host's typical time when known, "we'll notify you" | same | none |
| Q3 ended-event page | — (data exists: photos 084, follows, host events) | `reserveBarState`: ended wins over the ticket; attendee "You went ✓" / others "Missed it?" + recap photos, Follow host, next from this host | same in EventDetailView / ReserveBar.swift | none |
| Q4 check-in moment | — | ticket screen sees `checked_in` → "You're in. Enjoy tonight!" once | same + light haptic | none |
| Q5 host "You're live" | — | `event_approved` → celebration card with Share / Copy link / Add to Schedule, once per event | same | none |
| Q6 push ask + language | 198 translation rows | (no web push; nothing to ask) | done in 194 pass (PushAskSheet) | push_enabled |
| Q7 iOS referral parity | — (023 `redeem_referral`) | — (exists) | Invite card in Account + `?ref=` redemption on universal-link/deep-link open | none |
| Q8 saved, coming up | — (`get_public_event_fill`) | Home row of upcoming saved events with real date and real fill ("12 of 20 taken") | same | none |

Shared vectors: `tests/fixtures/quick-wins.json` (ended-vs-ticket precedence, which once-only keys, saved-row
selection/ordering, fill text). Metrics come from F1 events (`ticket_opened`, `share_completed`, `follow_tapped`).
