# Local isolated E2E harness

Runs Playwright (and the R2 media flow) against an **isolated local stack only**. Nothing here can reach the live
Supabase project, real R2/Cloudflare, real email/SMS or webhooks. It does not replace `playwright.config.js`
(which is wired to whatever `.env` points at — usually production).

## What runs where

| Piece | Where | Notes |
|---|---|---|
| Supabase (Postgres, Auth, Storage, PostgREST, Realtime, Mailpit) | Docker, project id `banbe-e2e-r2`, `127.0.0.1:55321` | Built from the repo's `supabase/migrations/*` — every migration is applied for real. Other containers are never touched. |
| S3 server standing in for R2 | Docker `versity/versitygw`, `127.0.0.1:59000` | Validates SigV4. Ephemeral storage. Fixed **local-only** credentials. |
| `/api/*` | `local-backend.mjs` on `127.0.0.1:5198` | The **real** `api/media.js` and `api/cron.js` handlers behind a tiny Vercel-style adapter (no `vercel` CLI needed). |
| "Media domain" | `local-backend.mjs` on `127.0.0.1:59010` | Models an R2 custom domain: GET/HEAD of the public bucket only, `v1/` keys only, no listing, never staging. |
| Cloudflare purge mock | `local-backend.mjs` on `127.0.0.1:59100` | Records purge requests. Checks request shape + token, **not** Cloudflare behaviour. |
| Web app | Vite on `localhost:5199` with `/api` proxied to `:5198` | `vite.local.config.mjs` (the app's own config + a proxy). |

## Quick start

```bash
scripts/e2e-local/stack.sh up            # first run pulls images; applies all migrations
scripts/e2e-local/s3.sh up               # only needed for the R2 specs
scripts/e2e-local/run.sh focused1 focused            # existing app specs (focused-specs.txt), R2 flags OFF
scripts/e2e-local/run.sh r2run r2                    # specs/*.spec.mjs: real /api/media + S3, R2 flags ON
node scripts/e2e-local/privacy-gaps.mjs after        # see "Privacy gaps" (needs the env run.sh builds, see below)
scripts/e2e-local/s3.sh down; scripts/e2e-local/stack.sh down
```

`run.sh` writes results/artifacts/auth state to `${TMPDIR:-/tmp}/banbe-e2e-out` (never into the repo).
After adding a migration run `scripts/e2e-local/stack.sh migrate`.

## Isolation (fail-closed, layered)

1. `guard.mjs` — refuses to start unless Supabase is `http://127.0.0.1:55321`, any S3/media/purge endpoint is the local one,
   R2 credentials are exactly the fixed local test values, no value mentions the live project ref or a hosted domain,
   and every email/SMS/webhook/APNs/Wallet variable is empty. Called by `run.sh`, `global-setup.mjs`, `local-backend.mjs`, `specs/_lib.mjs` and `privacy-gaps.mjs`.
2. `run.sh` blanks the integration secrets in the environment (the repo's `loadEnv.mjs` only fills variables that are *absent*, so `.env.local`'s real values can't leak in).
3. Chromium is launched with `--host-resolver-rules` mapping `*.supabase.co`, `*.r2.cloudflarestorage.com`, `*.r2.dev` and `api.cloudflare.com` to NOT_FOUND.
4. `webServer.reuseExistingServer` is `false` and ports differ from the usual dev port, so a dev server pointed at production is never reused.
5. The service-role key stays in Node (global setup, fixtures, specs). Browser tests sign in as a normal user, so RLS is exercised.

Only the fixed test accounts/rows named `e2e-*` are created; the specs delete what they create.

## Specs (`specs/`, Playwright project `r2`)

| File | What it proves |
|---|---|
| `r2-s3-client.spec.mjs` | Header-signed server-side GET/PUT/DELETE and presigned PUTs against a real SigV4 verifier; the media-domain boundary. |
| `r2-api.spec.mjs` | Real `/api/media` + `/api/cron` over HTTP: authz matrix, format/EXIF validation, variants, idempotency, privacy change, delete, sweep, rate limits, rollout flags. |
| `r2-migration.spec.mjs` | `scripts/migrate-media-to-r2.mjs`: dry-run, allowlist, copy+checksum, exclusions, resume, rollback. |
| `r2-browser.spec.mjs` | Real browser: UI upload (organizer avatar, Dashboard photo) → API → S3 → publish → render; cold/warm transfer; legacy fallback. |

`focused-specs.txt` lists the existing app specs run in project `focused` (R2 flags off). Baseline failures and fixtures: see `fixtures.mjs` if present and note 28.

## Server flags you can flip mid-test
`POST http://127.0.0.1:5198/__env` with `MEDIA_R2_UPLOADS`, `MEDIA_R2_UPLOAD_USER_IDS`, `MEDIA_R2_UPLOAD_PERCENT`, `MEDIA_UPLOADS_PER_HOUR`, `MEDIA_MAX_PENDING`, `MEDIA_DEMOTE_LEGACY_INVITE`, `MEDIA_SWEEP_STORIES` (anything else is rejected).

## Privacy gaps
`privacy-gaps.mjs before|after` demonstrates (before migration 154) and verifies the fixes for: public draft photos (listing), invite-only
events' existing public photos, expired-story cleanup, account-deletion leftovers. It needs `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
`VITE_SUPABASE_ANON_KEY` for the local stack, e.g. `eval "$(scripts/e2e-local/stack.sh env | sed -E 's/^SERVICE_ROLE_KEY=/export SUPABASE_SERVICE_ROLE_KEY=/;s/^ANON_KEY=/export VITE_SUPABASE_ANON_KEY=/')"; export SUPABASE_URL=http://127.0.0.1:55321 VITE_SUPABASE_URL=http://127.0.0.1:55321`.

## What this harness cannot prove
See "What the local emulator cannot prove" in `.claude/notes/28-r2-hybrid-media.md`.
