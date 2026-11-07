# Push notifications: how it works and troubleshooting

**The step-by-step owner checklist is `docs/apple-setup-checklist.md`.** This file explains the pieces.

Everything is built (migration 194, `api/_lib/apnsAlerts.js`, `/api/cron?job=push-drain`, iOS registration and the
Q6 ask). Three things gate it: the `push_enabled` switch (off = nothing queued), the Supabase Vault secrets (nothing
wakes the sender without them) and the APNs credentials on Vercel (without them the sender runs dry and marks rows
`skipped_no_credentials`). Pushes due more than 15 minutes ago expire, so turning it on later never sends a pile of
old alerts. Quiet hours: 22:00–07:00 on the phone's clock; those wait until 07:00. Promotional kinds (the weekly
digest) are pushed only to people who opted in.

Time needed: about 30 minutes once the membership is approved.

## What gets pushed
Every in-app notification (the bell list), in the recipient's language, unless the person muted that kind
in the notification menu or already read it in the app. Tapping a push opens the same screen as tapping it
in the bell. iOS asks for permission after sign-in; people can turn it off in iOS Settings.

## 1. Apple Developer portal
1. Join the Apple Developer Program. An **Organization** membership shows "banbe" as the seller on the App
   Store; an Individual one shows your own name.
2. Note your **Team ID**: developer.apple.com > Account > Membership details (10 characters, e.g. `ABCDE12345`).
3. Certificates, Identifiers & Profiles > **Identifiers** > App ID `com.banbe.ios` (Xcode can create it in
   step 2.3): enable **Push Notifications** and **Associated Domains**.
4. **Keys** > + > name it "banbe APNs" > tick **Apple Push Notifications service (APNs)** > Continue >
   Register > **Download** the `.p8` file (Apple lets you download it only once) and note its **Key ID**.
   The same key works for development and production. Keep the `.p8` out of the repo.

## 2. This repo (local files only)
```bash
node scripts/apple-team-setup.mjs --team ABCDE12345     # your Team ID
cd apps/ios && xcodegen generate
```
This sets `DEVELOPMENT_TEAM` in `apps/ios/Config/Team.xcconfig` (Debug and Release already carry the Push
entitlement) and puts the Team ID into `public/.well-known/apple-app-site-association` (universal
links for `/u/*`). Commit both files. `PersonalTeamDebug` is unaffected and still has no Push.

Open the project in Xcode, check Signing & Capabilities shows your team, run the **Debug** build on a real
iPhone, sign in, and allow notifications. The device token is stored with `environment = sandbox`.

## 3. Supabase (production)
1. Apply migrations **194** (push) and **195** (US time zone + currency) if they are not live yet. Production
   deliberately lacks 182-185, so apply them one at a time from a one-file workdir, the same way as the
   2026-10-22 rewards rollout (`.claude/notes/58-…md`, "Production log"). Check with
   `supabase migration list --linked` first.
2. SQL editor, once (the second value must equal `CRON_SECRET` on Vercel):
   ```sql
   select vault.create_secret('https://www.banbe.app/api/cron?job=push-drain', 'push_drain_url');
   select vault.create_secret('<the CRON_SECRET value>', 'push_drain_secret');
   ```

## 4. Vercel (Project > Settings > Environment Variables, Production)
| Variable | Value |
|---|---|
| `APNS_TEAM_ID` | Team ID from step 1.2 |
| `APNS_KEY_ID` | Key ID from step 1.4 |
| `APNS_PRIVATE_KEY` | full contents of the `.p8` file (pasting with line breaks or literal `\n` both work) |
| `APNS_BUNDLE_ID` | `com.banbe.ios` (`APNS_TOPIC` also accepted) |
| `APNS_ENV` | optional: `sandbox` or `production` forces one gateway; empty = each device's own |
| `CRON_SECRET` | a long random string, if not set already (other cron jobs use it too) |

Redeploy so the function sees the new variables.

## 5. Check it works
1. From a second account, send yourself a message (or trigger any notification for your account).
2. The push should arrive within a few seconds. If not:
   ```sql
   select id, status, attempts, last_error, created_at from push_outbox order by id desc limit 10;
   select platform, environment, app_id, updated_at from device_push_tokens where user_id = '<your user id>';
   ```
3. Manual wake-up (should answer `{"claimed":…,"sent":…}`):
   ```bash
   curl -X POST -H "Authorization: Bearer $CRON_SECRET" "https://www.banbe.app/api/cron?job=push-drain"
   ```

| Symptom | Cause / fix |
|---|---|
| rows end as `skipped_no_credentials` (`dry_run: true` from the drain) | one of `APNS_TEAM_ID` / `APNS_KEY_ID` / `APNS_PRIVATE_KEY` missing, or no redeploy |
| nothing queued at all | `push_enabled` is off (Account → Admin → Feature switches) |
| `401 UNAUTHORIZED` from the drain | Vault `push_drain_secret` ≠ Vercel `CRON_SECRET` |
| rows stay `pending`, then `expired` | Vault secrets missing (nothing wakes the drain) or `pg_net` blocked; the per-minute `bb_push_drain_tick` job retries |
| `last_error` 403 `InvalidProviderToken` | wrong Key ID / Team ID, or the key doesn't have APNs ticked |
| `last_error` 400 `DeviceTokenNotForTopic` | `APNS_TOPIC` / bundle id mismatch (the token is removed) |
| no row in `push_outbox` | no device token for that user (permission denied, or a free-team build) or the kind is muted |

TestFlight and App Store builds register `environment = production` automatically (read from the app's
provisioning profile). A token sent to the wrong environment is retried on the other one and corrected.

## Turning it off
Delete the Vault secret `push_drain_url` (stops waking the drain) or remove `APNS_PRIVATE_KEY` on Vercel.
Nothing else needs to change; in-app notifications are unaffected.

## Also unblocked by the same membership
- Apple Wallet passes: `.claude/notes/24-apple-wallet-pass.md` (needs a Pass Type ID certificate).
- Apple Maps on the web: `.claude/notes/42-web-mapkit.md` (a Maps ID + a key with MapKit JS ticked).
