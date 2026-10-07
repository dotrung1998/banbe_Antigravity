# 35 — For You attention state, pinned chip, ensure-organizer, profile keychain

Status: IMPLEMENTED LOCALLY (web + iOS + migrations 163/164), NOT applied/deployed, nothing committed. Web `vite build` clean; iOS simulator build + all 116 BanbeAppTests green; `node --test tests/unit` 142 green. NOT verified on a physical iPhone, in a real browser, or against a real Postgres/Supabase.

## Shared keychain contract (web + iOS + backend)

### Built-in asset set (24 original designs, 7 groups)
Source of truth: `assets/keychains/` (hand-authored SVG + `manifest.json` + `LICENSES.md`), rasterised by `scripts/build-keychains.mjs` (Playwright/Chromium, transparent PNG, 256x384) into
`public/keychains/` (web, + manifest.json) and `apps/ios/BanbeApp/Resources/Keychains/` (iOS bundle, + the same manifest.json).
Every PNG is 256x384 with the small metal ring + chain INCLUDED at the top; the pivot (attach point) is the top-centre of the ring: normalised `(0.5, 0.045)`.

| group | designs |
|---|---|
| sky (stars/moon/clouds) | sky-star, sky-moon, sky-cloud |
| love (hearts/ribbons) | love-heart, love-ribbon, love-bow |
| bloom (flowers/fruits) | bloom-flower, bloom-tulip, bloom-strawberry, bloom-lemon |
| cafe (coffee/music) | cafe-cup, cafe-note, cafe-vinyl |
| pals (cats/bears) | pals-cat, pals-bear, pals-paw |
| trip (travel/tickets) | trip-ticket, trip-plane, trip-compass, trip-suitcase |
| banbe (banbe motifs) | banbe-b, banbe-stub, banbe-spark, banbe-wave |

`manifest.json` shape: `{ "version":1, "pivot":{"x":0.5,"y":0.045}, "imageSize":{"width":256,"height":384}, "anchors":["top_left","top_right","bottom_left","bottom_right"], "sizes":{"s":0.7,"m":1,"l":1.35}, "baseWidth":64, "groups":[{"id","vi","en"}], "designs":[{"id","group","vi","en","file":"<id>.png"}] }` (`baseWidth` = rendered width in CSS px / pt at size `m`).
`custom` is a reserved extra design id (user-supplied art, rendered as the image below a drawn ring).

### Appearance metadata (server-side, owner-only writes)
Table `public.profile_keychains` (PK `user_id`), RLS owner-only; visitors read ONLY through RPC. Config (camelCase JSON in RPCs):
`{ enabled:bool (default false), designId: one of the 24 ids | 'custom' (default 'sky-star'), anchor: top_left|top_right|bottom_left|bottom_right (default top_right), size: s|m|l (default m), motionEnabled: bool (default true), customAsset: {id, path, width, height} | null, updatedAt }`
No sensor readings or drag positions are ever stored.

RPCs (all `SECURITY DEFINER`, `authenticated` only, never `anon`):
- `get_my_keychain()` -> `{success:true, keychain:<config>}` (defaults if no row).
- `save_my_keychain(p_config jsonb)` -> `{success:true, keychain:<config>}` / `{success:false,error:CODE}`. Accepts `enabled, designId, anchor, size, motionEnabled, customAssetId (uuid|null)`; `custom` requires a READY asset owned by the caller.
- `get_profile_keychain(p_handle text)` -> `{success:true, keychain:<config>|null}`; null unless the owner's keychain is enabled.

### Custom art upload (private bucket `keychain-art`, object `<uid>/<assetId>.<png|webp>`)
Client re-encodes locally (canvas / UIImage -> PNG or WebP with alpha, long edge <= 512 px, <= 256 KB, no metadata) then `POST /api/media` (Bearer token):
1. `{op:'keychain_init', contentType:'image/png'|'image/webp', bytes:<int>}` -> `{assetId, path, token}` (signed upload token for `storage.from('keychain-art').uploadToSignedUrl(path, token, blob)`); quota enforced (max 3 non-deleted assets / user, rate limited).
2. client uploads the bytes.
3. `{op:'keychain_finalize', assetId}` -> `{assetId, path, width, height}` — server validates real format (magic bytes), real dimensions, size, no animation, strips ancillary metadata, overwrites the object, marks `ready`.
4. client calls `save_my_keychain({... designId:'custom', customAssetId:assetId})`.
- `{op:'keychain_delete', assetId}` -> `{ok:true}` (owner only; removes object + row; if it was the active custom art the keychain falls back to `sky-star`).
Replacing art = init/upload/finalize new, save, then delete the old one. Reading: `storage.from('keychain-art').createSignedUrl(path, 3600)`; storage SELECT policy allows the owner, or any authenticated user when the owner's keychain is enabled and references that path. Account deletion removes the folder.

### Motion model (shared numbers, one module per platform)
Damped pendulum about the fixed pivot: angle `θ`, `θ'' = -(g/L)·sinθ - c·θ' + impulse`; stretch `s` (vertical extension, spring k, damping) clamped to `[-0.12, +0.35]·L`; angle clamped to ±0.9 rad; settle when `|θ|<0.004 && |θ'|<0.02 && |s|<0.002` -> stop the loop (no idle loop). Drag: vertical drag maps to stretch/lift (clamped), horizontal component to angle; release -> damped settle. Sensor/shake impulses capped at ±0.35 rad/s per event, at most 1 per 120 ms. Frame loop runs ONLY while not settled AND visible/foreground AND motion enabled AND not Reduce Motion. Non-drag controls: a "Swing" button (and keyboard Enter/Space on the focusable charm) that applies one bounded impulse; Reduce Motion = static charm, the button gives a brief non-moving highlight. No network call per interaction.

## Results

### 1. For You attention state
`src/lib/forYouAlert.js` + `useForYouAlert.js` + `src/screens/ForYouChip.jsx`; iOS `Lib/ForYouAlert.swift`. State per account (`banbe.forYouAlert.v1:<uid>`): baselined/prefsVersion/seen/pending/order. First observation or a changed prefsVersion baselines silently; only unseen/version-changed MATCHING events become pending; acknowledge on opening For You clears only the loaded ids. Version = `reviewed_at|submitted_at|status|visibility` (no `updated_at` is selected; price/seat changes never re-alert). Chip: one-shot ~3 s sweep + 2 halo pulses, then a "New" pill (white on #7A5200 ~6.9:1); static under Reduce Motion. Eligibility untouched.
### 2. Pinned filter
Second row = pinned For You chip + separate scroller (`data-hscroll`, `home-filter-extra-scroller`; iOS `statusFilterRow` keeps the `homeFilterStatus` exclusion zone). Known: a swipe starting on the pinned chip itself falls through to the root-tab swipe (web).
### 3. Organizer ensure (root cause)
`organizers` row was only created lazily inside `create_event_draft` (migrations 007/112); `set_organizer_mode` only flips role/flag, so Organizer Mode with no event yet had no Host card. Migration `163_ensure_my_organizer.sql`: `ensure_my_organizer()` (auth.uid only, advisory lock per user, owner-only check — team membership does not count, name = display name + " Events"/" Sự kiện" else neutral fallback, never email/phone, no role change, nothing published). Web `src/lib/{ensureOrganizer,useEnsureOrganizer}.js` + Account.jsx loading/error/Retry card; iOS `AppState+EnsureOrganizer.swift` + AccountView card. Open gap: an owned organizer with a BLANK name still leaves `myOrganizerId` null on web (syncUser) and shows no loading card.
### 4/5. Keychain
Backend: migration `164_profile_keychain.sql` (private bucket `keychain-art`, `profile_keychains`, `keychain_assets`, 3 RPCs, no client write policy on storage), `api/_lib/keychainArt.js` (ops dispatched from `handleMediaRequest`; works without R2 env; 3-asset quota, 10 inits/h, magic-byte/dimension/animation checks, metadata strip, delete cleanup), account-deletion cleanup in `api/auth/index.js`. Art: `assets/keychains/` (24 SVG sources, manifest, LICENSES.md), `npm run build:keychains` -> `public/keychains/` + `apps/ios/BanbeApp/Resources/Keychains/`. Web: `src/lib/keychain{,Physics,Motion,Upload}.js`, `src/components/Keychain{Charm,Settings}.jsx`. iOS: `Models/Keychain.swift`, `Lib/KeychainPhysics.swift`, `Services/KeychainArtService.swift`, `State/AppState+Keychain.swift`, `Views/KeychainViews.swift`. Anchors are PHYSICAL corners (not flipped in RTL). Web top anchors hang in a side gutter (cards narrow ~48 px at size M); iOS bottom anchors sit inside the card. iOS adds a 60 s sensor idle stop. Tilt/Swing buttons exist only in the settings preview; profile cards get drag + keyboard/accessibility action.

### Migrations to apply (`supabase db push`, after any earlier pending ones): 163, 164
### Tests
`tests/unit/{forYouAlert,ensure-organizer,keychain-manifest,keychain-api,keychain-physics,keychain-motion,keychain-upload}.test.mjs`; iOS `ForYouAlertTests`, `EnsureOrganizerTests`, `KeychainTests`. `tests/home-foryou-pinned.spec.js` written but FAILS in `setupToHome` (Home never appears in 8 s) — environment, not run green.
### Not verified
Real Postgres/Storage behaviour of 163/164; physical-device haptics, tilt/shake feel, drag vs scroll vs tab swipe; real-browser pointer drag, DeviceMotion permission, canvas re-encode; visual placement of the charm on both profile cards; `love-ribbon` art is the weakest.
