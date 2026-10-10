# LOCAL TEST HARNESS — NOT A MIGRATION, NEVER DEPLOY

Nothing in this directory is part of the migration chain. `supabase db push`
reads `supabase/migrations/*.sql` only, and none of these files live there or
match that path.

## What this is

A throwaway Postgres harness used to actually **execute** migration 130 (and
every migration before it) against a real database, instead of only reading it.

```bash
docker run --name banbe-pg \
  -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=postgres \
  -e JWT_SECRET=super-secret-jwt-token-with-at-least-32-characters-long \
  -p 54322:5432 -d supabase/postgres:17.6.1.166

./supabase/_localtest/run.sh
```

`run.sh` resets the schema, applies **all 125 migrations in order** (aborting on
the first error), seeds a two-party scenario, raises the refund dispute through
the real `dispute_refund()` RPC, then runs 51 assertions and prints
`RESULT: ALL PASS`.

Use the `supabase/postgres` image, not plain `postgres`: the migrations need
`auth.uid()`, `pg_cron`, and the `storage` schema.

## Files

| File | Purpose |
|---|---|
| `00_bootstrap_storage.sql` | Recreates the `storage` schema and the `auth.users` / `auth.sessions` columns that the Supabase storage+auth services normally provide. |
| `01_seed.sql` | Goer, host, stranger, admin; two events; two bookings; two conversations; one PAYMENT dispute decoy. |
| `02_dispute.sql` | Raises the refund dispute as the goer via `dispute_refund()`. |
| `03_assert.sql` | The 51 assertions (location, authorization, close, idempotency, retention, transcript, list shape). |
| `run.sh` | Orchestrates the whole thing from a clean database. |

## Two traps worth remembering

- Seed the claim as **`host_marked_sent`**, never `disputed`. `dispute_refund()`
  short-circuits with `already=true` when the claim is already disputed and
  never creates the thread, so a `disputed` seed silently tests nothing.
- `03_assert.sql` closes the dispute as part of its own sequence, so it is
  **not** re-runnable against the same database. Re-run `run.sh`, which resets
  first.

## What it found

`CREATE OR REPLACE FUNCTION` cannot change a function's return type, so
redefining `get_my_dispute_chats()` — which is `RETURNS TABLE(...)` — with four
added columns failed outright with `cannot change return type of existing
function`. Only executing the chain caught it; it needed `DROP FUNCTION` +
`CREATE FUNCTION`.
