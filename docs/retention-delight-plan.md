# banbe — Retention, delight and personalisation plan (VN + US, web + iOS)

## Context
The owner shared a summary of three design videos (peak-end rule, Undertone's "second visit", Netflix's friction, personalisation and viral UX) and asked for a concrete plan for banbe. The plan has to fit banbe's real flows, both markets and the hard rules: no dark patterns, coins with no cash value, server-authoritative awards, an append-only ledger, current policy, web/iOS parity, and per-market law and timezones.

It builds on what already exists: notes 17, 34–59, `docs/retention-monetization-roadmap.md` (the Sept roadmap, with real saves and a "This weekend" rail done; its weekly digest and P2 "after the event" items not built) and `docs/policy-rewards-draft.md`.

Status (2026-10-23 run; details: notes 60–62, production log note 61, how-to `docs/impl/`):

| Item | State |
|---|---|
| F1 measurement | built + migration 196 applied + web deployed; switch `app_events` OFF (needs the B12 re-consent decision) |
| F2 US tz/currency | applied (195) + verified in production + deployed; paid USD booking off by decision |
| F3 trust | 185 applied; age 16 applied (197) + deployed; effective date filled; company name/address/enterprise code/contact email/SMS provider BLOCKED (owner facts) |
| F4 interviews | guide written (`docs/interview-guide.md`); NEEDS OWNER |
| Push prep | built, 194 applied, `push_enabled` OFF; BLOCKED on the Apple account + APNs key (`docs/apple-setup-checklist.md`) |
| Q1–Q5, Q7, Q8 | built + deployed (web); iOS built and unit-tested, not shipped to TestFlight |
| Q6 | push ask built (iOS, waits for push_enabled); translations applied (198) |
| L1 reminders | applied (199) + deployed; switch `event_reminders` ON (in-app); email not built (mail setup unverified) |
| L2 / L3 / L4 | applied (199) + clients deployed; switches OFF (L2 needs B12 re-consent; L3/L4 product/legal check) |
| L5 digest | applied (200) + opt-in UI deployed; switch OFF (legal review: Decree 91/2020, CAN-SPAM) |
| L6 / L7 / L8 | see the last status update below this table (Phase 3 clients) |
| L9 Rewards | prepared only (`docs/impl/rewards-switch-on.md`); `rewards` / `rewards_v2` unchanged (OFF) |

Each phase has its own implementation plan in `docs/impl/`. Baseline query (counts only): `docs/sql/retention-baseline.sql`.

---

## 0. Bottom line
1. **The app stops at the ticket.** After booking there is no peak, and after the event there is no ending. There are no guest reminders, no recap, no feedback, and nothing tells a guest what to do next. This is the biggest retention gap, and it matches the attachment's core lesson.
2. **We cannot yet see where users return on their own.** There is no analytics sink, no market field per user, and production is nearly empty. As of 2026-10-22 (note 58), 6 users had reward activity, with 3 active days and 0 check-ins. Measurement comes first, because without it every proposal below is a guess.
3. **The US market is broken at the data layer.** Start times are stored as Vietnam time (`112:147-148, 309-310`; the iOS pickers are locked to VN), so a US host's 19:00 shows as 05:00 PDT on cards. Prices are VND-only. US retention work is pointless until this is fixed.
4. **Netflix's main problem doesn't apply to us.** Netflix had too much choice. banbe likely has too little real supply in a given city and week, so honest empty states, follow-host alerts and "next from this host" beat heavier personalisation.
5. A lot of good foundation is already built and live (see 2a). Most of the quick wins are client-only and reuse existing components.

---

## 1. Evidence check of the attachment
| Claim | Verdict | Note |
|---|---|---|
| Peak-end rule | **Supported for retrospective ratings.** | 2022 meta-analysis (Alaybek et al., *OBHDP*, 174 effects, r≈.58). The overall average predicts about as well, and evidence that it changes *repeat behaviour* is thinner. Use it to choose which moments to polish, not as a growth law. |
| Disney "70% return" | **Weak.** | No primary data. It traces to the Disney Institute book *Be Our Guest*. Don't cite it. |
| Netflix: 15% manual skip, 136M presses a day, 195 years saved | **Company-stated** (Netflix blog, 2022). | Fine as an anecdote. It isn't audited. |
| Netflix: 80% of viewing from recommendations | **Company-authored paper** (Gomez-Uribe & Hunt 2015, ACM TMIS). | Real, but it applies at massive catalogue scale, not ours. |
| 1,300 micro-genres, 230M users, $400B | Secondary or volatile. | Irrelevant to decisions. |
| Undertone metrics (50% never recorded, median 10 min, ~10% lost) | **Single case study, founder estimates, marketing context.** | The method ("find where users already show up") is the valuable part. The numbers are not. |
| "% match" scores create delight | **Opinion.** | For banbe, a match score on tiny data is false precision. Rejected (§6). |

Our own evidence is stronger on one point. Measured across more than 1,070 events, no-shows ran a median of 28% for free events and 17% for paid ones (PheedLoop). That makes reminders and day-of clarity a measurable lever.

---

## 2. Findings

### 2a. What we already do well (keep, don't rebuild)
- **Onboarding:** one question per screen with a head start, and a real For You reveal with confetti and ♡ Save (notes 43, 49, 53). Preferences are stored in an owner-only table and never shown to hosts (162).
- **Discovery:** a discovery-first Home (search, categories, filter sheet with counts, a "This weekend" rail, a Next-up banner 24h before an event, a For You chip) (notes 50, 37, 35). Map For You (36).
- **Honest friction design:** smart defaults that never touch consent or money, outcome-labelled CTAs, disabled buttons that say why, and loss framing only when it's real (note 48). The booking journey bar runs Event ✓ → Hold → Pay → Ticket.
- **Schedule tab with calendar export** (.ics, a Google link, and the iOS editor that needs no permission) (notes 44, 49).
- **Host tools:** "Recipe for success" with k-anonymous benchmarks, live fill (186), announcements (166), promo texts sent from the host's own phone with consent default OFF (123), Reports (43/46).
- **Rewards v2:** weekly streak, grace weeks, repair, tiers, a monthly goal, server-authoritative and append-only, live but **switched OFF** (note 58). Celebrations fire once per device and respect VoiceOver.
- **Ethical guardrails are already codified:** notes 36, 48, 59 and the roadmap ("no selling Pulse rank", "no forced daily opens").

### 2b. Biggest friction points and dead ends (ranked)
1. **Ticket → event → after: nothing.** There are no scheduled reminders (no `cron.schedule` for guests). Payment confirmed and checked in are plain notifications. When an event ends, the cron (167) flips it silently, the event disappears from Home, and Event Detail shows "View your ticket" forever because `reserveBarState` prioritises the ticket over `ended`. There are no recap photos for guests, no feedback, no follow prompt and no "next" event.
2. **The host's real peak is wasted.** Confetti fires on *submit* (still pending, so there's nothing to share), while *approval*, the moment the event goes live, is a plain notification with no share prompt. When an event ends the host gets nothing: no turnout summary, no "run it again", no repeat-guest count, and new followers can't be counted because `follows` has no `created_at`.
3. **Waiting for manual payment confirmation (no auto-confirm, note 02)** is the most anxious stretch. Today it shows only an "awaiting" state, with no expected time and no reassurance.
4. **US correctness:** the timezone and currency problems in §0.3, plus Vietnamese-only notification titles for some kinds (166's "Thông báo từ host" is missing from the 142 translation table).
5. **Saves (♡) lead nowhere.** They aren't a Schedule source and trigger nothing later.
6. **The push permission prompt fires right after sign-in with no context** (`AppState+Push.swift`), and there is no APNs sender at all (blocked on the paid Apple account).
7. **Sold out is a dead end.** The "message for waitlist" option just opens a chat, and some sold-out logic still reads the never-decremented `seats_remaining` (note 50).
8. **Parity gap:** referral (`?ref=`) is redeemed and shared on web only. iOS mentions "Invite friends" in Help but has neither feature.

### 2c. Peak and ending map (guest and host journeys)
| Moment | Today | Best use |
|---|---|---|
| Onboarding reveal | **Peak exists** (confetti) | Keep |
| Hold → pay → *host confirms* | Plain toast | **Guest peak:** "Your ticket is ready" (Q1) |
| Event day | Next-up banner, only if the app is open | Reminder + day-of card (L1, L7) |
| Check-in at the door | Small "Checked in" label | Small moment (Q4) |
| **Event ended (+12h)** | Nothing | **Guest ending:** recap, private feedback, follow, next (L2) |
| Host submit | Confetti | Keep, but move the share ask to approval |
| **Host approved / live** | Plain notification | **Host peak:** "You're live" + share (Q5) |
| **Host event ended** | Nothing | **Host ending:** recap + "Run it again" (L3) |

### 2d. Where users already return on their own — data status
- **What we know:** almost nothing at usable scale. There's no `track()` sink (`src/lib/analytics.js`, `Lib/Analytics.swift` are no-ops), no app-open or last-seen data, and no per-user market column. Test accounts are mixed into production data (notes 05, 37, 57).
- **Proxies already in the database:**
  - `auth.refresh_tokens` per day, as an app-open proxy.
  - `notifications.read_at − created_at` by `kind`, showing which events pull people back fastest.
  - Booking lead time, and `favorites` and `messages` timestamps.
  - `story_views`, `photo_likes` after the event ends.
- **Market split, in order of preference:** `events.country_code` of the events a user booked or saved → phone prefix (+84 / +1) → `reward_user_settings.tz` → budget currency.
- **Attempted:** a counts-only, read-only query covering these proxies, split by market, returning aggregate counts only. The session's permission rules **blocked the production read**, so no numbers are reported here (Open question 3).
- **Baseline result (run once, 2026-10-23, `docs/sql/retention-baseline.sql`, test accounts excluded, groups < 20 hidden):**
  every group is `<20`: there are fewer than 20 real (non-test) users, so no rate can be reported yet, by market or
  overall. Shape only: markets VN and unknown (no US yet); app opens seen at 07, 08 and 18 Vietnam time, Tue–Thu;
  bookings confirmed, cancelled and expired; notifications people read: booking requested, hold created/expired, new
  message, organizer invite. Next measurement: F1's `admin_retention_report()` once real users arrive.
- **Hypotheses to test, with how to measure each:**
  - H1, the day-of ticket lookup: opens within 3h of `starts_at`.
  - H2, payment confirmed: `payment_confirmed` read latency.
  - H3, after the event: photo views and likes 0–72h after the end.
  - H4, weekend planning: opens on Thu–Sat evenings, in local time per market.

---

## 3. VN vs US: what changes per market
| Area | Vietnam | United States |
|---|---|---|
| Payment habit | Wallets ~38%, bank transfer ~28%, VietQR volume rising fast (Antom 2025 estimates). The host-QR model fits. | Cards and Apple Pay are the norm. Venmo, Zelle and Cash App QR codes for strangers add friction, so the manual-confirm wait hurts more. Long term this points to a card option (out of scope). |
| Sharing | Zalo has ~79M MAU (VNG Q3 2025); Facebook groups are also big. There's no Zalo share target today. | SMS and iMessage dominate (Partiful grew on SMS-first invites); Instagram too. |
| Language and time | `vi` default, one timezone | `en`, multiple timezones, so per-event timezones are mandatory |
| No-show risk | Mostly paid events (transfers) | More free RSVPs and the higher free-event no-show rate, so reminders matter more |
| Data and consent | **PDPL Law 91/2025 + Decree 356/2025** (in force 2026-01-01): consent is the main legal basis, and under-16s need parental consent. **Decree 91/2020** anti-spam: prior consent for advertising messages, ≤3 ad emails per 24h, texts only 07–22, unsubscribe, keep records 1 year. Promotions: Decree 81/2018 as amended by 128/2024 and 239/2026; loyalty programmes are a notification-only form, lucky draws need registration. | **FTC** dark-pattern guidance (fake timers and scarcity are deceptive); the **FTC fee rule** (all-in live-event ticket pricing, effective 2025-05-12); **CPRA** (consent obtained through dark patterns isn't consent); CAN-SPAM for email; TCPA for marketing SMS. Click-to-cancel was vacated in 2025 but isn't relevant to us. |
| App store | Same for both: Apple guideline 4.5.4 allows marketing push only with explicit opt-in and an in-app opt-out. | |
| Evidence gap | No good primary data on how Vietnamese Gen Z discovers events was found. Do interviews (Phase 0). | Partiful and Eventbrite numbers are third-party estimates. |

---

## 4. Prioritised proposals
Flags: **[M]** migration · **[P]** policy text change · **[L]** lawyer review · Effort S ≤3 days, M ≤2 weeks, L >2 weeks (web + iOS together)

### Phase 0 — Foundations (do first; nothing below can be measured without F1)
**F1 · First-party, privacy-safe measurement** — Both · M · Risk: privacy · [M][P][L-light]
- **Problem:** we can't find return moments or prove any change worked.
- **Evidence:** Undertone's insight came only from analytics. The roadmap's "Chỉ số" (metrics) section already lists the KPIs, but nothing is built.
- **Change** (nothing user-visible beyond a policy line):
  - Point the existing `track()` and `Analytics.sink` at a first-party `app_events` table: no vendor, ids and buckets only, 13-month retention.
  - Add `admin_retention_report()`, aggregate-only, hiding groups under 20 (existing rule). It reports D7/D30, time to 2nd attendance and notification read latency by kind, split by market, excluding test accounts (`account_phone_test_exempt` + the Test Accounts list).
  - Add `profiles.market` derived from the first booked or created event's `country_code`, overridable.
- **Metric:** a dashboard exists with a baseline per market within 2 weeks.

**F2 · US correctness: event timezone + currency** — US · M · Risk: data migration · [M] — **IMPLEMENTED LOCALLY 2026-10-22 (migration 195, note 60), not applied.** As built: paid USD booking stays off (owner decision); also restores 107's resubmission limit, history and duplicate guard that 112 dropped.
- **Change:**
  - Add `events.tz` (IANA, from the location tree) and `events.currency` (VND or USD).
  - `create_event_draft` and `resubmit` use `AT TIME ZONE events.tz`. Backfill: VN rows = `Asia/Ho_Chi_Minh`; US rows flagged for host review.
  - Show times in the event's timezone, with "your time" when it differs. Add a USD price input and formatter.
- **Metric:** 0 events whose `starts_at` disagrees with the host's entered local time. US events published.

**F3 · Trust prerequisites** — Both · S · [M][P][L]
- Apply the existing **185** migration (anon can read organizers' bank columns; live today).
- Enforce the policy's age minimum at the DOB gate. The policy says 16+; PDPL requires parental consent under 16. Today any date is accepted.
- Fill the policy placeholders.

**F4 · 10 interviews** — 5 guests and 5 hosts per market (roadmap already asks for host interviews). Ask where they return, how they share (Zalo or SMS) and what made them come back. Effort S, zero risk.

### Phase 1 — Quick wins (client-only unless marked; days each)
**Q1 · "Your ticket is ready" peak** — Both · S · Low risk
- **Problem:** the relief at the end of the most anxious wait (manual confirmation) is a plain toast.
- **Evidence:** peak-end; Undertone's recap "unboxing".
- **Change:**
  - The first time Confirmed shows a newly confirmed booking: a short ticket "unwrap", reusing `ConfettiBurst` and the iOS `Haptics.success`. It fires once per booking per device and respects Reduce Motion.
  - Then show a calm ending: Add to calendar, "Give a ticket to a friend" (exists), host address and notes.
  - No coins copy unless Rewards is on.
- **Metric:** calendar-add rate per confirmed booking; day-of ticket opens (F1).

**Q2 · Honest waiting screen** — Both, mostly VN · S
- **Change:**
  - "Awaiting host confirmation" shows what happens next.
  - It shows this host's *typical* confirmation time, only when there are 5 or more past confirmations, so it's real data and not a countdown.
  - It says "We'll notify you". Help is offered before the hold-expiry edge case.
- **Metric:** fewer `payment_needs_info` and disputes per booking; abandonment in the awaiting state.

**Q3 · Ended-event page instead of a dead end** — Both · S–M
- **Change:** fix the `reserveBarState` priority so `ended` wins.
  - **Attendee:** "You went ✓", the host's recap photos (`event_photos` already allows ended events, migration 084), Follow host, "Next from this host" or similar upcoming events.
  - **Non-attendee:** "Missed it? Next from this host".
- **Metric:** follow rate on ended pages; 2nd booking within 60 days.

**Q4 · Check-in moment** — Both · S
- **Change:** when the ticket screen sees `checked_in`, show "You're in. Enjoy tonight!" with a light haptic, once.
- **Metric:** qualitative (F4); this is cheap delight.

**Q5 · Host "You're live" peak** — Both · S
- **Change:** on `event_approved`, show a celebration card with Share (now allowed), Copy link and Add to Schedule. Submit's confetti stays, but its copy says sharing opens at approval.
- **Metric:** share within 24h of approval; bookings via shared links (F1 `ref` param).

**Q6 · Contextual push ask + l10n fixes** — Both · S · [M] small (translation rows)
- **Change:**
  - Move the push prompt to after the first confirmed booking ("Get reminded on the day?") instead of after sign-in.
  - Add the missing EN translations for notification kinds from 142 onward.
- **Metric:** push opt-in rate (once APNs exists); share of EN users seeing Vietnamese titles = 0.

**Q7 · iOS referral parity** — Both · S
- **Change:** an iOS Invite card and `?ref` redemption on universal-link open. No reward (keeps us clear of promotion rules).
- **Metric:** share of signups that come from `referral_joined`.

**Q8 · Saved events go somewhere** — Both · S
- **Change:** a Home "Saved, coming up" row showing real dates and real fill ("12 of 20 taken" from `get_public_event_fill`). No timers, no "hurry" copy.
- **Metric:** save → booking conversion.

### Phase 2 — Core loops (weeks; migrations)
**L1 · Event reminders (transactional)** — Both · M · [M][P]
- **Change:**
  - A cron sends a day-before and a ~3h-before reminder, in-app plus email (Resend), with push once APNs exists.
  - Reminders contain the ticket, the map link and the host note, in the event's timezone and the user's locale.
  - Quiet hours 22:00–07:00 local. Mute per kind (the 062 mechanism, now also server-side).
- **Legal:** reminders are service messages, not advertising, so no promo consent is needed. They must still have an opt-out and say so in the policy.
- **Metric:** **no-show rate** (check-ins ÷ confirmed seats), compared against the free 28% / paid 17% baseline by market.

**L2 · Post-event recap: the guest's ending** — Both · M · [M][P]
- **Problem:** the attachment's strongest idea, and our biggest hole.
- **Change:**
  - At `ended` (cron 167), attendees get one in-app notification: "Your evening at ___".
  - It opens a recap card: date, the host's photos once uploaded, "You've been to N banbe events", badge progress only if Rewards is on, Follow host, Next from this host.
  - **One-tap private feedback** to the host (👍 / 👎 + optional note). It is never public. Hosts see aggregates only when there are 3 or more responses.
- **Metric:** recap open rate; follow rate; **2nd attendance within 60 days**, the north-star; feedback response rate.

**L3 · Host recap + "Run it again"** — Both · M · [M]
- **Change:**
  - When an event ends, the host gets turnout, check-in rate, the feedback summary, new followers (adds `follows.created_at`) and repeat guests (as a count only).
  - One tap duplicates the event with the date moved forward, reusing note 48's smart defaults.
- **Metric:** hosts creating a 2nd event within 45 days.

**L4 · Follow-host alerts** — Both · M · [M]
- **Change:** when a followed host's event goes live, followers get an in-app notification (email later). At most 1 per day, bundled, and mutable.
- **Evidence:** fits the supply-scarce reality (§0.4).
- **Metric:** bookings attributed to follow notifications; mute rate as a guardrail.

### Phase 3 — After baseline data exists (≥6–8 weeks of F1 data)
**L5 · Weekly "This weekend" digest** (already in the roadmap; refined) — Both · M · [M][P][L]
- **Change:**
  - Opt-in, default OFF. In-app plus email. Never sent when empty.
  - Sent Thursday 18:00 local per market and timezone.
  - "Because you follow X" / "Because you like Y" labels.
- **Legal:** this is advertising. VN Decree 91 rules apply (consent records kept 1 year, 07–22 window, unsubscribe in every message), plus CAN-SPAM in the US.
- **Metric:** digest → event open → booking. **Stop condition:** unsubscribe rate above 2% per send.

**L6 · Intent-based For You** — Both · S–M
- **Change:**
  - Use the onboarding *goal* answer (meet people, learn, unwind…) to set the Home section title and wording, with an explanation line ("Because you said you want to meet people").
  - Stated preferences only. Never infer mood or emotion from behaviour (PDPL consent; §6).
- **Metric:** For You open → booking versus non-For You, measured pre/post. A/B testing isn't feasible: about 1,400 users per arm are needed (note 58).

**L7 · Day-of card** — Both · M
- **Change:** on iOS, a Live Activity on event day (starts locally; remote updates need APNs). On web, the parity equivalent: the Next-up banner pinned with the ticket QR one tap away.
- **Metric:** time from opening the app to showing the QR at check-in; check-in success rate.

**L8 · Market-native sharing** — VN focus · S–M · [L-light]
- **Change:** in VN, a "Share to Zalo" target and Zalo-sized link previews (extending note 40's sizing). In the US, an SMS-first share ("Text a friend") with the same preview.
- **Metric:** share → visit → booking per channel.

**L9 · Staged Rewards switch-on** — VN first · S (switch) · [P][L]
- **Change:** turn on `rewards` (v1) once L1 and L2 are live and the lawyer has confirmed coins redeemable only for digital keychains are not a regulated promotion. Keep `rewards_v2` off for 4+ more weeks. US follows after the CCPA notice text (note 58 lawyer list).
- **Metric:** 2nd-attendance rate before and after; guardrail: the off-window and cap rows stay rare.

---

## 5. Roadmap summary
| Phase | Items | Needs |
|---|---|---|
| 0 · Weeks 1–2 | F1 measurement, F2 US tz/currency, F3 trust (185, age, policy placeholders), F4 interviews | Migrations (F1, F2, F3); policy text (F1, F3); light lawyer review (F1, age) |
| 1 · Weeks 2–4 | Q1–Q8 | Client-only, except Q6 translation rows |
| 2 · Weeks 4–10 | L1 reminders, L2 recap + feedback, L3 host recap, L4 follow alerts | Migrations (all four); policy text (L1, L2 feedback data) |
| 3 · Week 10+ | L5 digest, L6 intent For You, L7 day-of, L8 sharing, L9 Rewards on | Lawyer (L5, L9); paid Apple account (push, Live Activity updates) |

Every item ships on web and iOS together, with shared test vectors where logic is shared (the `tests/fixtures/*.json` pattern from note 58). Each phase ends with a `.claude/notes/` entry.

---

## 6. Risks, ethics and what we will NOT copy
- **Not copying:**
  - **"% match" scores**: false precision on small data.
  - **Autoplay or "Are you still watching?" style continuation**: auto-booking or pre-selected next events.
  - **Daily streak pressure** or loss-framed streak notifications ("your streak ends tonight"). The weekly streak with grace stays silent.
  - **Countdowns on saved events**, and "X people viewing".
  - **Public ratings** while the volume is tiny: retaliation, defamation and small-n anonymity risks.
  - **Emotion inference from behaviour**: Netflix-style "emotional personalisation" is profiling, which needs explicit consent under PDPL and is a CPRA risk. We use stated answers only.
- **Celebration fatigue:** one moment per milestone, once per device. Reduce Motion is respected and VoiceOver announces it. Nothing celebrates spending.
- **Notifications:** transactional reminders are opt-out; anything promotional is opt-in and default OFF (Apple 4.5.4, Decree 91, CAN-SPAM). There are quiet hours, and nothing is sent when there's nothing real to say.
- **Measurement:** first-party only, aggregate reports with groups under 20 hidden, no chat, bank or answer content logged, disclosed in the policy.
- **Statistical honesty:** at current volume, no A/B claims. We report pre/post results with caveats and rely on interviews until each arm has around 1,400 users.
- **Supply risk:** retention mechanics can't fix empty weeks. When there is nothing nearby, honest empty states and follow alerts beat clever ranking.

---

## 7. Open questions (each with a recommendation)
1. **Is the US market live with real hosts, or planned?** *Rec:* F2 is a blocker either way. Until it ships, block US location selection in Create Event rather than publish wrong times. **Answered 2026-10-22:** not live yet, prepare for it. F2 built with free + USD-priced events; paid USD booking deferred.
2. **Measurement: first-party table or a vendor (e.g. PostHog EU)?** *Rec:* first-party. It matches the current "no third-party trackers" policy and avoids PDPL cross-border transfer paperwork.
3. **May I run one counts-only, read-only production query** (sign-in/refresh-token days, notification read latency by kind, booking lead times, market split)? It is blocked in this session. *Rec:* allow it once, or run it yourself: `supabase db query --linked -f docs/sql/retention-baseline.sql`.
4. **Post-event feedback: private to the host only, or public ratings?** *Rec:* private only, with aggregates shown at 3 or more responses. Revisit public ratings past roughly 50 events per host category.
5. **Buy the paid Apple Developer account now?** *Rec:* yes. It unblocks push (L1), Live Activity updates (L7) and Wallet (note 24). **Answered 2026-10-22:** yes. Push pre-built (migration 194, note 60); turn-on steps in `docs/push-setup.md`.
6. **Rewards switch-on timing.** *Rec:* after L1 and L2 plus the lawyer review, VN first, with v2 4+ weeks later.
7. **Age minimum to enforce.** *Rec:* 16, matching the policy and PDPL's parental-consent threshold. Confirm with the lawyer for the US (COPPA applies under 13).

---

## Verification
- **Per item, during implementation:**
  - SQL harness suites for each migration (the `supabase/_localtest` pattern).
  - Unit and shared parity vectors run on web (`npm run test:unit`) and iOS (`xcodebuild test`).
  - Playwright for flows.
  - Reduce Motion and VoiceOver checks for every celebration.
  - VI/EN × light/dark screenshots.
- **Outcome:** F1's `admin_retention_report()` baseline per market is captured before Phase 1 ships. Each proposal's metric is compared pre and post, and stop conditions are checked weekly.

## Sources
- Peak-end meta-analysis: [GMU defense](https://psychology.gmu.edu/defenses/1259), [IDEAS/OBHDP 2022](https://ideas.repec.org/a/eee/jobhdp/v170y2022ics0749597822000334.html), [Duration neglect](https://en.wikipedia.org/wiki/Duration_neglect)
- Disney 70%: [Help Scout](https://helpscout.com/blog/disney-customer-experience), [HBS D3](https://d3.harvard.edu/platform-rctom/submission/the-happiest-place-on-earth-the-magic-recipe-behind-disney-parks-70-return-rate/)
- Netflix: [Skip Intro blog](https://about.netflix.com/news/looking-back-on-the-origin-of-skip-intro-five-years-later), [80% recommendations summary](https://illumin.usc.edu/?p=3668), [etcentric](https://www.etcentric.org/netflix-viewing-activity-is-largely-recommendation-driven/)
- No-shows: [PheedLoop #05](https://pheedloop.com/blog/event-data-lab-report-5), [PheedLoop #06](https://pheedloop.com/blog/event-data-lab-report-06)
- VN law: [PDPL / Decree 356 (Rajah & Tann)](https://www.rajahtannasia.com/?p=184709), [Allen & Gledhill](https://www.allenandgledhill.com/perspectives/articles/31074/vnkh-upcoming-changes-to-vietnam-s-personal-data-protection-regime), [Decree 91/2020 (Tilleke)](https://www.tilleke.com/insights/vietnams-new-decree-91-sets-out-stricter-anti-spam-regulations/), [Decree 128/2024](https://english.luatvietnam.vn/thuong-mai/decree-128-2024-nd-cp-on-trade-promotion-367918-d1.html), [Decree 239/2026](https://english.luatvietnam.vn/decree-no-239-2026-nd-cp-dated-june-26-2026-of-the-government-amending-and-supplementing-a-number-of-articles-of-the-governments-decree-no-81-2018-438914-doc1.html)
- US law: [FTC dark patterns report (Hunton)](https://www.huntonprivacyblog.com/2022/09/27/ftc-releases-report-on-dark-patterns/), [FTC fees rule](https://techcrunch.com/2025/05/05/ftc-bans-hidden-fees-for-live-events-and-short-term-rentals-effective-may-12/), [FTC fee FAQ](https://www.ftc.gov/node/88198), [Click-to-cancel vacated](https://www.gtlaw.com/en/insights/2025/7/eighth-circuit-vacates-ftcs-click-to-cancel-rule), [CPRA dark patterns](https://www.hunton.com/privacy-and-cybersecurity-law-blog/cppa-issues-enforcement-advisory-regarding-dark-patterns)
- Markets: [Antom Vietnam payments](https://www.antom.com/markets/vietnam), [Zalo 79.2M MAU (Tuoi Tre)](https://news.tuoitre.vn/vietnams-80-million-user-messaging-giant-zalo-puts-spotlight-on-parent-vngs-business-103251229150347905.htm), [Partiful (CNBC/NBC)](https://www.nbcnewyork.com/news/business/money-report/meet-partiful-the-gen-z-party-planning-staple-thats-taking-on-apple/6231135/)
- Apple 4.5.4: [Martech](https://martech.org/how-will-ads-in-ios-push-notifications-change-mobile-marketing/)
- Streak evidence (secondary only): [Lenny's: Duolingo streaks](https://lennysnewsletter.com/p/behind-the-product-duolingo-streaks)
- Luma post-event feedback: [Luma help](https://help.luma.com/p/collect-feedback-from-your-event-guests)
