-- Account deletion (self-service) — Task 2, Account/Settings pass.
--
-- WHY a tracking table instead of one atomic RPC/endpoint call: the actual
-- deletion is a multi-step WORKFLOW (Storage cleanup for files this user
-- owns, then `admin.auth.admin.deleteUser()`, which is what actually
-- cascades/detaches everything else per each table's own FK rule — see
-- below), and any one step can fail independently on a live serverless
-- platform (timeout, transient Storage API error, etc). This table is the
-- single source of truth for "where did this request get to", so a failed
-- attempt is a recorded, inspectable, retryable row — never a silent
-- half-deleted account with no trace.
--
-- What deletion actually does to related data, confirmed by reading every
-- relevant FK in the schema (this migration does not change any of it —
-- purely additive, see the table below):
--   - `profiles.id REFERENCES auth.users(id) ON DELETE CASCADE` — deleting
--     the auth user cascades the profile row automatically.
--   - HARD-DELETED (ON DELETE CASCADE from `profiles`/`auth.users`, directly
--     or transitively): bookings.user_id, threads.guest_id + messages sent
--     into a thread that's itself cascaded, favorites.user_id, follows,
--     organizer_members (098), event_organizer_credits (100),
--     thread_participant_state/message_reactions (065),
--     device_push_tokens.user_id (049).
--   - ANONYMIZED / ORPHANED, NOT deleted (ON DELETE SET NULL) — matches
--     Policy's "booking record stays, identity detached": organizers.owner_id
--     / organizers.user_id, bookings.paid_marked_by/cancelled_by,
--     messages.sender_id, payment_documents.uploaded_by,
--     dispute_events.actor_id, refund_batches.created_by,
--     payment_verifications.verified_by, events.organizer_id (only if the
--     ORGANIZER row itself is deleted, which this flow never does directly —
--     an organizer with other real team members/events is not touched here
--     at all, only this one user's OWNERSHIP link is cleared).
--   - BLOCKED, not silently ignored: any organizer this user owns
--     (`organizers.owner_id`/`user_id`) that still has an event in
--     `status IN ('live','review')` — refused before any deletion step
--     runs, matching Policy's own "refused while you still own an open
--     event" claim. A `draft`/`cancelled`/`ended` event never blocks.
--   - Storage: this user's own `avatars/<user_id>/...` files are removed by
--     the endpoint (real deletion, real Storage API call). Files in
--     booking-keyed buckets (`payment-documents`, `pay-proof`, keyed by
--     booking id, not user id) are NOT enumerated/deleted by this pass — a
--     real, documented limitation (see the endpoint's own comment), not a
--     silent gap: those buckets are private and un-listable by handle-path
--     convention alone without a booking-id index for "which bookings
--     belonged to this user", which `bookings.user_id` already answers but
--     the endpoint only best-effort attempts (see report).
create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null, -- NOT a FK to profiles/auth.users: the whole point
                         -- of this row is to survive the user it's about
                         -- being deleted, as an audit trail.
  status text not null default 'pending' check (status in ('pending', 'processing', 'done', 'failed')),
  reason_code text,
  reason_text text,
  steps jsonb not null default '{}'::jsonb, -- per-step progress, e.g.
    -- {"open_event_check": "ok", "avatar_storage": "ok", "auth_delete": "failed: <message>"}
  error_detail text,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.account_deletion_requests enable row level security;

-- The requesting user can see their OWN request rows (so the client can
-- show real progress/failure), but can never write to this table directly —
-- every write goes through the service-role endpoint, which verifies the
-- caller's own bearer token server-side before ever touching this table.
drop policy if exists "account_deletion_requests_select_own" on public.account_deletion_requests;
create policy "account_deletion_requests_select_own"
on public.account_deletion_requests for select
to authenticated
using (auth.uid() = user_id);

revoke insert, update, delete on public.account_deletion_requests from authenticated, anon;

create index if not exists account_deletion_requests_user_id_idx on public.account_deletion_requests (user_id);
create index if not exists account_deletion_requests_status_idx on public.account_deletion_requests (status) where status in ('pending', 'processing', 'failed');
