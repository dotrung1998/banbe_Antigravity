# banbe — iOS (SwiftUI)

A native SwiftUI client for the same Supabase project the web app
(the repo root) uses. Same tables, same RLS policies, same RPCs — this is
a second frontend, not a second backend.

## Structure (MVVM)

```
apps/ios/
  project.yml              # XcodeGen project definition — the source of
                            # truth; BanbeApp.xcodeproj is generated from it
                            # and is NOT committed (see .gitignore)
  BanbeApp/
    App/BanbeApp.swift      # @main entry point
    Models/                 # Codable structs matching the Postgres schema
    Services/SupabaseService.swift
    ViewModels/              # ObservableObject state + Supabase calls
    Views/                   # SwiftUI screens
    Resources/Assets.xcassets
```

## One-time setup

```bash
brew install xcodegen        # already done on this machine
cd apps/ios
xcodegen generate            # writes BanbeApp.xcodeproj
open BanbeApp.xcodeproj       # first launch: let Xcode resolve SPM packages
```

Re-run `xcodegen generate` any time you add/remove a file or change
`project.yml` — the `.xcodeproj` is generated output, not hand-edited.

To build from the command line instead of Xcode:

```bash
xcodebuild -project BanbeApp.xcodeproj -scheme BanbeApp \
  -destination 'generic/platform=iOS Simulator' build
```

(Already verified to build clean on this machine with Xcode 26.6.)

## What's implemented so far

- **SupabaseService** — one shared `SupabaseClient`, same project URL and
  anon key as `src/lib/supabase.js`. Accounts created on web sign in fine
  here and vice versa; it's the same `auth.users` table.
- **Models** — `Profile`, `Organizer`, `Event`, `Booking`, `ChatThread`,
  `ChatMessage`, `AppNotification`, matching the tables created in
  `supabase/migrations/` (001 core schema, 002 booking lifecycle, 003 social
  chat, 019 notifications).
- **AuthViewModel** — session restore + listener (mirrors GocContext's
  `onAuthStateChange` handling), email-code sign-in (request + verify),
  profile load, and a Face ID app-lock (below).
- **AuthAPIService** — requests the sign-in/sign-up code from
  `/api/auth/send-email-code` (the same Vercel function the web app uses,
  delivering via Gmail), rather than Supabase's own `signInWithOTP` mailer.
  Verifying the code is still a direct `supabase.auth.verifyOTP` call —
  just checking a token, not sending anything.
- **BiometricAuthService** — thin `LocalAuthentication` wrapper used only
  for that app-lock, nothing more.
- **HomeViewModel** — fetches `events` where `status = 'live'`, same rows
  the web Home screen's "All" section reads via `events_select_public` RLS.
- **PhotoCatalog** — the same `LOCAL_PHOTOS` rotation as
  src/data/events.js, so each card gets a real photo (served from the
  deployed web app's `/photos/*`, since the `events` table itself has no
  photo column — the web feed doesn't either, it picks by list position
  the same way).
- **BanbeTheme** — the web app's light-mode paper/ink colors
  (src/index.css), so cards read the same on both.
- **Views** — `RootView` (auth gate + Face ID lock overlay), `LoginView`,
  `HomeView` + `EventRow` (photo card: hero photo, name, category ▪︎ area
  ▪︎ date, price/seats — mirrors the web feed card), `SettingsView` (Face
  ID toggle, sign out), `FaceIDLockView`.

## Face ID (for a returning, already-signed-in user)

Supabase's own client already persists a session across launches on its
own (Keychain-backed) — that part needed no new code. What's added here is
an **app-lock in front of that already-restored session**: turn it on from
Settings (the gear icon on Home) and the next cold launch shows
`FaceIDLockView` instead of the app content until Face ID succeeds
(`AuthViewModel.isLocked`, cleared by `BiometricAuthService.authenticate`).
It's off by default, persisted in `UserDefaults` (`banbe.faceIDEnabled`),
and has nothing to do with which Supabase credential (code or password)
originally created the session — it gates access to a device that's
already signed in, the same way it would for a banking or notes app.
`NSFaceIDUsageDescription` is set in `project.yml`.

## Why sign-in goes through the web app's API, not straight to Supabase

Requesting the code is a POST to `AppConfig.apiBaseURL +
"/api/auth/send-email-code"` (`AuthAPIService.requestEmailCode`) — the
exact same Vercel function the web app calls, which delivers via Gmail
with no meaningful limit. Calling Supabase's own `signInWithOTP` directly
(what an earlier version of this did) hits Supabase's own built-in mailer
instead, which on this project is capped at a handful of emails per hour
and fails almost immediately with "email rate limit exceeded" — a real
bug, not a hypothetical one. `AppConfig.apiBaseURL` is hardcoded to the
deployed origin (`https://banbe-two.vercel.app`, matching
`AUTH_REDIRECT_URL` in `.env.example`) since iOS has no origin of its own
the way the web app's relative `fetch('/api/...')` relies on — update it
if the app is deployed elsewhere.

Verifying the code is still a direct `supabase.auth.verifyOTP(email:
token: type:)` call — that only checks a token against Supabase, it
doesn't send anything, so it isn't subject to that limit and needs no
server round trip. `type` is `.signup` for a sign-up confirmation code or
`.email` for a login code, matching whichever mode (`AuthMode.login` /
`.signup`) the code was requested for — the screen now has the same
Log in/Sign up toggle (and a display-name field on Sign up) the web
Login screen has, rather than one flow that both created and signed in an
account.

There is deliberately no "sign in via link" option — an earlier version of
this screen requested one via `signInWithOTP(redirectTo: "banbe://login-
callback")`, but that URL scheme was never registered anywhere (no
`CFBundleURLTypes` in `project.yml`, no `onOpenURL` wired to it), so
tapping the emailed link did nothing. Sign-in here is code-entry only.

Password login/signup and "forgot password" (`api/auth/signup-password.js`,
`send-password-reset.js` on the web side) have no iOS equivalent yet —
future work, following the same AuthAPIService pattern.

## Not yet ported (only Home/Login exist so far)

The Home feed's card now looks like the web version (photo, name, meta
line, price/seats) but doesn't yet have: the language/area header row and
its "banbe ▪︎ Sài Gòn" area picker, the "Your events"/saved-events strip,
per-card Save toggle and "Going" chip, or category filter tabs — those all
need more state/RPCs wired up (favorites, area matching, etc.), not just a
visual pass.

Profile, Feed detail, Reserve/booking, Chat, Attendance/check-in
(camera QR scan), Notifications, Organizer/dashboard screens, and the
`claim_seats` / `check_in_guest` / `cancel_booking` / `undo_check_in` /
`confirm_payment` / `create_event_draft` / `set_organizer_mode` /
`rename_display_name` RPC calls the web app already makes. The Models and
SupabaseService here are meant to be the shared foundation for adding
those next, following the same ViewModel → SupabaseService.client pattern
used in HomeViewModel.

## SweetPad (VS Code)

`.vscode/settings.json` at the repo root points SweetPad at
`apps/ios/BanbeApp.xcodeproj/project.xcworkspace` / scheme `BanbeApp`.
That's the workspace bundle Xcode automatically creates *inside* every
`.xcodeproj` — SweetPad always builds with `xcodebuild -workspace`, which
rejects a bare `.xcodeproj` path ("is not a workspace file"), so this is
the path to use even though there's no separate top-level `.xcworkspace`
here. Since the `.xcodeproj` isn't committed, run `xcodegen generate`
(above) once after cloning — that also regenerates
`project.xcworkspace` — before SweetPad's build/run commands will find it.
Also see `.vscode/extensions.json` (recommends the `sweetpad.sweetpad`
extension).
