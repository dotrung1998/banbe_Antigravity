# 40 — Event/photo share previews, Supabase quota outage, recovery runbook (2026-10-09)

Status: share-preview code is in commit 46847aa; error-UI copy + compress script IMPLEMENTED (uncommitted when written). R2 NOT configured (needs the account owner). Nothing here could be verified against production: the Supabase project was blocked.

## Incident
- Supabase org `zanlbyylttnadeehylgy` used 17.04GB of 5.5GB cached egress; "requests to your projects are dropped until the quota refills on October 12, 2026" (email 2026-10-09). Dashboard still works; REST/Auth/Storage all return `exceed_cached_egress_quota`. The app shows the account-gate "unavailable" screen. No app change revives it before the refill; the only immediate fix is Pro (can be downgraded after a month).
- Cause (hypothesis, never measured per-object): repeat downloads of public event/organizer photos (+ re-signed private URLs). See notes 22 and 28.

## Account-gate "unavailable" UI
- iOS `AccountGateViews.swift` / web `AccountGate.jsx`: title now "Service temporarily unavailable" (vi "Dịch vụ tạm thời không khả dụng"), subtitle says banbe can't reach its servers; Try again unchanged. The same screen is used for a plain network failure, so the copy covers both.

## Share previews (api/photo-share.js, vercel.json)
- `?eid=<event id>` = event share, preview = cover photo (first `event_photos` by sort_order), only `visibility='public'`, status live/ended/cancelled. `?pid=<event_photo id>` = that photo. Event shares used `https://banbe.app/<key>` (domain no longer exists) -> now `https://www.banbe.app/api/photo-share?eid=` on web (`shareEvent`) and iOS (`EventDetailView.share()`, reuses `PhotoShareSource`, now internal).
- Why Messenger showed no image: Facebook/Messenger scrape `og:url`/canonical, which pointed at the SPA index (no OG tags). `og:url` + canonical are now the share URL itself.
- Why WhatsApp showed the logo: lookup failed (quota block) -> wordmark fallback. WhatsApp also drops og:images over ~300KB: WhatsApp UA gets `w=640&q=60`, everyone else `w=1200&q=75`, via Vercel Image Optimization (`images` block in vercel.json, remotePattern = the Supabase public event-photos path). The endpoint GETs the optimized URL first and falls back to the original image if it doesn't return an image, so a bad optimizer config cannot blank the preview. UNVERIFIED: that `/_vercel/image` works for this project/rewrite setup — test after deploy.
- Still on `banbe.app`: ticket links (`BanBeContext.jsx` ~8073 `/ve/`), organizer/profile share links + QR codes, HostPromo, iOS HostPromoViews. Not changed.
- WhatsApp/Messenger cache previews per link; re-test with a fresh link or the Facebook Sharing Debugger.

## Recovery runbook (do in this order once Supabase is reachable: Oct 12 or after upgrading)
1. Sanity: app loads, `supabase migration list`, then `supabase db push` (pending: 153 R2 columns, 156/159/162–167 etc. — check each note's "must be applied" line first; 167 = hourly end-past-events cron).
2. Quick egress win with NO Cloudflare: `node scripts/compress-supabase-media.mjs` (dry-run) -> `--apply --limit 5` -> verify in both apps -> `--apply`. New objects are <=1600px (events) / 512px (organizers) JPEG q82, uploaded to a NEW path with 1-year Cache-Control; originals kept; row switched compare-and-set; state in `.migration-state/compress-supabase.jsonl`. Undo: `--rollback --apply`. Delete originals after a week: `--purge --older-than-days 7 --apply`. Needs service-role key + macOS `sips`. Dry-run was NOT executed (DB unreachable).
3. R2 (note 28): owner does Cloudflare setup (buckets, custom domain, tokens), sets Vercel env from `.env.example`, `MEDIA_R2_UPLOADS` off first, then `node scripts/migrate-media-to-r2.mjs` dry-run -> `--apply --event-ids ...`. Do NOT run both scripts blindly on the same rows: compress skips rows with `r2_ref`; the R2 script reads whatever `storage_path` points to (the compressed copy is fine).
4. Watch Supabase Dashboard > Reports > Storage weekly; the 5.5GB cap is per billing cycle.
