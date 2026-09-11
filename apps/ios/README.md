# banbe — iOS (SwiftUI)

A native SwiftUI client for the same Supabase project the web app
(the repo root) uses. Same tables, same RLS policies, same RPCs — this is
a second frontend, not a second backend.

## Structure (MVVM)

```
apps/ios/
  project.yml               # XcodeGen project definition — the source of
                            # truth; BanbeApp.xcodeproj is generated from it
                            # and is NOT committed (see .gitignore)
  Tools/generate-catalog.mjs # regenerates Resources/events.json from the
                            # web app's own src/data/events.js
  BanbeApp/
    App/BanbeApp.swift      # @main entry point
    Models/                 # Codable structs matching the Postgres schema,
                            # plus the shared event catalogue
    Services/               # Supabase client, auth API, biometrics, location
    State/                  # AppState — the port of GocContext
    Views/                  # the screens
    Resources/              # events.json + asset catalog
  BanbeAppUITests/          # XCUITest smoke suite (the Playwright analogue)
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

Build and test from the command line:

```bash
xcodebuild -project BanbeApp.xcodeproj -scheme BanbeApp \
  -destination 'generic/platform=iOS Simulator' build

xcodebuild test -project BanbeApp.xcodeproj -scheme BanbeApp \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Where the content comes from

The `events` table holds the rows that bookings, threads and check-ins
reference by id — but all the *presentation* detail (copy, photos,
galleries, organizer bios, greetings, price and seat labels) lives in the
web app's `src/data/events.js`, keyed by the same id. Rather than keep a
second hand-written copy that drifts, `Tools/generate-catalog.mjs` emits
`Resources/events.json` straight from it:

```bash
node apps/ios/Tools/generate-catalog.mjs   # after editing src/data/events.js
```

Photos are the same files the web app serves, shipped in the app bundle
as optimized derivatives — see **Photos** below.

## Screens

Every screen in `src/App.jsx`'s SCREENS map has a counterpart here, with
the same one-screen-at-a-time routing and explicit back targets:

| Web | iOS |
| --- | --- |
| Splash / LangPick / ThemePick | `OnboardingViews.swift` |
| Home | `HomeView.swift` (header, held-spot banner, "Your events" strip, filters, photo cards, save/going chips) |
| EventDetail | `EventDetailView.swift` (hero, Maps link, details, gallery, ticket-or-reserve bar) |
| Organizer | `OrganizerView.swift` |
| Reserve → Confirmed | `ReserveView.swift`, `ConfirmedView.swift` (real QR of the booking id) |
| Refunded | `RefundedView.swift` |
| Account / Preferences / EditName | `AccountView.swift`, `PreferencesView.swift` |
| Inbox / Chat / Notifications | `MessagingViews.swift` |
| Dashboard / HostIntro / CreateEvent | `DashboardView.swift`, `OnboardingViews.swift` |
| Attendance | `AttendanceView.swift` + `QRScannerView.swift` (AVFoundation) |
| Area / Location / Reason sheets | `Sheets.swift` |
| Login | `LoginView.swift` |

All of it talks to the same backend: `claim_seats`, `check_in_guest`,
`undo_check_in`, `cancel_booking`, `create_event_draft`,
`set_organizer_mode`, `rename_display_name`, the `threads`/`messages`
tables, and the `/api/notify-*` endpoints for the email side.

## Face ID (for a returning, already-signed-in user)

Supabase's own client already persists a session across launches
(Keychain-backed). What's added here is an **app-lock in front of that
restored session**: turn it on in Preferences and the next cold launch
shows `FaceIDLockView` until Face ID succeeds (`AuthViewModel.isLocked`,
cleared by `BiometricAuthService`). Off by default, stored in
`UserDefaults` (`banbe.faceIDEnabled`). It has nothing to do with which
credential created the session — it gates a device that's already signed
in. `NSFaceIDUsageDescription` is set in `project.yml`.

## Photos

The catalogue photos in `public/photos` are only 1000px wide but were
saved at very high JPEG quality — ~360KB each, 3-4x more than that
resolution needs. `Tools/optimize-photos.sh` re-encodes them to WebP at
q82 (visually indistinguishable, checked side by side) into
`public/photos/optimized`, which is **74% smaller overall: 20.8MB → 5.4MB**:

```bash
brew install webp
./apps/ios/Tools/optimize-photos.sh
```

Those derivatives ship *inside the app bundle*, for the same reason
`events.json` does — it's the same static catalogue — so the feed paints
from local files with no network round trip at all and works offline. A
cold launch went from photos trickling in over ~30s to everything visible
in about 3s.

`PhotoLoader` handles the rest: it downsamples while decoding (a 52pt
avatar no longer decodes a 1000px image at full size), keeps decoded
images in an `NSCache`, and for anything *not* bundled — a future
user-uploaded photo from storage — falls back to the network with a
256MB disk cache and a policy that doesn't re-validate on every scroll.
The lists that carry photos are `LazyVStack`/`LazyHStack`, so only the
cards actually on screen load anything.

The web app still serves the original JPEGs; it could point at
`/photos/optimized/*.webp` for the same saving whenever that's wanted.

## Logos

The app draws the web app's own artwork — `public/banbe-mark.png` and the
two wordmarks — referenced in place rather than copied, so both frontends
show the same mark. `BanbeLogo` renders them, at the same sizes the web
uses: the mark at 44pt on the language screen, the wordmark at 252pt on
the splash, the small wordmark at 126pt in the feed header, the mark at
34pt on the dashboard and 38pt in the host-intro card.

They're drawn as **template images tinted with the current ink colour**.
The artwork is near-black, which is right on the light paper but would be
invisible on the dark one — the web renders the PNG as-is and does lose
its logo in dark mode. Tinting keeps the design system's "one ink" rule
and is identical to the web in light mode.

### App icon

The springboard icon is `public/banbe-favicon.png` (the same mark), flattened
onto an opaque copy of the light-theme paper color and resized to exactly
1024×1024 — an app icon can't carry a transparent background (App Store
Connect rejects one that does; the favicon's is transparent outside its own
black square), so `banbe-icon.png` in `AppIcon.appiconset` is a baked, opaque
copy rather than the raw favicon. iOS applies its own rounded-corner mask on
top. Regenerate it if the favicon artwork ever changes:

```python
from PIL import Image
src = Image.open("public/banbe-favicon.png").convert("RGBA")
bg = Image.new("RGBA", src.size, (247, 244, 236, 255))  # #F7F4EC
bg.paste(src, (0, 0), src)
bg.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(
    "apps/ios/BanbeApp/Resources/Assets.xcassets/AppIcon.appiconset/banbe-icon.png"
)
```

## Known gaps

- **Sign-in is email-code only.** The web app also has password
  login/signup and a "forgot password" recovery link
  (`api/auth/signup-password.js`, `send-password-reset.js`); iOS requests
  its code from the same Gmail-backed `/api/auth/send-email-code` endpoint
  (Supabase's own mailer is rate-limited to a handful per hour) and
  verifies it with `supabase.auth.verifyOTP`. The Zalo/Facebook/Instagram
  and phone-OTP buttons on the web login screen aren't here either.
- **Light/dark follows the account; system appearance is ignored**, same
  as the web app.
- **Create-event photo upload** isn't wired (the web screen's photo slots
  are placeholders there too).

## Tests

`BanbeAppUITests` is the iOS counterpart of the web Playwright suite:
onboarding, feed → event → organizer navigation, category filtering, the
area sheet, account/preferences, language switching and the signed-out
sign-in prompt. Screens name themselves with a `screen.<name>`
accessibility identifier (see `RootView`) and controls carry stable ids,
the same way the web screens use `data-screen-label` / `data-testid` —
display copy is bilingual and would break the moment the language changes.

The signed-out test skips itself if the simulator happens to hold a
session, since sign-in needs a real emailed code.

## SweetPad (VS Code)

`.vscode/settings.json` at the repo root points SweetPad at
`apps/ios/BanbeApp.xcodeproj/project.xcworkspace` / scheme `BanbeApp`.
That's the workspace bundle Xcode creates *inside* every `.xcodeproj` —
SweetPad always builds with `xcodebuild -workspace`, which rejects a bare
`.xcodeproj` path. Since the `.xcodeproj` isn't committed, run
`xcodegen generate` once after cloning before SweetPad can find it. See
also `.vscode/extensions.json`.
