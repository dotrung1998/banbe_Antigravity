# Supabase bandwidth/egress optimization pass (2026-10-01)

## Status: PARTIALLY DONE this pass — client-side fixes shipped and verified (web build + iOS compile, both green); existing-media backfill and cache-control retrofit on already-uploaded objects are DRY-RUN ONLY, awaiting approval. Read this before touching image upload/cache code again.

## Why this pass happened
Project `ukchdgdnwytretvqjjqu` ("Bolt diy banbe") was reported over its free-tier **cached egress** (9.631/5GB — the uncached figure, 2.229/5GB, was still under). Database (0.046/0.5GB) and Storage (0.071/1GB, per the dashboard snapshot given at the start of this pass — see the measured-vs-dashboard discrepancy note below) were nowhere near their caps: this is a bandwidth problem, not a storage/DB problem, and already-served egress cannot be recovered after the fact — only future growth is actionable.

## Measured facts (read-only, this session — service-role Storage API object listing, no downloads; see method below)
Ran a scratchpad Python script against the Storage REST API (`POST /storage/v1/object/list/{bucket}`, recursive by prefix) using the service-role key already in `.env.local` — metadata only (`size`, `mimetype`), zero object bodies fetched. Current totals (as of 2026-10-01, NOT the billing-cycle-start snapshot the user had — see discrepancy note):

| bucket | files | total size | avg/file | largest file seen |
|---|---|---|---|---|
| event-photos | 101 | 80.47 MB | 816 KB | 3.88 MB |
| pay-proof | 131 | 38.08 MB | 298 KB | 4.78 MB |
| chat-attachments | 184 | 26.13 MB | 145 KB | 4.92 MB |
| organizer-photos | 17 | 20.33 MB | 1.22 MB | 3.32 MB |
| stories | 2 | 8.11 MB | 4.15 MB | 4.30 MB |
| payment-documents | 29 | 5.98 MB | 211 KB | 2.07 MB (PNG), 356 KB (PDF) |
| avatars | 3 | 1.78 MB | 607 KB | 971 KB |
| event-photos-private, pay-qr | 0 | — | — | — |

**Total: 180.9 MB across 467 objects.** `event-photos` is the single largest bucket (44.5% of storage) and matches the dashboard log example (`noigiay/DSCF4223.jpg`, `bepnho/DSCF4423.jpg`, "Test sự kiện", "Event new photos" — all raw camera-resolution JPEGs, several 3-4MB each, consistent with zero prior compression).

**Discrepancy, labeled explicitly**: this 180.9MB measured total is larger than the dashboard's "Storage: 0.071/1GB" (71MB) snapshot pasted into this task. Likely explanation: the dashboard figure is a stale/cycle-start snapshot and more test events (`test-v2-*`, `test-ab56f6`, etc., timestamps in the uploaded paths) were added since — not something this pass can resolve; flagged as a fact, not papered over.

**Not measured (blocked)**: per-object request counts / which specific objects are driving the 9.6GB of cached egress. The Storage REST API gives sizes, not hit counts; Supabase's request-log/analytics data needs the project's Logs Explorer (Management API with a personal access token, or the Dashboard UI) — neither was available to this session. The dashboard's own 24h log (quoted in the task) is the only hit-count evidence in hand, and it only shows which objects were requested, not bytes transferred per request (CDN cache hit vs. miss vs. browser-cache-avoided). This is this report's main measurement gap — monitor via the Dashboard's own Storage → Logs panel going forward.

## Root causes confirmed by code audit (file:line)
1. **No upload-time compression for avatars/event/organizer photos.** `src/lib/proofUpload.js`'s `normalizeProofFile` (canvas resize+requality, used by receipts/pay-proof/stories/chat) was never reused for `uploadAvatar` (`GocContext.jsx:5649`), `uploadEventPhoto` (`:5690`), `saveOrganizerProfile`'s avatar branch (`:7787`), or `reconcileEventMedia`'s bulk photo loop (`:8104`) — all four uploaded the original camera file as-is, up to the bucket's own 50MB cap for event photos.
2. **No `cacheControl` set on any `.upload()` call** (grepped all 11 call sites) — Supabase Storage's unset default is 1h, far shorter than useful for objects that, in this app, are *never actually overwritten in place* (every upload path mints a new `Date.now()`-based path — confirmed in all four functions above — so long-lived caching is safe by construction, not just by assumption).
3. **iOS `PhotoLoader.swift`'s cache key included the full signed URL**, including its rotating token/expiry query string (`key(_:_:)`, was `"\(path)@\(Int(maxPixel))"` with `path` sometimes a 10min/1h-TTL signed URL) — an unchanged photo re-signed on a later screen visit got a brand-new cache key, silently orphaning the old entry and re-downloading + re-decoding identical bytes. Confirmed via `AppState+Data.swift`'s `createSignedURLs(...expiresIn: 600/3600)` call sites.
4. **No request coalescing in `PhotoLoader.load`** — two concurrent callers for the same (path, maxPixel) (e.g. a list cell and a story preload) each missed cache and fetched independently.
5. **No cache invalidation on sign-out** (`AppState+Data.swift:568 signOut()`) — private media (chat attachments, invite-only event photos, payment proofs) persisted in `PhotoLoader`'s NSCache/URLCache indefinitely across an account switch on a shared device. No key-collision leak (keys include the token), but the raw bytes outliving the session is itself a privacy exposure the instructions called out.
6. No shared image component on web (41 ad hoc `<img>` tags, no `loading="lazy"`), no service worker, no thumbnail/variant convention on either platform (list and detail views request the identical object). **Not addressed this pass** — see "Explicitly out of scope" below.

## Fixes shipped this pass

### Web — `src/lib/proofUpload.js` + `src/state/GocContext.jsx`
- Added `normalizeImageForUpload(file, {maxDimension, maxBytes})`, generalizing the existing `reencodeUnderLimit` shrink-loop: PNG sources stay PNG (resized only, never quality-reduced — preserves transparency, unlike always-JPEG `normalizeProofFile`), everything else re-encodes to JPEG via the same quality-step search. Files already within budget pass through unchanged (no needless re-encode).
- New budgets (`AVATAR_UPLOAD_BUDGET` = 512px/512KB, `EVENT_PHOTO_UPLOAD_BUDGET` = 1600px/2MB — matching the task's own display-size guidance) wired into all four upload call sites (`uploadAvatar`, `uploadEventPhoto`, `saveOrganizerProfile`, `reconcileEventMedia`). A `CONVERT_FAILED` decode error falls back to uploading the original rather than blocking the user — same fail-open behavior `normalizeProofFile`'s callers already rely on.
- Added `cacheControl: '31536000'` (1 year) to the same four `.upload()` calls. Safe specifically because every path is `Date.now()`-unique per upload (confirmed above) — an edited photo is a new object at a new path, never a mutation of a cached one.
- `normalizeProofFile` itself (receipts/pay-proof/stories/chat) is **untouched** — per the task's own instruction not to compress receipts/documents, and chat/stories already had their own budget.

### iOS — `apps/ios/BanbeApp/Services/PhotoLoader.swift`, `AppState+Data.swift`, `AccountView.swift`
- `key(_:_:)` now strips the query string off an absolute (signed) URL before hashing, so re-signing the same object no longer busts the decoded-image cache. Safe for the same Date.now()-path reason as above.
- Added an actor-based in-flight request map (`InFlight`) so concurrent `load()` calls for the same (path, maxPixel) share one fetch instead of double-downloading.
- Added `PhotoLoader.clearCache()` (drops NSCache + the custom URLCache only — never touches drafts/sessions/tickets, which live in entirely different stores), called from `signOut()` for privacy, and exposed as a "Clear Image Cache" row in `AccountView.swift` next to Sign Out (`account.clearImageCache`).
- Did **not** change the existing NSCache (64MB decoded)/URLCache (16MB mem / 256MB disk) size budgets — already in the ballpark the task suggested (200MB/32MB) and not implicated by the measured drivers; resizing them without profiling evidence would be guessing.

### Explicitly out of scope this pass (not done — flag before assuming otherwise)
- **Existing-media backfill**: the 180.9MB already in Storage is still uncompressed/short-cached. No production backfill was run (per the task's own approval gate). A dry-run plan is below.
- **Web lazy-loading / shared image component / service worker**: audited (41 ad hoc `<img>` tags, several list thumbnails as CSS `backgroundImage` divs in `MapExplore.jsx` rather than `<img>`, so native `loading="lazy"` doesn't even apply there) but not touched — retrofitting 24 files safely without a way to visually verify every screen in this pass's time budget was judged higher-risk than the upload/cache-control fixes, which are both high-confidence and narrowly scoped. Candidate for a follow-up pass once this one is verified on-device.
- **iOS `AsyncImage` unification**: ~15 view files (`OrganizerProfileView`, `SurveyStoryCardView`, `DashboardView`, `EditProfileView`, `ChatPhotoViewerView`, `AccountView`, `StoryViewerView`, `OnboardingViews`, …) use plain SwiftUI `AsyncImage` (its own `URLSession.shared`-backed cache) instead of `PhotoLoader`, so they don't benefit from the stable-key/dedup fixes above. `StoryViewerView.swift:221-223`'s own comment confirms this split is deliberate, not an oversight to silently "fix" — left alone this pass.
- Signed-URL TTL churn itself (10min for pay-proof/stories/chat, 1h for event-photos-private) was not shortened or lengthened — orthogonal to cached-egress and risks breaking the "freshness" and revocation guarantees the task explicitly protects.

## Dry-run backfill plan for existing oversized media (NOT executed — needs explicit approval)
- **Candidates**: `event-photos` (101 objects, 80.47MB, public bucket) and `organizer-photos` (17 objects, 20.33MB, public bucket) — both well above the new 1600px/2MB and 512px/512KB budgets respectively; `stories` (2 objects, 8.11MB, private, 10min-signed) is a smaller, lower-priority candidate.
- **Process**: for each object, download original (one-time, unavoidable egress cost — estimate ~110MB total for these two buckets, a one-time cost against future recurring savings), run it through the same `normalizeImageForUpload` budgets, upload the result to a **new** path (never overwrite the original in place), update the referencing `event_photos.storage_path` / `organizers.avatar_path` row, keep the original object for N days as rollback, then delete.
- **Estimated savings** (estimate, not measured — labeled as such): phone-camera JPEGs resized to 1600px long edge typically land 150-400KB vs. the current 800KB-3.9MB range seen above; a rough 60-75% reduction on these two buckets' ~100MB combined would save roughly 60-75MB of standing storage and a proportional cut in future per-view egress for every repeat visit to an event/organizer page.
- **Compatibility**: both platforms already fall back to the original-image URL for any row whose path doesn't match a variant-naming convention (no variant-metadata scheme exists yet — this plan would need one, or simply treat the new path as the row's sole `storage_path`, which is compatible with every existing reader).
- **Rollback**: keep original objects until the new paths are confirmed serving correctly in both apps; the DB row update is the only non-additive step and is trivially revertible (restore the prior `storage_path`).
- **Not done**: no originals were downloaded, no objects were overwritten/deleted, no DB rows were changed. This needs an explicit go-ahead before running against the live bucket.

## Verification this pass
- `npx vite build` — succeeded (467 modules, no errors).
- `xcodebuild -scheme BanbeApp -destination 'generic/platform=iOS Simulator'` — **BUILD SUCCEEDED**.
- `tests/proof-upload.spec.js`, `tests/organizer-profile-photo-refresh.spec.js`, `tests/chat-photo.spec.js` (none directly exercise the four changed upload functions' new code path by name, but share `proofUpload.js` and the organizer-photo/chat-photo UI flows) — all pass when run in isolation (1 worker). Two of these specs are flaky under 3-way parallel browser contention **on unmodified `main` as well** (confirmed via `git stash` + rerun) — pre-existing environment flakiness, not a regression from this pass.
- Not done: no physical-iPhone run (user will verify); no cold/warm network byte-count comparison (would need the Dashboard's own request logs or a packet capture neither available nor safe to fabricate here — reported as a measurement blocker, not a fabricated number).

## Monitoring egress going forward
- Supabase Dashboard → Project → Reports → Storage (or Settings → Billing) shows cached/uncached egress against the current cycle (next cycle starts after 2026-10-12 per the task's own billing-cycle note) — check weekly rather than waiting for another grace-period warning.
- Dashboard → Storage → a bucket's own object browser shows per-object size directly; the scratchpad listing script used in this pass (service-role Storage API, recursive `list`, metadata-only) can be rerun anytime to re-snapshot bucket totals without downloading anything, to track whether `event-photos`/`organizer-photos` average file size trends down after this pass's upload-time compression takes effect on new uploads.
- The real second-order win (repeat views of *existing* photos getting a 1-year `Cache-Control` instead of 1h) only applies to objects uploaded **after** this pass — existing objects keep their original 1h header until re-uploaded or backfilled (see the dry-run plan above).
