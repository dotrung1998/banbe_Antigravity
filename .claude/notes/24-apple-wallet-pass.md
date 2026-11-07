# Apple Wallet ticket + custom card design (2026-10-05)

## Status: PARTIALLY WORKING — iOS UI, issue endpoint and pass-update (void-on-gift) service built; real signing/APNs NOT verified (no Pass Type ID certificate yet)

- iOS: confirmed-ticket screen (`ConfirmedView`) has "Add to Apple Wallet" for paid, un-gifted tickets → `WalletPassDesignView` (colour presets, custom background/text colour, optional banner photo centre-cropped to 750x246 PNG) → `WalletPassService.fetchPass` → `PKAddPassesViewController`. Style persists in UserDefaults (`walletPassStyle.v1`).
- Server: `api/wallet-pass.js` (POST, bearer token, RLS read of the booking; refuses unconfirmed or gifted tickets). Built with `passkit-generator`. Verified locally only with a throwaway self-signed cert (pass builds/signs; guard paths 503/401/400 answer correctly). Wallet itself has not accepted a pass yet.
- Without the env secrets the endpoint answers 503 `WALLET_NOT_CONFIGURED` and the app shows "Apple Wallet isn't switched on yet".

## To switch on (needs a paid Apple Developer account)
1. Register a Pass Type ID, create its certificate, export cert + key as PEM.
2. Download Apple's WWDR intermediate certificate (PEM).
3. Vercel env: `WALLET_PASS_TYPE_ID`, `WALLET_TEAM_ID`, `WALLET_SIGNER_CERT`, `WALLET_SIGNER_KEY` (both base64 of the PEM), `WALLET_WWDR_CERT` (base64), optional `WALLET_SIGNER_KEY_PASSPHRASE`.
4. Deploy, then add a pass from a real device and confirm Wallet accepts it.

## Pass update service (void on gift) — built, NOT verified against real Wallet/APNs
- Passes carry `webServiceURL` = `<origin>/api/wallet` + a per-pass HMAC `authenticationToken`. `api/wallet/[...path].js` implements Apple's register / unregister / list-updated / fetch-latest / log endpoints. A ticket that is no longer live (gifted, cancelled, expired) is re-issued as a **voided** pass with no barcode.
- Push: `api/_lib/apns.js` sends an empty background push (HTTP/2, Pass Type ID cert as TLS client cert, topic = pass type) when `api/_lib/walletRefresh.js` sees the ticket's state hash change.
- Triggers: iOS calls `api/wallet-refresh` right after a successful gift (`AppState+Gifting.confirmGift`); `api/cron/wallet-pass-sweep` (daily, vercel.json) catches everything else; Wallet's own list call also re-checks.
- **Needs migration 140** (`wallet_passes`, `wallet_pass_registrations`, service-role only) applied with `supabase db push`, plus `SUPABASE_SERVICE_ROLE_KEY` and optionally `WALLET_AUTH_SECRET` in Vercel. Without the migration/key, passes are still issued but without the update service (the issue endpoint logs why).
- Verified locally: voided-vs-live pass build, state hash, token check (throwaway cert). NOT verified: real APNs delivery, Wallet registering and fetching, multi-seat split (qty change) refresh. The push uses `api.push.apple.com` (production); a development-signed pass would need testing on a production-signed one.

## Gift PDF "Add to Apple Wallet" button
- The recipient may have no banbe account, so the PDF links to `GET /api/wallet-pass?gift=<admission token>` (public; the unguessable admission token, already the QR's content, is the credential). Safari then shows iOS's Add-to-Wallet sheet. Recipient passes use serial `gift-<token>`, the default dark design, a "GIFTED TO" field, and are NOT registered for updates (no void/refresh later). Needs `SUPABASE_SERVICE_ROLE_KEY` (lookup by token) and the Wallet cert env; otherwise 503.
- PDF layout is four actions in three groups: Wallet (filled hero), Apple/Google Calendar pair, open-in-banbe. Verified by rendering the PDF in the simulator and by `GiftTicketPDFTests` (12 pass). Link taps in real viewers and the Wallet download itself are NOT verified.

## Known limits
- The pass logo is the Home-screen wordmark, recoloured server-side to the card text colour (loadWordmark in api/_lib/walletPass.js, uses pngjs). The small notification icon still reuses banbe-mark.png at every size; Apple wants dedicated 29/58/87 px icons.
- Voiding depends on the holder's phone being online to receive the push; an offline phone keeps the old pass until it next syncs.
- The Wallet card shows only the purchaser's own tickets; gifted PDFs do not get a Wallet button.
