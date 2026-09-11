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
  `onAuthStateChange` handling), magic-link sign-in, profile load, and a
  Face ID app-lock (below).
- **BiometricAuthService** — thin `LocalAuthentication` wrapper used only
  for that app-lock, nothing more.
- **HomeViewModel** — fetches `events` where `status = 'live'`, same rows
  the web Home screen's "All" section reads via `events_select_public` RLS.
- **Views** — `RootView` (auth gate + Face ID lock overlay), `LoginView`,
  `HomeView` + `EventRow` (auth → fetch → render), `SettingsView` (Face ID
  toggle, sign out), `FaceIDLockView`.

## Face ID (for a returning, already-signed-in user)

Supabase's own client already persists a session across launches on its
own (Keychain-backed) — that part needed no new code. What's added here is
an **app-lock in front of that already-restored session**: turn it on from
Settings (the gear icon on Home) and the next cold launch shows
`FaceIDLockView` instead of the app content until Face ID succeeds
(`AuthViewModel.isLocked`, cleared by `BiometricAuthService.authenticate`).
It's off by default, persisted in `UserDefaults` (`banbe.faceIDEnabled`),
and has nothing to do with which Supabase credential (code, password, or
magic link) originally created the session — it gates access to a device
that's already signed in, the same way it would for a banking or notes
app. `NSFaceIDUsageDescription` is set in `project.yml`.

## Known gap: sign-in flow doesn't match the web app exactly

The web app has three sign-in methods (see the root README's auth
migration): an emailed 6-digit code (`api/auth/send-email-code.js`),
password login/signup with a "forgot password" recovery link
(`api/auth/signup-password.js`, `send-password-reset.js`), and a nickname
at sign-up. `AuthViewModel.sendMagicLink` instead uses Supabase's own
built-in `signInWithOTP` **magic-link** flow directly against the Supabase
Auth API — still a real session against the same `auth.users` table (an
account works across both apps), but the emailed template is Supabase's
default rather than the app's, there's no code/password choice, and no
nickname field at sign-up yet. Matching the web flow exactly here is
future work: point a rewritten sign-in view at those same three endpoints
instead (they need a reachable HTTPS URL for the deployed API, not
`localhost`), verifying with `supabase.auth.verifyOtp` for the code paths.

## Not yet ported (only Home/Login exist so far)

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
