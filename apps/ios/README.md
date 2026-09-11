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
  `onAuthStateChange` handling), magic-link sign-in, profile load.
- **HomeViewModel** — fetches `events` where `status = 'live'`, same rows
  the web Home screen's "All" section reads via `events_select_public` RLS.
- **Views** — `RootView` (auth gate), `LoginView`, `HomeView` + `EventRow`
  as one working end-to-end example (auth → fetch → render).

## Known gap: sign-in flow doesn't match the web app exactly

The web app posts to a custom `/api/auth/send-email-link` Vercel function
(see `api/auth/send-email-link.js`) so it can send a branded email and
attach a nickname at sign-up. `AuthViewModel.sendMagicLink` instead uses
Supabase's own built-in `signInWithOTP` magic-link flow directly against
the Supabase Auth API. Both produce a real session against the same
`auth.users` table, so an account works across both apps — but the iOS
email will look different (Supabase's default template, not the app's),
and there's no nickname field wired into iOS sign-up yet. If matching the
web email exactly matters, point `sendMagicLink` at that same
`/api/auth/send-email-link` endpoint instead (it needs a reachable HTTPS
URL for the deployed API, not `localhost`).

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
