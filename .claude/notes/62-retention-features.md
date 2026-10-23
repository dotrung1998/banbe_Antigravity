# 62 — Retention-plan features: what was built (2026-10-23)

Plan: `docs/retention-delight-plan.md`; how-to per phase: `docs/impl/`; production log: note 61; legal limits:
`docs/policy-retention-draft.md`. Shared parity vectors: `tests/fixtures/{event-market,app-events,quick-wins,core-loops}.json`.
SQL suites 23–27 (`supabase/_localtest/retention_suites_run.sh`, now versioned).

## Switches (Admin › Feature switches; table `app_feature_flag_defs` since 194, so a new switch is one INSERT)
| Key | Seed | What |
|---|---|---|
| push_enabled | OFF | APNs push (194). Off = nothing queued |
| app_events | OFF | first-party measurement (196). Needs the B12 re-consent decision |
| event_reminders | ON | L1 reminders (199), transactional in-app |
| event_recap / host_recap / follow_alerts | OFF | L2 / L3 / L4 (199) |
| weekly_digest / intent_foryou / live_activity / market_share | OFF | L5 / L6 / L7 / L8 (200) |
Clients: `src/lib/featureFlags.js` ⇄ `Lib/FeatureFlags.swift` (every new key is dark-until-set except event_reminders).
Policy passages per switch: `src/lib/contentFlags.js` ⇄ `Lib/ContentFlags.swift` (content key = switch key).

## Phase 0
- **F1** `app_events` + `log_app_events` (whitelist table `app_event_names`, signed-in only, 50/call, 600/user/hour,
  13-month purge `bb_purge_app_events`), `profiles.market` (set once from the first booked/hosted event's country),
  `admin_retention_report` (test accounts = phone-test exemption + `report_excluded_users` + admins + test addresses;
  groups < 20 → "<20"). Clients: sinks in `src/lib/analytics.js` / `Lib/AppEventsSink.swift`; Admin › Retention report.
- **F2** see note 60. **F3** 185 applied; age 16 (197, `AGE_TOO_YOUNG`, existing accounts not re-checked); policy
  effective date 6 October 2026; legal name/address/enterprise code/contact email/SMS provider BLOCKED on the owner.
- **F4** `docs/interview-guide.md` (needs the owner).

## Push preparation (194 extended before it was applied)
Quiet hours 22:00–07:00 in the device's zone (`device_push_tokens.timezone`, `push_quiet_until`), promotional kinds
(`notification_kind_policy`) only with `notification_preferences.promo_push`, dry run `skipped_no_credentials`,
retry backoff. Sender env `APNS_KEY_ID/TEAM_ID/BUNDLE_ID/PRIVATE_KEY/ENV`. iOS: Debug carries aps-environment; the app
registers only while push_enabled is on; Q6 pre-permission sheet after the first confirmed ticket
(`PushAskSheet`, `PushAsk.shouldOffer`). Owner steps: `docs/apple-setup-checklist.md`.

## Phase 1 (198 + clients)
Q1 ticket reveal, Q2 what-happens-next + typical confirmation time (n ≥ 5), Q3 ended page (ended beats ticket in
`reserveBarState`), Q4 check-in moment, Q5 host "You're live" card, Q6 translations (198), Q7 iOS invite + `?ref`
(new accounts only, like web), Q8 "Saved, coming up". Once-only keys `banbe.moment.*.v1.<id>`. Rules:
`src/lib/quickWins.js` ⇄ `Lib/QuickWins.swift`. Notes: the awaiting-confirmation timer that shows how long the host has
to respond was kept (informational, pre-existing); the host's note on the ticket is the host's own chat greeting;
checked-in bookings (status `attended`) now count as tickets.
