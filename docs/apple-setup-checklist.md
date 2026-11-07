# Apple setup checklist (do this after buying the Apple Developer Program)

Everything on banbe's side is already built and switched off. These steps connect it. About 45 minutes.
Troubleshooting and how push works inside: `docs/push-setup.md`.

## 1. Enroll
1. developer.apple.com/programs → Enroll (99 USD/year). Choose **Organization** if you want "banbe" (not your own
   name) shown as the seller on the App Store. Organization enrollment needs a D-U-N-S number.
2. When approved: developer.apple.com → Account → **Membership details** → copy the **Team ID** (10 characters).

## 2. App ID
Certificates, Identifiers & Profiles → **Identifiers** → `com.banbe.ios` (create it if missing, type App IDs → App):
- tick **Push Notifications**
- tick **Associated Domains**
- Live Activities need no separate tick: they use the app's Push Notifications capability. The Live Activity
  widget extension (`com.banbe.ios.LiveActivity`) is registered by Xcode automatically on the first signed build.

## 3. APNs key (.p8)
Keys → **+** → name "banbe APNs" → tick **Apple Push Notifications service (APNs)** → Continue → Register →
**Download** (only possible once; keep it safe, never in the repo or a chat). Note the **Key ID** (10 characters).
One key works for both development (sandbox) and production.

## 4. Put the values where they belong
**Repo (local files only):**
```bash
node scripts/apple-team-setup.mjs --team <TEAM_ID>
cd apps/ios && xcodegen generate
```
Commit the two changed files (`apps/ios/Config/Team.xcconfig`, `public/.well-known/apple-app-site-association`).

**Vercel** → Project → Settings → **Environment Variables** → Production (or `vercel env add <NAME> production`):
| Name | Value |
|---|---|
| `APNS_KEY_ID` | Key ID from step 3 |
| `APNS_TEAM_ID` | Team ID from step 1 |
| `APNS_BUNDLE_ID` | `com.banbe.ios` |
| `APNS_PRIVATE_KEY` | the whole `.p8` file content (line breaks or literal `\n` both work) |
| `APNS_ENV` | leave empty (each device's own environment is used). Set `sandbox` or `production` only to force one. |
| `CRON_SECRET` | a long random string, if not already set |
Then **Redeploy** (Deployments → ⋯ → Redeploy) so the function sees them.

**Supabase** → SQL Editor → run once (the second value must equal `CRON_SECRET`):
```sql
select vault.create_secret('https://www.banbe.app/api/cron?job=push-drain', 'push_drain_url');
select vault.create_secret('<the CRON_SECRET value>', 'push_drain_secret');
```

## 5. Turn push on
In the app as an admin: **Account → Admin → Feature switches → Push notifications (iPhone)** → on.
Until then nothing is queued. If you turn it on before step 4 is complete, the server runs dry (logs counts only,
sends nothing).

## 6. Check with a test iPhone
1. Xcode → open `apps/ios/BanbeApp.xcodeproj` → scheme **BanbeApp**, configuration **Debug** → your iPhone → Run.
2. Sign in, open a confirmed ticket → banbe asks "Get reminders for your events?" → Continue → Allow.
3. From a second account, send yourself a chat message. The push should arrive within seconds (not between 22:00 and
   07:00 on the phone's clock: those wait until 07:00).
4. If nothing arrives, Supabase SQL Editor:
   ```sql
   select status, attempts, last_error, created_at from push_outbox order by id desc limit 10;
   ```
   `skipped_no_credentials` = step 4 Vercel values missing; nothing at all = switch off or no device token.

## 7. Apple Wallet passes (later, optional)
1. Identifiers → **+** → **Pass Type IDs** → e.g. `pass.app.banbe.ticket`.
2. Select it → **Create Certificate** → upload a CSR made with Keychain Access (Certificate Assistant → Request a
   Certificate From a Certificate Authority) → download the `.cer` → double-click → export the certificate + private
   key from Keychain as `.p12`.
3. Convert and base64 (Terminal):
   ```bash
   openssl pkcs12 -in pass.p12 -clcerts -nokeys -out signerCert.pem -legacy
   openssl pkcs12 -in pass.p12 -nocerts -out signerKey.pem -legacy
   curl -sO https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer
   openssl x509 -inform der -in AppleWWDRCAG4.cer -out wwdr.pem
   base64 -i signerCert.pem | pbcopy   # repeat for signerKey.pem and wwdr.pem
   ```
4. Vercel env: `WALLET_PASS_TYPE_ID`, `WALLET_TEAM_ID`, `WALLET_SIGNER_CERT`, `WALLET_SIGNER_KEY`,
   `WALLET_WWDR_CERT` (the three base64 values), `WALLET_SIGNER_KEY_PASSPHRASE` (if you set one),
   `WALLET_AUTH_SECRET` (a long random string). Redeploy. Details: `.claude/notes/24-apple-wallet-pass.md`.
   Until then "Add to Apple Wallet" answers "not available yet" (503).
