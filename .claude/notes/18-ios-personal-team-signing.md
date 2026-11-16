# iOS Personal Team signing — local real-device testing on a free Apple ID (2026-10-02)

## Status: WORKING (config/entitlements/scheme added and build-verified on this machine; actual on-device install/signing under the user's own Apple Account was NOT performed in this session — no Apple ID is signed into Xcode in this sandbox).

## A. Current state

- A new `PersonalTeamDebug` build configuration + scheme exists, alongside the pre-existing `Debug`/`Release` — neither of those two was changed in behavior.
- It intentionally omits every capability not confirmed to provision under a free/personal Apple ID: no `aps-environment` (Push), no `com.apple.developer.associated-domains` (Universal Links). This app has no App Groups/iCloud/Sign in with Apple/Apple Pay entitlement anywhere today, so there was nothing else to exclude.
- **What works** under `PersonalTeamDebug`: install/run on the owner's own iPhone via Xcode + a signed-in Personal Team; the full app UI; Supabase (auth, data, Storage — none of that depends on any entitlement); `banbe://` custom-scheme deep links (OAuth callback, shared-organizer-link "Open" button); the public-profile web page at `https://banbe.app/u/<handle>` opened from Safari (that route lives entirely on the web app, untouched — see 17-ux-foundation-release.md).
- **What's intentionally disabled/degraded**: remote push registration (already gated behind `ENABLE_PUSH`, which this configuration also sets to `NO` — the exact same guard the ordinary `Debug` config has always relied on, see 07-notifications.md) and Universal Links (`https://banbe.app/...` tapped from another app opens Safari instead of the app itself — the ordinary system behavior for a link with no verified app association, not a custom fallback this app had to build). Neither crashes or shows a misleading "push enabled"/"linked" state.

**2026-10-02 addendum — distinct Home Screen icon/name**: `PersonalTeamDebug` installs as **"Banbe Dev"**; the normal Debug/Release build is still **"banbe"** (its existing, unchanged display name — untouched by this addendum). Both can be installed on the same iPhone at once, as two entirely separate apps (different bundle ids — `com.thetrung.banbe.dev` vs `com.banbe.ios` — means separate Home Screen entries, separate sandboxed storage, separate everything). Stopping Xcode does **not** uninstall "Banbe Dev" — it stays on the device exactly like any other installed app until you delete it yourself; if you tap the OLD "banbe" icon after a `PersonalTeamDebug` session, you're opening whatever was last built/signed for over there under whichever config that was, not "reverting" anything.

## B. How to run now

1. Open `apps/ios/BanbeApp.xcodeproj` in Xcode (regenerate first with `xcodegen generate` from `apps/ios/` if you've pulled newer source — the committed project file doesn't auto-discover changes).
2. Xcode → Settings → Accounts: sign in with your Apple Account (a free/personal one is enough).
3. Select the `BanbeApp` project → `BanbeApp` target → Signing & Capabilities → for the **PersonalTeamDebug** configuration specifically, choose your Personal Team from the Team dropdown.
4. In Xcode's scheme picker (next to the Run/Stop buttons), select the **PersonalTeamDebug** scheme.
5. Select your own physical iPhone as the run destination (plugged in, or over the network if already paired).
6. Confirm "Automatically manage signing" is checked (it is, by default, for this configuration — `CODE_SIGN_STYLE = Automatic`).
7. Press Run.
8. Free Apple ID provisioning profiles are time-limited and Xcode/iOS periodically require the app to be re-signed/reinstalled to keep running — exactly how long is not restated here since it isn't verified against Apple's current docs/Xcode UI in this session; if the app stops launching after some time with a "developer cannot be verified"/expired-profile message, re-running from Xcode re-signs it.

## C. Upgrade checklist after joining the Apple Developer Program

1. In Xcode, select your paid team (Settings → Accounts, and again per-target in Signing & Capabilities).
2. Switch back to the **Debug** or **Release** configuration/scheme for anything beyond personal-device testing — never ship or extensively test on `PersonalTeamDebug` going forward; it exists only for the free-team gap.
3. Register/confirm the real production App ID (`com.banbe.ios`) in the Apple Developer portal.
4. Enable the Push Notifications capability for that App ID (portal + Xcode).
5. Enable the Associated Domains capability for that App ID (portal + Xcode).
6. `Release` already points at `BanbeAppPush.entitlements` (declares `aps-environment` + `com.apple.developer.associated-domains`) — nothing to change there; just set `DEVELOPMENT_TEAM` in `apps/ios/project.yml` to your real Team ID and rebuild (see 07-notifications.md's own two-edit summary — still accurate, unchanged by this pass).
7. Configure real APNs credentials (Auth Key/certificate) and whatever server-side sending piece the notification architecture ends up using — nothing in this repo sends a real push yet regardless of team (07-notifications.md).
8. Replace the literal `"TEAMID"` placeholder in `public/.well-known/apple-app-site-association` with `<REAL_TEAM_ID>.com.banbe.ios`.
9. Deploy that file at exactly `https://banbe.app/.well-known/apple-app-site-association`, served as `application/json`, no redirect, no auth wall (`vercel.json` already sets the content-type header — just needs the real Team ID in the file and a real deploy).
10. Test Universal Links on a fresh physical-device install (uninstall/reinstall first — iOS caches AASA resolution).
11. Test real push delivery end-to-end, including token registration (`register_push_token()`).
12. Update any other placeholder (`src/lib/appStore.js`'s `APP_STORE_URL`, etc.) now that this app has real store/team identifiers.
13. **Never copy `BanbeApp.PersonalTeam.entitlements` into a production/paid-team build** — it exists specifically to have LESS than the real entitlements file, permanently; if a future capability is added to the paid entitlements, it does not automatically belong in the personal-team one too (see that file's own comment).

## D. Exact files/build settings changed and why

- `apps/ios/BanbeApp/BanbeApp.PersonalTeam.entitlements` (new) — empty entitlements dict, the Personal Team Debug config's `CODE_SIGN_ENTITLEMENTS`. Distinct from `BanbeApp.entitlements` (the ordinary Debug file), which now also declares Associated Domains (2026-10-01 UX foundation pass) — that's exactly the extra capability this new file has to NOT carry.
- `apps/ios/Config/PersonalTeamDebug.xcconfig` (new) — `ENABLE_PUSH = NO`, points at the new entitlements file, `CODE_SIGN_STYLE = Automatic`, and defines `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) PERSONAL_TEAM_BUILD`. (It also names `DEVELOPMENT_TEAM` since 2026-11-16 — see the addendum at the end.)
- `apps/ios/project.yml` (2026-10-02 addendum) — `CFBundleDisplayName` changed from the literal string `banbe` to `$(APP_DISPLAY_NAME)` (a build-setting variable Xcode substitutes into Info.plist at build time — the same mechanism `$(PRODUCT_BUNDLE_IDENTIFIER)` already relies on for `CFBundleIdentifier`). `APP_DISPLAY_NAME` is defined as `banbe` in the target's base settings (Debug/Release: unchanged from before) and overridden to `Banbe Dev` only under `settings.configs.PersonalTeamDebug`. Verified in the actual built `.app` bundle's `Info.plist`, not just `-showBuildSettings`.
- `apps/ios/project.yml` — new top-level `configs:` map (`Debug: debug, Release: release, PersonalTeamDebug: debug`, required so xcodegen creates the third configuration at all instead of only its default Debug/Release pair); new `configFiles.PersonalTeamDebug` entry; new per-config `PRODUCT_BUNDLE_IDENTIFIER: com.thetrung.banbe.dev` under the `BanbeApp` target's `settings.configs.PersonalTeamDebug` (the "distinct bundle id" from requirement 4 — lets Automatic Signing register a brand-new App ID for local testing without ever touching or colliding with the real `com.banbe.ios` App ID this project ships under); new `schemes.PersonalTeamDebug` (build the app target only, run config `PersonalTeamDebug`) so it's a single scheme-picker selection, not a manual per-run Edit Scheme change.
- `apps/ios/BanbeApp/App/BanbeApp.swift` — one `#if PERSONAL_TEAM_BUILD` console `print(...)` in `init()`, developer-only (no UI banner), per this ticket's own instruction.
- `apps/ios/BanbeApp/State/AppState+Push.swift`, `apps/ios/BanbeApp/State/AppState+Profile.swift` — doc-comment-only additions (no logic change) noting that the existing `ENABLE_PUSH` guard and the OS's own "no entitlement → open in Safari" behavior already cover this new configuration for free; nothing needed a new runtime check.
- **No push/notification-extension target exists in this project** (`project.yml` defines only the `BanbeApp` app target and the `BanbeAppUITests` test bundle) — requirement 3's "any push/extension target entitlement file if that target participates in signing" does not apply here.

Cross-references: 07-notifications.md's own paid-team upgrade steps are unchanged and still authoritative for Push specifically — this note's Section C just adds the Associated Domains/AASA half on top. 17-ux-foundation-release.md's Section D ("what's still a placeholder") now points here for the signing side of that story.

## 2026-11-11 addendum: bundle id renamed

`com.banbe.ios.dev` was already registered to another Apple team, so Automatic Signing failed with "Failed Registering Bundle Identifier". `PersonalTeamDebug` now uses `com.thetrung.banbe.dev` (Live Activity: `com.thetrung.banbe.dev.LiveActivity`). Verified: builds, installs and launches on a physical iPhone. A free Apple ID allows only 3 apps on a device, so uninstall one if install fails with "maximum number of installed apps". `xcodegen generate` clears the team (Config/Team.xcconfig is empty): reselect the Personal Team in Xcode, or build with `DEVELOPMENT_TEAM=<team id>` — superseded by the 2026-11-16 addendum below.

## 2026-11-16 addendum: PersonalTeamDebug names its team

Command-line device builds failed with "No Account for Team \"6477969BNB\"" / "No profiles for 'com.thetrung.banbe.dev' were found" unless `DEVELOPMENT_TEAM=<id>` was passed by hand: `xcodebuild` does not fall back to the Apple Account selected in Xcode, and `xcodegen generate` leaves `Config/Team.xcconfig` empty (that file is the PAID team's, included only by Debug/Release, and was NOT touched). `Config/PersonalTeamDebug.xcconfig` now sets `DEVELOPMENT_TEAM = XXXXXXXXXX` — the free "The Trung Do (Personal Team)" team registered in Xcode → Settings → Accounts. Bare `xcodebuild -scheme PersonalTeamDebug -destination 'id=<device>' -allowProvisioningUpdates` now signs, installs and launches on the physical iPhone. Another developer on their own personal team changes that one line (or passes `DEVELOPMENT_TEAM`, command-line wins over xcconfig). The team comes from the certificate/account, not the CN's parenthesised number: the keychain identity reads `Apple Development: thetrung1998@live.com (6477969BNB)` while its OU and the provisioning profiles are `XXXXXXXXXX`.
