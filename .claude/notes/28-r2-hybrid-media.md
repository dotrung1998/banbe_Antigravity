# Supabase + Cloudflare R2 hybrid for PUBLIC media (phase one)

## Status: IMPLEMENTED LOCALLY, NOT DEPLOYED. Nothing here has touched production: no bucket/domain created, no migration applied, no objects copied. See "Deployed vs implemented" at the bottom.

## Asset classification (from the audit — by real authorization, not bucket name)
| Asset | Bucket | Class | Phase one |
|---|---|---|---|
| Event photos, event `status IN (live,ended,cancelled)` AND `visibility='public'` | event-photos | PUBLIC | R2-eligible |
| Event photos, draft/review/withdrawn event | event-photos (public bucket by accident) | RESTRICTED | stay in Supabase, never R2 |
| Event photos, `visibility='invite'` | event-photos-private | RESTRICTED | stay in Supabase |
| Organizer profile photo | organizer-photos | PUBLIC (public organizer profile) | R2-eligible |
| User avatars | avatars | public but tiny (3 objects) | not moved (no egress case) |
| Stories | stories | RESTRICTED (followers only, signed URLs) | stay |
| chat/dispute attachments, pay-proof/refund-proof/payment-documents, pay-qr/refund-qr | private | RESTRICTED | stay |

Measured (note 22, 2026-10-01): event-photos 101 files/80MB, organizer-photos 17/20MB. Per-object hit counts NOT measurable from here (hypothesis: these two public buckets + re-signed private URLs dominate the 16GB).

## Pre-existing leaks found by the audit (flag, independent of R2)
1. iOS `uploadEventPhoto` (AppState+Data.swift ~742) hard-codes the PUBLIC bucket even for invite-only events (web routes correctly).
2. Draft/review event photos are uploaded to the public bucket; the object is fetchable if the URL is known/listed (anon list policy).
3. Switching an event to invite-only never moves already-uploaded public objects.
4. `cleanup_expired_stories()` has no caller; expired story files are never removed. Account deletion only cleans `avatars`.
R2 publishing deliberately avoids all of these: drafts/invite-only never go to R2, and the sweep unpublishes anything that stops being eligible.

## Architecture
- Two R2 buckets: `banbe-media-public` (custom domain ONLY, e.g. media.<domain>; never r2.dev) and `banbe-media-staging` (private, no domain, 1-day lifecycle expiry).
- `api/media.js` (one Vercel function; Hobby cap is 12, this is the 12th) is the ONLY holder of R2 secrets. Ops: `init`, `finalize`, `delete`; cron job `media-sweep` (api/_lib/handlers/cronMediaSweep.js) unpublishes ineligible assets + cleans orphans.
- Upload: client -> `init` (server verifies JWT, account gate, ownership, eligibility, rate limit) -> short-lived presigned PUT per variant to the STAGING bucket (object-scoped key, signed content-type + content-length) -> `finalize` (server reads staged bytes, verifies magic bytes + real dimensions + size caps, strips EXIF/XMP/GPS, writes to the PUBLIC bucket under an unguessable immutable key, records `media_assets`, deletes staging). Finalize is idempotent (keyed by assetId). Bytes never pass through Supabase.
- Variants are produced by the client (canvas / UIImage) because the repo has no server image library and R2 has no free transforms: `thumb` <=320px, `card` <=800px, `full` <=1600px long edge, all the SAME format. The server does not trust them: it re-validates every variant.
- Metadata in Supabase: table `media_assets` (provider, bucket, object keys, variants, version, sha256, owner, scope, status). RLS: owner can read own rows; all writes service-role only.
- References: `event_photos.r2_ref`, `events.cover_r2_ref`, `organizers.avatar_r2_ref` (nullable). Legacy columns (`storage_path`, `cover_image`, `avatar_path`) are NEVER rewritten for migrated assets, so old app builds keep working off the Supabase copy. ONE resolver per platform prefers `r2_ref` when the read flag is on and falls back to the legacy path.
- Ref string: `r2:<scope>/<assetId>.<ext>`, scope = `ev-<eventId>` | `org-<organizerId>`. Public key of a variant = `v1/<scope>/<assetId>/<variant>.<ext>`; URL = `<MEDIA_PUBLIC_BASE_URL>/<key>`. assetId is a fresh UUID per upload, so URLs are immutable (`Cache-Control: public, max-age=31536000, immutable`); "version" is the `v1` path segment + assetId.
- Brand-new R2-only uploads (no Supabase copy) also write `storage_path = r2_ref` so rows are non-null; builds that predate the resolver cannot render those. Enable `MEDIA_R2_UPLOADS` only after the resolver builds are the minimum supported.

## HTTP contract (web + iOS)  — POST {API_BASE}/api/media, `Authorization: Bearer <Supabase access token>`, JSON
- `{op:'init', kind:'event_photo'|'organizer_avatar', eventId? | organizerId?, idempotencyKey:<uuid>, files:[{variant:'thumb'|'card'|'full', contentType:'image/jpeg'|'image/png'|'image/webp', bytes:<int>}]}`
  -> `{provider:'supabase'}` (flag off, not allow-listed, or event not eligible: use the LEGACY upload path unchanged) OR
  -> `{provider:'r2', assetId, expiresIn, uploads:[{variant, url, method:'PUT', headers:{...}}]}` (client PUTs the exact bytes with exactly those headers).
- `{op:'finalize', assetId, setCover?:bool, sortOrder?:int}` -> `{provider:'r2', assetId, ref:'r2:...'}`. For `event_photo` the server inserts the `event_photos` row itself (`storage_path=ref, r2_ref=ref`); `setCover` also sets `events.cover_r2_ref` (the client still calls its existing RPC with `p_cover_image=ref`). For `organizer_avatar` it sets `organizers.avatar_r2_ref=ref` (+`avatar_path=ref`). Calling finalize twice returns the same result.
- `{op:'delete', assetId}` -> `{ok:true}`: owner-only; deletes public R2 objects, purges the CDN, marks the asset deleted, nulls referencing `*_r2_ref`.
- Errors: `{error:'CODE'}` with 400/401/403/404/413/415/429/503. Any non-2xx or network failure on `init` => client silently uses the legacy path. A failure AFTER bytes were PUT (finalize error) => surface/retry finalize with the same assetId; do not re-upload to legacy unless user retries.
- Read config (client): `VITE_MEDIA_PUBLIC_BASE_URL` / iOS `MediaConfig.publicBaseURL`, and read flag `VITE_MEDIA_R2_READS=1` / iOS flag. Flag off or base URL empty => resolver ignores `r2_ref` entirely (instant rollback for reads).
- Variant usage: list/card/thumbnail views -> `card` (or `thumb` for <=96pt avatars); detail/gallery -> `full`. Never fetch gallery images that are not on screen.

## Rollout / rollback
1. Apply migration 153 (additive only).  2. Deploy API with all `MEDIA_*` env unset => feature fully off.  3. Ship clients (resolver is inert while flags off).  4. Set `MEDIA_R2_UPLOADS=allowlist` + `MEDIA_R2_UPLOAD_USER_IDS`, then percent.  5. Run migration script `--dry-run`, then `--apply` for a small allowlist; verify; then widen.  6. Turn `VITE_MEDIA_R2_READS` on.
Rollback: reads -> unset read flag (clients immediately use legacy Supabase copies, which are never deleted automatically). Uploads -> `MEDIA_R2_UPLOADS=off` (init returns `provider:'supabase'`). Migrated assets -> `scripts/migrate-media-to-r2.mjs --rollback` nulls `*_r2_ref` for migrated rows (legacy data untouched).

## Files (all new unless marked)
Backend: `api/media.js`, `api/_lib/{media,mediaCtx,mediaDb,r2,imageSafe}.js`, `api/_lib/handlers/cronMediaSweep.js`, `api/cron.js` (+job), `vercel.json` (+cron `media-sweep` 45 10 * * *), `supabase/migrations/20261203000153_153_r2_public_media.sql`, `scripts/migrate-media-to-r2.mjs`.
Web: `src/lib/{mediaResolver,mediaUpload,mediaUrls}.js`; `src/state/BanBeContext.jsx` and 9 screens (modified).
iOS: `Services/{MediaResolver,MediaUploader}.swift`, `BanbeAppTests/MediaResolverTests.swift`; AppState+Data/Profile/Surveys, several views (modified).
Tests: `tests/unit/{media-api,imageSafe,mediaResolver}.test.mjs`.

## Security behaviour (each covered by tests/unit/media-api.test.mjs unless noted)
- JWT validated server-side (`auth.getUser`) + `account_gate_ok`; user id comes only from the JWT. Unauthenticated/garbage token -> 401.
- Cross-account: non-owner init -> 403 (identical for missing event); finalize/delete of another user's asset -> 404 (identical to missing).
- Draft / review / withdrawn / invite-only events: `init` returns `provider:'supabase'` — never R2. Privacy change between init and finalize -> 409, nothing published.
- Declared MIME never trusted: real format from magic bytes, real dimensions from the container, per-variant byte + long-edge caps, one format across variants, animated files rejected, truncated files rejected. Oversize/spoofed -> 413/415/422, nothing published, asset marked failed.
- EXIF/XMP/GPS/text chunks stripped losslessly (JPEG APPn/COM, PNG ancillary chunks, WebP EXIF/XMP) — tested, but ONLY on hand-built images; run a real phone photo through once (check #1 below).
- Unguessable keys (`v1/<scope>/<uuid>/<variant>.<ext>`); presigned PUTs are object-scoped to `staging/<assetId>/<variant>`, 5-minute expiry, with content-type + content-length signed. Clients cannot overwrite existing public keys (they never get a signature for them). Presign signing is verified against the official AWS SigV4 vector; the header-signed server requests (GET/PUT/DELETE) share the same key derivation but are NOT independently verified against real R2.
- Idempotent: same `idempotencyKey` -> same asset; finalize twice -> same result, one row.
- Rate limits: `MEDIA_UPLOADS_PER_HOUR` (60) + `MEDIA_MAX_PENDING` (24) per user, DB-backed (works across serverless instances).
- Withdrawal: `delete` (owner/host/admin), `reconcile` (host, immediate after visibility/withdraw), daily `media-sweep` (any event no longer public, event deleted, stale pending, retry of half-finished deletes). Public objects deleted + Cloudflare purge-by-URL; R2-only photos are first moved to `event-photos-private` so the host does not lose them. Not possible: recalling copies already downloaded by others.
- `*_r2_ref` columns are server-managed: DB trigger rejects client writes and requires the ref scope to match the row (migration 153; NOT executed anywhere, so untested against a real Postgres — verify after applying: an authenticated client `UPDATE event_photos SET r2_ref='...'` must fail with 42501).
- Stories, chat, disputes, payments, refunds, QR codes, invite-only/draft photos: untouched, still private Supabase with existing RLS. The 4 pre-existing leaks above are NOT fixed by this work except the iOS invite-only upload routing.

## Cache behaviour
- Public R2 variants: `Cache-Control: public, max-age=31536000, immutable`, unique URL per upload => cache keys are stable (iOS `StorageImageCache`/`PhotoLoader`, browser HTTP cache). Lists use `card`/`thumb` (<=800px / <=320px), detail uses `full` (<=1600px): lists no longer download originals once an asset is on R2.
- Private (still Supabase) caches: unchanged from note 22 — cleared on sign-out. Service worker (public/sw.js) does not cache the R2 origin (R2 responses are already immutable-cached by the browser).

## Required configuration (NOT done — needs the account owner; paid dependencies marked)
1. Cloudflare account with R2 enabled (R2 requires a payment method on file; free allowance 10GB storage / 1M Class A / 10M Class B per month, egress to the internet free). A domain whose DNS is on Cloudflare (needed for the custom domain; the Cloudflare Free plan is enough for CDN + cache purge by URL).
2. Create buckets `banbe-media-public`, `banbe-media-staging`. Staging: no public access, no domain, lifecycle rule "delete objects older than 1 day", CORS: AllowedOrigins = the production web origin(s) only, AllowedMethods PUT, AllowedHeaders content-type, content-length, MaxAge 3600. (CORS is browser hygiene, not authorization — the presigned signature is.) Public bucket: attach custom domain `media.<yourdomain>`; leave r2.dev DISABLED; Cache Rule: cache everything on that hostname, respect origin headers.
3. R2 API token (S3 credentials): Object Read & Write, scoped to just those two buckets. Zone token: Cache Purge on the media zone only.
4. Vercel env: the variables in `.env.example` (R2_*, MEDIA_PUBLIC_BASE_URL, CLOUDFLARE_*, CRON_SECRET, MEDIA_R2_UPLOADS=off initially). Web build env: `VITE_MEDIA_PUBLIC_BASE_URL`, `VITE_MEDIA_R2_READS`. iOS: `MEDIA_PUBLIC_BASE_URL`, `MEDIA_R2_READS` Info.plist keys (empty by default).
5. `supabase db push` for migration 153 (additive). The clients tolerate the columns being absent, so ordering is safe either way.
6. The new cron entry in vercel.json adds a 4th cron job: confirm the Vercel plan allows it (Hobby allows only 2 cron jobs and 12 functions; this repo already has 3 crons and exactly 12 functions, so it is presumably not on Hobby, but I could not verify).

## Cost drivers
R2: storage (GB-month) + Class A ops (PUT/LIST: 3 variants x uploads + staging puts/deletes) + Class B ops (GET; mostly absorbed by CDN cache) — egress free. Cloudflare: CDN on Free plan; purge API is free. Vercel: one extra function invocation per upload (init+finalize ≈ 2) and a daily cron; server-side reads of ≤3 small images per finalize. Supabase: no Storage egress for migrated/new public media; DB writes for `media_assets`. Image processing: client-side canvas/UIImage (no paid transform service).

## Measurement
NOT MEASURED. No Cloudflare account/domain exists, nothing was deployed, and per-object hit counts were never available (note 22). Expected (estimate only): event-photos/organizer-photos average 0.8-1.2MB/original; lists switching to <=800px variants (~100-250KB) would cut per-view bytes for those surfaces by roughly 70-85%, and R2 egress is free. Real before/after numbers need: Supabase Dashboard egress for the cycle after rollout, Cloudflare analytics for the media hostname, and Safari/Chrome devtools (cold vs warm) on Home / Event detail / Organizer profile.

## Deployed vs implemented
IMPLEMENTED LOCALLY: everything above. DEPLOYED/EXECUTED: nothing — no migration applied, no bucket/domain/token created, no migration script run (dry-run not run either: needs service-role env), no commit/push.
