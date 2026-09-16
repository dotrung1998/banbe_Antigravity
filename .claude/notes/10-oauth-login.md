# Google/Facebook OAuth sign-in (2026-09-21)

## Status: WORKING (web + iOS)

## Task 1 — audit + consent-flow decision

**Existing auth surface** (`src/screens/Login.jsx`, `src/state/GocContext.jsx`, `apps/ios/BanbeApp/Views/LoginView.swift`, `apps/ios/BanbeApp/State/AppState.swift` + `ViewModels/AuthViewModel.swift`): email+password, emailed 6-digit code, phone OTP (web only, stub), Zalo/Facebook/Instagram buttons (all three were stubs saying "not available yet" — `GocContext.jsx:2205,2217,2218`). **iOS has no social buttons at all** — `LoginView.swift`'s own header comment says "The social buttons are still web-only."

**The consent mechanism (note 09) assumes a premise that OAuth breaks.** `GocContext.jsx`'s `syncUser()` (~line 445) auto-stamps `policy_accepted_at` unconditionally for any profile that doesn't have it yet, on the stated justification that "the ONLY way to ever reach a session at all now is through Login.jsx's mandatory, unticked-by-default consent checkbox." That's true for email/password/code sign-up (the checkbox gates `codeRequestSubmit`/`passwordSignupSubmit` before either ever runs). It is **not** true for OAuth: `supabase.auth.signInWithOAuth()` establishes a session directly from a provider redirect — no client-side submit function runs at all, so a brand-new Google/Facebook signup could reach `syncUser()` with no recorded consent and get auto-stamped anyway, without ever having ticked anything. This is exactly the gap Task 1 asked to find.

**Web complication**: `signInWithOAuth` does a **full-page redirect** away from the SPA and back (confirmed: no popup mode used anywhere in this codebase, and `src/lib/supabase.js`'s `detectSessionInUrl: true` is the standard full-redirect pattern). The whole React app remounts on return — any in-memory flag (`s.policyConsent`) is lost across that round trip. So checking `s.policyConsent` *after* the redirect, in `syncUser()`, is checking a value that has already reset to `initialState`'s `false`.

**iOS has no such gap**: `signInWithOAuth` on Apple platforms uses `ASWebAuthenticationSession` (confirmed in the SDK source, `supabase-swift/Sources/Auth/AuthClient.swift:839-870`) — a **modal sheet within the same process**, not a real navigation away from the app. `AppState`'s in-memory `policyConsent` survives the whole flow untouched, so it can be checked directly when the session comes back, no persistence trick needed.

**Decision**: 
- **Web**: stash proof-of-intent in `localStorage` (`banbe.pendingOAuthConsent`, mirroring the existing `REFERRAL_STORAGE_KEY` cross-redirect pattern already used for `?ref=` codes) *before* starting the redirect, only if `s.policyConsent` was true at click time. `syncUser()`'s auto-stamp block now branches on `user.app_metadata?.provider`: `'email'` (or absent, for pre-OAuth legacy rows) keeps the existing unconditional stamp; anything else (an OAuth provider) requires the stashed flag to be present — if it's missing, the session is signed back out and the user is bounced to Login with an error instead of silently granted an unconsented account. The flag is read once and cleared either way.
- **iOS**: no stash needed. `AppState.applySession()` (the profile-fetch step, iOS's equivalent of `syncUser()`) gets the identical branch, just checking `self.policyConsent` directly (still in memory) instead of a stashed flag.
- Both `signInWithGoogle()`/`signInWithFacebook()` (web) and their iOS equivalents refuse to start the OAuth flow at all unless `policyConsent` is already true — same as the existing signup-only gate on `codeRequestSubmit`/`passwordSignupSubmit`/`canRequest`, just applied unconditionally (both Login and Signup tabs) since OAuth can't be pre-classified as "definitely just a login" the way a password attempt against an existing account can.
- Consequence, disclosed rather than hidden: the consent checkbox now renders on **both** tabs (previously Signup-only, per note 09's fix) — but only the two OAuth buttons are gated on the Login tab; the existing email/password/code fields there are unaffected (still ungated, matching note 09's fix exactly).

**A second, pre-existing gap found while checking iOS for the equivalent mechanism**: iOS **never wrote `policy_accepted_at` at all**, on any path — grepped the whole iOS app, zero hits for `policy_accepted_at`/`policyAcceptedAt`. The checkbox (`app.policyConsent`) only ever gated the local `canRequest` computed property; nothing recorded consent server-side afterward. Any account created purely through the iOS app (no web visit ever) would have `policy_accepted_at` permanently NULL. Fixed as part of this pass (see Task 3) rather than leaving OAuth as the only path that records consent on iOS while password/code signup still silently doesn't.

## Task 2 — web (file:line)
- `src/state/GocContext.jsx` — `loginGoogle()`/`loginFacebook()` (new, replacing the old Facebook stub), consent-gated, stash `banbe.pendingOAuthConsent`, call `supabase.auth.signInWithOAuth({ provider, options: { redirectTo: getAuthRedirectUrl() } })`.
- `src/state/GocContext.jsx` `syncUser()` — OAuth-aware consent branch (see decision above).
- `src/screens/Login.jsx` — two new buttons, checkbox now renders on both tabs.
- No new callback route: this is a client-state SPA with no router (`src/App.jsx`'s `SCREENS` map); the existing `onAuthStateChange` listener + splash-timer + `postAuthDestination()` already cooperate to route a freshly-landed session correctly (this was the whole point of postAuthDestination's `!prev.sessionChecked` fix in note 09) — confirmed by reading that flow, not re-built.

## Task 3 — iOS (file:line)
- `apps/ios/BanbeApp/ViewModels/AuthViewModel.swift` — `signInWithGoogle()`/`signInWithFacebook()` (new), using `client.auth.signInWithOAuth(provider:redirectTo:)`.
- `redirectTo` reuses the **already-registered** `banbe://` URL scheme (`apps/ios/project.yml:84-86`, `Info.plist:21-31`) — added for the `banbe://organizer/<eventKey>` shared-link feature, not for auth. `LoginView.swift`'s own header comment ("no URL scheme was ever registered") is now stale — the scheme exists, just wasn't wired for this. **No Info.plist/project.yml change needed.** Note: the SDK's `ASWebAuthenticationSession`-based overload completes the flow internally via its own completion handler — it does **not** go through the app's existing `.onOpenURL { appState.handleDeepLink(url) }`, so no interaction with that deep-link handler at all.
- `apps/ios/BanbeApp/State/AppState+Data.swift` `applySession()` — new consent-recording block (the gap described above), OAuth-aware per the Task 1 decision.
- `apps/ios/BanbeApp/Views/LoginView.swift` — two new buttons (previously none on iOS at all).

## Task 4 — manual setup checklist (non-secret steps only, not fabricated)
This project's ref is `ukchdgdnwytretvqjjqu` (from `src/lib/supabase.js`'s fallback URL / `AppConfig.supabaseURL`).

**Supabase's own callback URL — same for both providers, paste into both consoles:**
```
https://ukchdgdnwytretvqjjqu.supabase.co/auth/v1/callback
```

1. **Google Cloud Console** (console.cloud.google.com → APIs & Services → Credentials):
   - Create OAuth 2.0 Client ID, type **Web application** (not iOS/Android — Supabase itself is the thing talking to Google, regardless of which client app the user is on).
   - Authorized redirect URI: `https://ukchdgdnwytretvqjjqu.supabase.co/auth/v1/callback` (exactly, no trailing slash).
   - Copy the generated Client ID and Client Secret (don't paste them anywhere in this repo).

2. **Meta for Developers** (developers.facebook.com → My Apps):
   - Create an app (type: Consumer, or "Authenticate and request data from users with Facebook Login").
   - Add the **Facebook Login** product.
   - Facebook Login → Settings → Valid OAuth Redirect URIs: `https://ukchdgdnwytretvqjjqu.supabase.co/auth/v1/callback`.
   - Copy the App ID and App Secret from Settings → Basic.

3. **Supabase Dashboard** (this project → Authentication → Providers):
   - Enable **Google**, paste the Client ID + Client Secret from step 1.
   - Enable **Facebook**, paste the App ID + App Secret from step 2.
   - Authentication → URL Configuration → Redirect URLs: add `banbe://login-callback` (the iOS custom-scheme callback — web needs no entry here beyond the site's own origin, which is normally already allow-listed as the Site URL).

Nothing above is a credential this session can generate — Client ID/Secret pairs only exist once you create the OAuth app in each console yourself.

## Implementation notes (file:line, added once actually built)

**Web:**
- `src/state/GocContext.jsx:21-27` `PENDING_OAUTH_CONSENT_KEY` constant + comment.
- `src/state/GocContext.jsx` `syncUser()`'s consent block (~line 453) — now branches on `user.app_metadata?.provider`; signs back out and shows an error (`reserveError`, deliberately a fixed bilingual string, not `T(...)` — this effect's deps are `[set]` only, so any `T` it closed over is frozen at mount-time `s.lang`, not the user's current choice) if an OAuth session has no `PENDING_OAUTH_CONSENT_KEY` proof.
- `src/state/GocContext.jsx` `startOAuth()`/`loginGoogle()`/`loginFacebook()` (replacing the old Facebook stub) — consent-gated, stash-then-redirect.
- `src/screens/Login.jsx` — new "Continue with Google" button (`data-testid="login-google"`), Facebook's existing button now wired to the real `loginFacebook` (`data-testid="login-facebook"`), consent checkbox block now `{!awaitingCode && (...)}` (was `&& isSignup`).
- `getAuthRedirectUrl()` (already existed, `src/lib/supabase.js`) reused for `redirectTo` — no new redirect-origin logic needed.

**iOS:**
- `apps/ios/BanbeApp/Models/Profile.swift` — added `policyAcceptedAt: Date?` (`policy_accepted_at`). This column was never in the iOS `Profile` model at all before this ticket.
- `apps/ios/BanbeApp/ViewModels/AuthViewModel.swift` — `signInWithGoogle()`/`signInWithFacebook()`, both calling a private `signIn(with: Provider)` using `client.auth.signInWithOAuth(provider:redirectTo:)` (the `ASWebAuthenticationSession`-presenting overload, confirmed via the checked-out SDK source rather than assumed).
- `apps/ios/BanbeApp/State/AppState+Data.swift` `applySession()` — new consent-recording block mirroring `syncUser()`'s, reading `session.user.appMetadata["provider"]?.stringValue` and (for a non-email provider) `policyConsent` directly rather than a stash, since the in-process modal sheet never tears down app memory. Signs out and bounces to `.login`/`authMandatory = true` on no proof, same as web.
- `apps/ios/BanbeApp/Views/LoginView.swift` — two new buttons (`oauthButton` helper + `startOAuth` gate), checkbox condition now `if !auth.codeSent` (was `&& mode == .signup`).
- No Info.plist/project.yml change: `banbe://` was already registered (`project.yml:84-86`) for the organizer-share deep link, confirmed reusable for `banbe://login-callback` without any new URL-type entry.

**Tests**: `tests/auth-notifications.spec.js`'s old "shows Facebook not available error" test rewritten as two — Facebook and Google both now real OAuth, so clicking either unticked shows the consent-gate message instead of the old "not available yet" stub. Full fast suite re-verified: 89 passed, 0 failed. Both iOS Debug and Release `xcodebuild` succeeded.

## Fixed: pre-redirect consent gate was fragile and regressed the Signup-only checkbox (2026-09-21)

**Regression reported**: the fix above put the checkbox back on the Login tab (to have somewhere to render for the OAuth buttons' consent gate) — undoing commit `2f90ecd`'s Signup-only fix, and — per the user's report — sometimes bounced a user back to Login right after they'd just accepted the policy, exactly matching the documented behavior above: if `PENDING_OAUTH_CONSENT_KEY`'s localStorage stash didn't survive the redirect (storage partitioning, a cleared/blocked store, or simply the timing of when the flag was read), `syncUser()` treated that as "no consent" and signed the session back out.

**Root cause of the fragility**: trying to verify consent *before* the redirect ever completes is inherently unreliable — the stash has to survive a real, opaque, external navigation with no guarantee it comes back intact. The fix moves the check to *after* the session lands, where the one thing that actually matters (`profiles.policy_accepted_at`) can just be read directly from the database — no stash, nothing to lose.

**New design**:
- Google/Facebook buttons are **not gated on consent at all** anymore, on either platform — a returning user reaches the provider with zero friction, same as password login (this was always true for password login; it just wasn't true for the OAuth buttons in the interim design above).
- `PENDING_OAUTH_CONSENT_KEY` and its whole stash/read/clear mechanism — removed entirely, not fixed. There's nothing left to lose across a redirect because nothing is stashed before one starts.
- `syncUser()` (web) / `applySession()` (iOS): for a session whose `user.app_metadata.provider` isn't `'email'`/absent AND whose profile has no `policy_accepted_at` yet, instead of requiring pre-redirect proof and signing out on its absence, this now sets a new `policyGateActive` flag and routes `screen` to `'policy'` — **without signing anyone out**. A *returning* OAuth user's profile already has `policy_accepted_at` set, so this whole branch never runs for them at all — same zero-friction path as password login.
- `Policy.jsx`/`PolicyView.swift` (the same "view the policy" screen from note 09, reused rather than building a new one) grow a second rendering mode, active only while `policyGateActive`: no back link (there's nowhere legitimate to go — the account already exists), and a persistent "I agree ▪︎ Continue" bar (web: `position: fixed` at the bottom; iOS: `.safeAreaInset(edge: .bottom)`, so it survives scrolling and doesn't need the reader to reach the end of a long bilingual legal document to find it).
- `acceptPolicyGate()` (new, both platforms) — stamps `policy_accepted_at`/`policy_version` for real, clears `policyGateActive`, then hands off to the exact same `postAuthDestination()` (web)/`postAuthDestination(isSignedIn:)` (iOS) every other sign-in path already uses, rather than inventing a bespoke "where does this land" decision.
- The checkbox itself: back to exactly note 09's Signup-only rendering on both platforms (`src/screens/Login.jsx`'s `{!awaitingCode && isSignup && (...)}`, `LoginView.swift`'s `if !auth.codeSent && mode == .signup`) — it no longer needs to appear on Login at all, since OAuth consent is handled entirely post-redirect now.

### file:line

**Web:**
- `src/screens/Login.jsx` — checkbox condition reverted to `{!awaitingCode && isSignup && (...)}`; Google/Facebook `onClick` handlers unchanged (call `loginGoogle`/`loginFacebook` directly — they were never gated at the JSX layer, only inside `startOAuth`, which is what changed).
- `src/state/GocContext.jsx` — `PENDING_OAUTH_CONSENT_KEY` constant removed; `startOAuth()` no longer checks `s.policyConsent` or touches `localStorage`; `syncUser()`'s consent block now sets `{ policyGateActive: true, screen: 'policy' }` instead of signing out, for a non-`'email'`-provider profile with no `policy_accepted_at`; new `acceptPolicyGate()` action (stamps consent, calls `postAuthDestination`).
- `src/screens/Policy.jsx` — `gateActive` (from `state.policyGateActive`) switches the header (no back link, a "read and agree" notice instead) and adds a `position: fixed` bottom bar (`data-testid="policy-gate-bar"`/`"policy-gate-accept"`) calling `acceptPolicyGate`.

**iOS:**
- `apps/ios/BanbeApp/Views/LoginView.swift` — removed the local `startOAuth(_:)` wrapper and its consent guard; buttons call `auth.signInWithGoogle()`/`signInWithFacebook()` directly; checkbox condition reverted to `if !auth.codeSent && mode == .signup`.
- `apps/ios/BanbeApp/State/AppState+Data.swift` `applySession()` — same branch change as `syncUser()`: sets `policyGateActive = true; screen = .policy` instead of signing out; the small `ConsentUpdate` struct (previously nested/duplicated) hoisted to file scope so `AppState.swift`'s new `acceptPolicyGate()` can reuse it too.
- `apps/ios/BanbeApp/State/AppState.swift` — new `@Published var policyGateActive`; new `acceptPolicyGate()` (stamps consent, calls the existing `private func postAuthDestination(isSignedIn:)`).
- `apps/ios/BanbeApp/Views/PolicyView.swift` — `gateActive` computed from `app.policyGateActive`; header conditionally hides the back button; `.safeAreaInset(edge: .bottom)` adds the "I agree ▪︎ Continue" bar, extracted into a `policyGateBar` computed property (needed to untangle a brace-counting mistake made while first wiring this up — see Errata).

### Errata while implementing
Restructuring `PolicyView.body` to add `.safeAreaInset` produced a real "Extraneous '}' at top level" build error from a miscounted closing brace (this file's original `ScreenScaffold { VStack { ... } modifiers }` had exactly two closing braces at the same indentation — one for `ScreenScaffold`'s trailing closure, one for `body` itself — and the new modifier needed to be chained between them, not after both). Fixed by extracting the bar into its own `policyGateBar` computed property, which also made the brace structure easier to verify by inspection going forward. Both Debug and Release `xcodebuild` succeeded afterward.

### Tests
`tests/auth-notifications.spec.js`'s two "requires consent before starting OAuth" tests (added by the regression) replaced with one confirming the checkbox is Signup-only again with both OAuth buttons visible on Login. New `tests/oauth-consent-e2e.spec.js` ("OAuth consent gate (real backend)", excluded from the fast suite the same way `dispute-flow-e2e.spec.js`/`notifications-toast.spec.js` are) — since no real Google/Facebook app is configured yet, this simulates exactly what a real OAuth sign-in produces: a real test account via the admin API, tagged with `app_metadata.provider` set to a non-`'email'` value (`admin.auth.admin.updateUserById`), then a fresh session minted (JWTs embed `app_metadata` at mint time, so the patch must happen before signing in) and loaded as real `storageState` — nothing about the consent gate itself is mocked, only the "came from a real OAuth redirect" part. Confirms: a returning user (`policy_accepted_at` pre-set) reaches Home directly with no Policy screen and no bounce to Login; a brand-new signup hits the Policy gate exactly once, accepting stamps `policy_accepted_at` for real and continues to Home, and a reload afterward never shows the gate again. Both pass. Full fast suite re-verified: 88 passed, 0 failed (back to the pre-regression baseline, plus the checkbox-placement test replacing the two removed ones).
