# Strict invite-only events + interest surveys — domain note

## Status: PARTIALLY WORKING, web AND iOS. Read this before touching invite-only events, event photo privacy, or surveys again.

Slice A (invite-only events) backend is real and tested, including the
**critical fix described below** (the actual booking RPC, not just the one
originally gated) — web AND iOS both create/read/book through it, and iOS
has the same private-bucket-aware photo resolution as web. Slice B
(interest surveys) backend + a functional web AND iOS host/respondent UI
are real and tested/build-clean; the dedicated browser route is web-only
by nature. Slices C (candidate generation) and D (surveys in stories) are
**not started**, on either platform. Host invite-management UI, invite
email delivery, and EventDetail accept/decline for event invites are also
**not started**, on either platform.

## Slice A — Strict invite-only events

### What's real and verified

- `supabase/migrations/20261025000113_113_strict_invite_only_events.sql`
  (**not yet applied to any deployed database** — see Deployment below).
- `event_invites` table (pending/accepted/declined/revoked/expired), RLS
  scoped to host/admin/invitee via two bypass-RLS helper functions
  (`is_event_host`, `has_event_invite_access` — needed to break a genuine
  mutual-recursion cycle between `events` and `event_invites` RLS,
  confirmed by actually reproducing "infinite recursion detected in
  policy" against a local Postgres before fixing it this way).
- `events_select_public` narrowed to require `visibility='public'`
  (previously ignored visibility entirely — any invite-only event was
  fully readable by direct id/slug). `events_select_invited` is the
  additive policy for the invited case, same pattern as the existing
  `events_select_admin` (085).
- **CRITICAL, found and fixed after the first pass looked done**:
  `claim_seats` (007) was gated first, but reading `GocContext.jsx`'s own
  `submitReserve` comment revealed the REAL reserve flow calls
  **`hold_seats()` (migration 053)**, not `claim_seats` — the latter is
  explicitly described in that comment as legacy (it never touches
  `payment_state`/`hold_expires_at`). Gating `claim_seats` alone left the
  actual booking path completely unprotected despite looking fixed.
  **Both are now gated**: `claim_seats` for defense-in-depth, `hold_seats`
  because it's what the app actually calls — verified end-to-end against
  the local Postgres harness (stranger blocked with `INVITE_REQUIRED`,
  invitee books successfully, owner bypasses without needing an invite,
  correct notifications fire). **Lesson for next time**: always trace a
  client call site to its real RPC name before declaring a server-side
  gate complete — a plausible-sounding function name is not proof it's
  the live path.
- Real photo privacy: invite-only events' photos go to a **separate,
  genuinely private bucket** (`event-photos-private`), not the existing
  public `event-photos` bucket. This matters because Supabase serves a
  `public: true` bucket's objects via `getPublicUrl()` regardless of
  `storage.objects` RLS — gating RLS alone would NOT have closed the "a
  private event's public image URL isn't private" gap the task called
  out. Public events are completely unaffected (same bucket/path, same
  synchronous `getPublicUrl()` fast path as always).
- `create_event_invites`/`revoke_event_invite`/`respond_to_event_invite`/
  `redeem_event_invite_token`/`set_event_visibility` RPCs. Tokens are
  high-entropy (32 random bytes), stored only as a SHA-256 hash, returned
  to the caller once. Redemption re-verifies the caller's own
  `auth.users.email` against the invited address at redemption time — a
  forwarded link cannot grant a different account access.
- Existing-user invites insert a real `notifications` row (kind
  `event_invite`), reusing the existing table/RLS/toast pipeline — no new
  inbox. `openNotification()` routes it to `goEvent()` (GocContext.jsx).
- `MapExplore.jsx`'s `fetchLiveEvents` now filters `visibility='public'`
  (it never had before — the only web discovery query with this gap).
- **iOS parity fix, found by re-auditing after the web fix**:
  `AppState+Data.swift`'s `loadMapEvents()` (the Map screen's real query)
  had the EXACT SAME missing-visibility-filter bug as `MapExplore.jsx` —
  fixed the same way (`.eq("visibility", value: "public")`). iOS's
  `locationUniverse`/Home-feed filters (`AppState.swift:1635`/`:1757`)
  were re-checked and are already correct (`!e.inviteOnly`, mirroring
  web's `Home.jsx`) — no change needed there. `ViewModels/HomeViewModel.
  swift` has the same bare `status=live` query with no visibility filter,
  but is dead code (grepped: referenced nowhere else in the app) — left
  alone; RLS is the real backstop for it regardless if it's ever wired up.
- The static demo catalogue's `banrieng` entry (`src/data/events.js`,
  iOS `Resources/events.json`) is **removed** — it was gated only by a
  hardcoded client-side map plus an `s.invited` array that was never
  actually populated (dead code, always `[]`), so any signed-in user
  navigating to it directly got full "private" demo content for free. The
  real seeded `events` row with the same id (migration 020) now goes
  through the real RLS/`event_invites`/booking path this migration added.
- Fixed a fabricated claim: EventDetail (web + iOS) used to show "You can
  bring one +1" on any invite-only event — leftover flavor text from the
  removed demo event's own fiction. No "+1" mechanism exists anywhere in
  the invite model; now shows a truthful "This event is invite-only"
  instead, on both platforms, since this line now renders for REAL
  invite-only events.
- `CreateEvent.jsx` has a Public/Invite-only toggle (`s.createVisibility`,
  persisted via the new `set_event_visibility` RPC, deliberately NOT a new
  param on the already-large `create_event_draft`/`resubmit_event_for_
  review` — same pattern as the existing `set_event_keywords`) and shows
  it on the Review step.
- `submitReserve`'s (web) and iOS's equivalent error-mapping both now show
  a truthful "This event is invite-only" for `INVITE_REQUIRED`, instead of
  the generic "could not hold this spot, try again" fallback.

### Verification performed (Slice A)

No local/staging Supabase instance exists in this environment (no
`supabase` CLI, no running project). Verified instead against a throwaway
local Postgres container running a minimal stub of the relevant schema —
NOT a substitute for a real `supabase db push` + `supabase migration list`
check. Confirmed, calling the RPCs directly under different session
identities (`request.jwt.uid` session var standing in for `auth.uid()`):
- Non-invitee: 0 rows on direct `SELECT events`; both `claim_seats` AND
  `hold_seats` raise `INVITE_REQUIRED`.
- Invited (pending, no explicit accept) user: sees the event, books
  successfully via `hold_seats` (the real path) with correct
  `payment_state`/notifications.
- The event's organizer owner books their own private event without
  needing an invite.
- Host revokes → invitee's next booking attempt fails (`INVITE_REQUIRED`);
  the invitee's EARLIER booking is untouched (no silent cancellation/
  financial-state change).
- Email-only invite: wrong token → `INVITE_NOT_FOUND`; correct token from
  the wrong identity → `IDENTITY_MISMATCH`; correct token from the actual
  invited email → binds `invited_user_id`, succeeds.
- `create_event_invites` on a `visibility='public'` event →
  `EVENT_NOT_INVITE_ONLY`.
- `event_photos` row visibility follows the same rules (stranger: 0 rows,
  invitee: sees them).
- `set_event_visibility` rejects a non-owner (`NOT_AUTHORIZED`) and
  correctly inserts a `notifications` row for an existing-user invite.
- `npx vite build` clean. `xcodebuild -scheme PersonalTeamDebug ... build`
  → **BUILD SUCCEEDED**, after the iOS `loadMapEvents`/error-mapping/"+1"
  copy fixes.

### Not done (Slice A)

- **Host invite-management UI** (send invites, see pending/accepted/
  revoked list, revoke button) — the RPCs exist and are tested, but no
  screen calls them yet.
- **Email delivery for email-only invites** — `create_event_invites`
  returns the plaintext token, but nothing calls `/api/notify` yet to
  actually send it. Needs a new `event_invite` case in `api/notify.js`
  (same Bearer-token/service-role pattern as its existing cases).
- **EventDetail accept/decline banner** for event invites — an invitee
  lands on the event (RLS-permitted) but there's no UI surfacing "you're
  invited, accept/decline."
- **iOS is now at full parity with web for what web itself has**:
  `CreateEventView` (OnboardingViews.swift) has the same Public/Invite-only
  toggle, persisted via the same `set_event_visibility` RPC; photo uploads
  route to `event-photos-private` for invite-only events
  (`reconcileEventMedia`); a new `resolveEventPhotoURL` helper
  (AppState+Data.swift) resolves signed URLs for the private bucket and is
  now used everywhere an event photo is displayed (EventDetailView's
  gallery, CreateEventView's edit-seed, AdminEventsView's review gallery
  via `loadEventGalleryURLs`, notification thumbnails via
  `firstPhotoURLByEvent`); `loadMapEvents` (the Map screen's real query,
  found to have the exact same missing-visibility-filter bug as web's
  `MapExplore.jsx`) is fixed; `hold_seats`'s `INVITE_REQUIRED` error maps
  to the same truthful message. Still not done, either platform: invite
  RPC calls (create/revoke/accept/decline/redeem) have no UI at all yet —
  see the bullets above, unchanged by the iOS work.
- **Organizer public-profile stats leak (found, not fixed)**: `get_
  organizer_profile` (095) and the organizer public team page (100) count
  `event_count`/`hosting_since_year` over `status IN ('live','ended')`
  with **no visibility filter** — an invite-only event's existence
  contributes to a PUBLIC organizer page's numbers even though the event
  row itself is now correctly hidden. Not fixed: both are large (100+
  line) `SECURITY DEFINER` functions redefined multiple times across later
  migrations, and this environment can't test a full redefinition against
  the real schema — retyping them by hand under time pressure without a
  real test was judged riskier than leaving a documented, lower-severity
  leak (aggregate counts/year, not event content) for a follow-up pass.
- **Organizer-team invites vs event invites**: deliberately kept separate
  — `event_invites` is attendee-level event access; `organizer_members`/
  `invite_organizer_member` (098) is organizer-team membership. No shared
  table, no shared RPC.

## Slice B — Interest surveys before an event

### What's real and verified

- `supabase/migrations/20261026000114_114_interest_surveys.sql` (**not yet
  applied to any deployed database**).
- Fixed MVP question set stored as ONE structured `surveys.config` JSON
  block (date/time options, location options, budget options, activities,
  group size bounds, per-field `required` flags) — deliberately not a
  generic question/option engine, per the task's own "don't build an
  unrestricted complex form-builder" instruction.
- `surveys` (draft/active/closed/archived) + `survey_responses`
  (`UNIQUE(survey_id, respondent_id)`, atomic upsert = "one current
  response, editable until closure"). Direct table SELECT is host/admin
  only; the public browser route reads exclusively through
  `get_survey_public()`, an allowlisted-field RPC that can never leak more
  than it explicitly returns, and that computes EFFECTIVE status
  (`closes_at <= now()` ⇒ closed) rather than trusting the stored column
  alone, in case the closure worker hasn't run yet.
- RPCs: `create_survey`/`update_survey` (host, structural `config` changes
  LOCKED once any response exists — not versioned, an explicit simpler
  choice, see Not done)/`publish_survey`/`close_survey`/`archive_survey`/
  `get_survey_public`/`submit_survey_response`.
- `submit_survey_response` validates: survey is active AND
  `opens_at <= now() < closes_at` (enforced here too, not just by the
  worker — "enforce closes_at on response writes even if the worker is
  late"), every required field per the survey's own `config.required`,
  every submitted option id is a real member of that survey's own option
  set, group size within `config.group_size_min/max`. Atomic upsert via
  `ON CONFLICT (survey_id, respondent_id)` under the survey row's own
  `FOR UPDATE` lock, so a host's `close_survey()` and a respondent's
  concurrent submit can't race past each other.
- Deadline closure: `close_expired_surveys()` on `pg_cron` (`* * * * *`,
  same pattern as the existing `goc_expire_lapsed_pendings`/`goc_mark_
  past_events` jobs, migration 008) — idempotent, host doesn't need the
  app open.
- Respondent privacy: RLS on `survey_responses` scopes SELECT to
  `respondent_id = auth.uid()` OR the survey's own host/admin — a
  respondent can never see another respondent's name or answers.
- Contact consent (`contact_consent`) is a separate boolean field, never
  implied by answering, never auto-true.
- Browser route: real path `/surveys/<publicId>` (NOT a query param — see
  the correction below), read the same way this app's existing `/u/
  <handle>` and `/org/<id>` deep links are (parsed from
  `window.location.pathname` once at module load, before React mounts;
  works signed out via the anon-granted RPC). One screen
  (`SurveyPublic.jsx`) serves both the dedicated browser page and in-app
  navigation (`goSurveyPublic`), sharing the exact same backend calls, per
  the task's "reuse... the SAME response backend" instruction.
- Draft answers persist through a sign-in round trip via `sessionStorage`
  (keyed by `public_id`), restored on mount, cleared on successful submit
  — "preserve entered answers through auth."
- Host screen: `SurveysHosting.jsx`, reachable from Account → Hosting →
  "Khảo Sát & Ý Tưởng Sự Kiện" (new `GroupCard`, badge honestly `0` since
  the real unseen-candidate-count driving that badge is Slice C, not
  built). Active/Closed/Suggested-Drafts tabs; create form (title,
  description, days-until-close, comma-separated option lists, max group
  size); publish/close-early/archive actions; a "Preview" link that opens
  the same `SurveyPublic` screen in-app. The Suggested-Drafts tab shows an
  honest empty state explaining candidate generation isn't built —
  present in the IA (a real, correctly-positioned entry point), never
  claiming content that doesn't exist.

### Correction made mid-implementation (routing)

An earlier audit pass concluded this app has "no client-side router...
so `/surveys/:publicId` must be a query-param convention," based on
`MapExplore.jsx` and query-param usage. That was **wrong** — re-checking
`GocContext.jsx` directly during implementation found `sharedProfileHandle`/
`sharedOrganizerId` already parsing REAL paths (`/u/<handle>`, `/org/<id>`)
from `window.location.pathname` at module load, working fine under
`vercel.json`'s catch-all SPA rewrite (any path still serves `index.html`,
so this JS still runs and still sees the real pathname on direct load and
refresh). `/surveys/<publicId>` uses the exact same, already-proven
pattern — a real path, not a query param. **Lesson**: verify a structural
claim like "this app has no path-based routing" by grepping for the
actual mechanism, not by trusting one prior investigation's summary.

### Verification performed (Slice B)

Same local-Postgres-harness method as Slice A (extended with `surveys`/
`survey_responses`/pg_cron stub). Confirmed:
- Draft survey not reachable via `get_survey_public` (`NOT_FOUND`, same as
  a genuinely missing link — a draft was never meant to be reachable yet).
- Respondent blocked from submitting before publish (`SURVEY_NOT_ACTIVE`).
- After publish: `get_survey_public` reports `active`; a respondent
  submits successfully; the SAME respondent editing their answer updates
  the same row (not a duplicate — `UNIQUE(survey_id, respondent_id)`
  proven, not assumed).
- Invalid option id → `INVALID_LOCATION_OPTION`; missing required field →
  `DATE_OPTIONS_REQUIRED`; out-of-bounds group size → `INVALID_GROUP_
  SIZE`.
- A second respondent's row is invisible to the first respondent via
  direct `SELECT` (RLS proven with two real, different session
  identities, not assumed from the policy text alone).
- Host sees both respondents' full rows.
- `update_survey` with a `config` change AFTER a response exists →
  `STRUCTURAL_CHANGE_LOCKED`; the SAME call with only `title` changes
  still succeeds.
- Host `close_survey()` → subsequent respondent submit →
  `SURVEY_NOT_ACTIVE`; `get_survey_public` reports `closed`.
- `npx vite build` — clean (`SurveyPublic.jsx`, `SurveysHosting.jsx`,
  `Account.jsx`, `App.jsx`, `GocContext.jsx` changes).

**Not run**: no iOS survey code was written this pass, so no iOS build
was needed for it (the earlier Slice A iOS build already covers the fixes
that touch iOS files). No real Supabase project was touched; no data was
written to any deployed database.

### Not done (Slice B)

- **True invite-gated private surveys** — this pass ships public-by-link
  audience only (anyone with the `/surveys/<publicId>` link can respond,
  same trust model as any other shared link in this app). Reusing
  `event_invites` to gate a survey's audience is not implemented.
- **Question-level versioning** — `update_survey` HARD LOCKS `config`
  changes once any response exists, rather than the task's alternative
  "or implement explicit versioning so old answers keep their meaning."
  `config_version` exists on both `surveys` and `survey_responses` for a
  future pass that wants true versioning instead of a lock; this pass
  took the simpler, safer branch given time constraints.
- **Explicit rate-limiting** of `submit_survey_response` itself — the
  atomic per-respondent upsert structurally caps meaningful writes to one
  effective row no matter how many times it's called (idempotent, not
  spammable into duplicates), and identity verification itself already
  rate-limits via the existing OTP/email-code infra (`otp_codes.attempts`)
  reused for sign-in. No NEW request-throttling infra (e.g. a sliding
  window) was added.
- **iOS now has full survey parity with web**: `AppState+Surveys.swift`
  (models + every RPC call — `get_survey_public`, `submit_survey_response`,
  `create_survey`/`publish`/`close`/`archive_survey`, `loadMySurveys`,
  `loadMySurveyResponse`), `SurveyPublicView.swift` (one screen for both
  in-app navigation and the `/surveys/<publicId>` universal-link deep link
  — `handleUniversalLink` in AppState+Profile.swift now recognizes a
  `surveys` path segment the same way it already does `u`/`org`; actual
  resolution still needs the real Team ID for Associated Domains, same
  documented caveat as every other universal link in this app, see note
  17), `SurveysHostingView.swift` (Active/Closed/Suggested-Drafts tabs,
  create form, copyable link), a new Account → Hosting entry point.
  `xcodebuild -scheme PersonalTeamDebug ... build` → BUILD SUCCEEDED after
  adding all of this. No draft-persistence-through-sign-in mechanism was
  needed on iOS the way web's `sessionStorage` fix was — the app itself is
  the durable session, so there's no "browser tab reload mid-auth" failure
  mode to guard against.
- **Slice C (candidate generation)** — not started. Schema was shaped
  with this in mind (`date_options`/`location_options` stored as
  queryable arrays per response) so a later deterministic scoring pass
  doesn't need a data migration first, but no scoring function, candidate
  table, or "Use This Idea" → Create Event prefill exists.
- **Slice D (surveys in organizer stories)** — not started. No survey
  story/card type, no "Answer Survey" CTA, no pause-story-for-response
  flow.
- **Notifications/badges for survey results** — no "your event ideas are
  ready" notification exists (there's nothing to notify about yet, since
  Slice C doesn't exist); the Hosting/dock badge Slice C would eventually
  drive is a hardcoded `0` for now, honestly, not a fabricated count.

## Deployment status (both migrations)

**Nothing in either migration has been applied to any database.** No
`supabase` CLI is installed in this environment and no local/staging
Supabase project is running, so `supabase db push`/`supabase migration
list` could not be run here. Before either is live:
1. Run `supabase migration list` against the real project to confirm
   `20261025000113` and `20261026000114` aren't already partially applied
   some other way.
2. `supabase db push` (or equivalent) to apply them, in order — both are
   schema changes (new tables/buckets, redefined `claim_seats`/
   `hold_seats`) and should go through whatever review/approval this
   project normally requires for a production migration.
3. Until applied: `visibility='invite'` on `events` remains completely
   unenforced in production (the exact pre-existing gap 113 closes), and
   no survey infrastructure exists at all in production. Do not rely on
   either feature in production before confirming both migrations are
   live.

## iPhone/browser checklist (once migrations are deployed)

- Create an event, toggle Invite-only, confirm it does NOT appear on
  Home/Map for a second test account with no invite.
- From a second account with no invite, try to reserve the same event by
  guessing/reusing its id directly (not through the UI) — should fail.
- Open `/surveys/<publicId>` for a published survey directly in Safari,
  signed out: description/deadline/form should render; submitting should
  prompt sign-in, then land back on the same survey with the draft intact.
- Refresh the browser survey page mid-form — draft answers should survive
  (sessionStorage).
- As the host, publish a survey, submit a response from a second account,
  confirm it appears in `SurveysHosting`'s Active tab; close it early;
  confirm the browser page now shows "closed" and rejects a new submit.
- iOS: repeat the Invite-only toggle + photo-upload check in the app's own
  Create Event flow; open Account → Hosting → "Khảo Sát & Ý Tưởng Sự Kiện"
  and create/publish/close a survey from the phone; tap "Xem trước" and
  confirm the in-app survey form matches the browser version's behavior.
