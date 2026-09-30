# Strict invite-only events + interest surveys — domain note

## Status: PARTIALLY WORKING (web only). Read this before touching invite-only events, event photo privacy, or surveys again.

Slice A (invite-only events) backend is real and tested; web UI has the
creation toggle only, no host invite-management UI yet. Slices B/C/D
(interest surveys, candidate generation, stories/badges integration) are
**not started**.

## What's real and verified

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
- `claim_seats` (007) redefined with one added check: invite-only events
  require a non-revoked/non-expired invite row for the caller, checked
  server-side — direct RPC calls cannot bypass it. The organizer owner can
  always book their own event.
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
  (it never had before — the only discovery query with this gap).
- The static demo catalogue's `banrieng` entry (`src/data/events.js`,
  iOS `Resources/events.json`) is **removed** — it was gated only by a
  hardcoded client-side map plus an `s.invited` array that was never
  actually populated (dead code, always `[]`), so any signed-in user
  navigating to it directly got full "private" demo content for free. The
  real seeded `events` row with the same id (migration 020) now goes
  through the real RLS/`event_invites`/`claim_seats` path this migration
  added — no separate demo auth model.
- `CreateEvent.jsx` has a Public/Invite-only toggle (`s.createVisibility`,
  persisted via the new `set_event_visibility` RPC, deliberately NOT a new
  param on the already-large `create_event_draft`/`resubmit_event_for_
  review` — same pattern as the existing `set_event_keywords`) and shows
  it on the Review step.

## Verification performed

No local/staging Supabase instance exists in this environment (no
`supabase` CLI, no running project). Verified instead against a throwaway
local Postgres container running a minimal stub of the relevant schema
(events/organizers/bookings/threads/profiles/event_photos/auth.users/
storage.buckets+objects) plus this migration applied on top — NOT a
substitute for a real `supabase db push` + `supabase migration list`
check, which still needs to happen before this is live. Confirmed:
- Non-invitee: 0 rows on direct `SELECT events`, `claim_seats` raises
  `INVITE_REQUIRED`.
- Invited (pending, no explicit accept) user: sees the event, books
  successfully.
- Host revokes → invitee's next `claim_seats` call fails
  (`INVITE_REQUIRED`); the invitee's EARLIER booking is untouched (no
  silent cancellation/financial-state change).
- Email-only invite: wrong token → `INVITE_NOT_FOUND`; correct token from
  the wrong identity → `IDENTITY_MISMATCH`; correct token from the actual
  invited email → binds `invited_user_id`, succeeds.
- `create_event_invites` on a `visibility='public'` event →
  `EVENT_NOT_INVITE_ONLY`.
- `event_photos` row visibility follows the same rules (stranger: 0 rows,
  invitee: sees them).
- `set_event_visibility` rejects a non-owner (`NOT_AUTHORIZED`) and
  correctly inserts a `notifications` row for an existing-user invite.
- `npx vite build` — clean, no errors, after all client-side changes.

**Not run**: `xcodebuild` (no iOS changes were made this pass — see Not
done, below). No real Supabase project was touched; no data was written
to any deployed database.

## Not done this pass (explicitly out of scope / deferred)

- **Host invite-management UI** (send invites, see pending/accepted/
  revoked list, revoke button) — the RPCs exist and are tested, but there
  is no screen calling them yet. Planned location: a panel in
  `CreateEvent.jsx`'s edit mode when `createVisibility === 'invite'`, or a
  new Dashboard sub-view.
- **Email delivery for email-only invites** — `create_event_invites`
  returns the plaintext token, but nothing calls `/api/notify` (or
  `src/lib/sendEmail.js`) to actually send it yet. Needs a new
  `event_invite` case in `api/notify.js` (same Bearer-token/service-role
  pattern as its existing cases) plus a redemption link built from the
  token (`/?invite=<token>` query-param convention, since this is a
  path-less Vite SPA — see Slice B's own routing note below).
- **EventDetail accept/decline banner** — an invitee currently lands on
  the event (RLS-permitted) but there's no UI surfacing "you're invited,
  accept/decline" or handling the `INVITE_REQUIRED` error from
  `claim_seats` with a clear message instead of the generic reserve-error
  path.
- **iOS** — zero iOS changes this pass. `EventDetailView.swift`'s existing
  `inviteOnly` check (driven by `event.visibility`) already reads real
  data once the demo catalogue fix above ships (its own bundled
  `events.json` no longer has a `banrieng` row), but iOS has no invite
  RPC calls, no accept/decline, no private-bucket-aware photo loading.
  `AppState.swift:1635`/`:1757` (`!e.inviteOnly` filters) were not audited
  for whether they need the same MapExplore-style visibility fix.
- **Organizer public-profile stats leak (found, not fixed)**: `get_
  organizer_profile` (095) and the organizer public team page (100) count
  `event_count`/`hosting_since_year` over `status IN ('live','ended')`
  with **no visibility filter** — an invite-only event's existence
  contributes to a PUBLIC organizer page's numbers (count, "hosting
  since" year) even though the event row itself is now correctly hidden.
  Not fixed this pass: both are large (100+ line) `SECURITY DEFINER`
  functions already redefined multiple times across later migrations
  (096, 097, 102 all touch `get_public_profile`'s mirrored organizer sub-
  object), and this environment has no way to test a full redefinition of
  them against the real schema (the local stub used above doesn't model
  `follows`/`event_credits`/etc.) — retyping them by hand under time
  pressure without a real test was judged riskier than leaving a
  documented, lower-severity leak (aggregate counts/year, not event
  content) for a follow-up pass with proper testing.
- **Organizer-team invites vs event invites**: deliberately kept separate
  — `event_invites` (this migration) is attendee-level event access;
  `organizer_members`/`invite_organizer_member` (098) is organizer-team
  membership. No shared table, no shared RPC, per the task's own
  instruction not to confuse the two.
- **Slices B/C/D (surveys, candidates, stories/badges)** — not started.
  See the audit dependency map given to the user for what exists vs is
  missing there (no survey/poll table anywhere; no client-side router, so
  `/surveys/:publicId` must be a query-param convention on this Vite SPA,
  not a real path route; `pg_cron` is the reusable pattern for deadline
  closure).

## Deployment status

**Nothing in this migration has been applied to any database.** No
`supabase` CLI is installed in this environment and no local/staging
Supabase project is running, so `supabase db push`/`supabase migration
list` could not be run here. Before this is live:
1. Run `supabase migration list` against the real project to confirm
   `20261025000113` isn't already partially applied some other way.
2. `supabase db push` (or equivalent) to apply it — this is a schema
   change (new table, new bucket, redefined `claim_seats`) and should go
   through whatever review/approval this project normally requires for a
   production migration.
3. Until applied, `visibility='invite'` on the `events` table still exists
   but is completely unenforced in production (the exact pre-existing gap
   this migration closes) — do not rely on any invite-only behavior in
   production before confirming the migration is live.
