# Mandatory login + policy consent + splash-before-login (Task 1/2, commit 3ee304b)

## Status: WORKING (web + iOS), fast Playwright suite stabilized in 8cbaa78

## What changed
- No guest/anonymous browsing of any screen — Home, Event, Account, disputes, etc. all require a session. A guest visitor lands on the mandatory Login screen instead.
- Login/sign-up requires ticking an unchecked "Tôi đồng ý với Điều khoản sử dụng và Thông báo quyền riêng tư" consent checkbox before submit is allowed.
- Consent is recorded once per account: `profiles.policy_accepted_at` (timestamptz) + `profiles.policy_version` (text).
- Splash now always shows (~2.6s) on cold launch/reopen, including for returning users — previously skipped straight to Home for anyone with saved preferences. Shows before Login *and* before iOS's FaceID lock prompt.

## Files / functions
- `supabase/migrations/20260918000055_055_policy_consent_columns.sql` — adds `profiles.policy_accepted_at`, `profiles.policy_version`. No new RLS needed; `profiles_update_own` (001_core_schema.sql:111) already scopes writes to these columns.
- `src/lib/policy.js` `POLICY_VERSION` — the version string stamped into `policy_version` at consent time. Bumping it does **not** by itself force re-consent for already-consented users (see below) — it's bookkeeping, not a gate.
- `src/state/GocContext.jsx:52` `GUEST_ALLOWED_SCREENS` — the only screens reachable signed-out: `splash`, `langPick`, `themePick`, `login`, `resetPassword`, `policy`.
- `src/state/GocContext.jsx` blanket guard `useEffect` (watches `sessionChecked`/`user`/`screen`) — the single enforcement point for "no guest browsing of any screen"; catches call sites like `goHome()`/`logout()` that don't otherwise check auth. Waits for `sessionChecked` so a slow session restore isn't misread as signed-out.
- `src/state/GocContext.jsx` `postAuthDestination(prev)` — decides `'home'` vs. forced `'login'` after splash/onboarding finishes. Treats `!prev.sessionChecked` the same as `prev.user` truthy (optimistically goes to the target screen) rather than assuming signed-out — the async session/profile fetch can still be in flight when this runs, and deciding "signed out" prematurely was a real bug (see Errata below), not just test flakiness.
- `src/screens/Login.jsx` — consent checkbox (`data-testid="login-policy-consent"`), link to Policy screen (`data-testid="login-policy-link"`); `codeRequestSubmit`/`passwordSignupSubmit`/`passwordLoginSubmit` all gate on `s.policyConsent` first.
- `src/screens/Policy.jsx` — full bilingual policy text (see below), reads `POLICY_VERSION`.
- iOS mirrors: `AppState.swift` (`authMandatory`, `policyConsent`, `guestAllowedScreens`, `postAuthDestination(isSignedIn:)`, `dismissSplash(isSignedIn:)`), `AppState+Data.swift` `signOut()`, `Views/RootView.swift` (blanket guard `.onChange(of: app.screen)`, FaceID lock gated `&& app.screen != .splash`), `Views/LoginView.swift` (checkbox, `canRequest` gate), `Views/PolicyView.swift`, `Views/OnboardingViews.swift` (`SplashView`/`ThemePickView` call sites).

## Policy document (2026-09-19 follow-up)
`banbe_User_Policy.md` (repo root) is the canonical source, supplied directly by the user — v1.0, bilingual (Vietnamese prevails per its own A1). `src/screens/Policy.jsx` and `apps/ios/BanbeApp/Views/PolicyView.swift` render its full text (not paraphrased/shortened): summary + numbered list, consent checkbox text, Part A (A1-A8), Part B (B1-B12) including the B2/B4/B7 tables, contact block. `POLICY_VERSION` is still `'2026-09-18'` (the placeholder-content version) — **not yet bumped** to reflect the real text; see the recommendation below before changing it.

Bracketed placeholders in the source doc itself ([effective date], [registered address], [enterprise code], [contact email], [Vietnamese SMS provider], "CÓMPANY") are rendered verbatim — those are the legal team's blanks to fill in, not something to invent here.

### Version-bump recommendation (open question, not yet decided)
Whether replacing placeholder wording with the real policy text should count as a new `POLICY_VERSION` — which would need a re-consent flow, since existing `profiles.policy_accepted_at` rows (incl. the shared fast-suite test account) currently point at consent to the placeholder text, not this real text — was raised back to the user rather than decided unilaterally, since it affects existing consent records. No re-consent mechanism exists yet either way (bumping the constant alone does not re-prompt anyone, per `src/lib/policy.js`'s own comment).

## Errata found while stabilizing the fast Playwright suite (commit 8cbaa78)
- `Locator.isVisible({ timeout })` is deprecated/ignored in this Playwright version (never actually waits) — `tests/helpers.js`'s `setupToHome()` used it to probe onboarding screens, which was really an instant, racy DOM check. Fixed with real `waitForSelector`-based waits.
- The actual app bug (not just a test issue): `postAuthDestination` originally decided Home-vs-Login from `prev.user` alone, which can still be `null` while `syncUser`'s async profile fetch is in flight — a fast click through langPick→themePick could race ahead of it and wrongly force an *already signed-in* account to Login. Fixed as described above.
- A shared `"?org="` link's fast-open-to-Organizer behavior (bypassing splash/onboarding) was lost when Task 2 made `screen` always start at `'splash'` — restored as a special case in the `useState` initializer.
- `tests/global-setup.js` resets the shared fast-suite account's `profiles.role` to `'participant'` every run — it had drifted to `'organizer'` outside any test run and silently broke "goer" test assertions.

## TODO / open questions
- Real legal text still has unresolved brackets ([effective date] etc.) — company will need to fill these in before this is truly final, independent of the version-bump question above.
- No re-consent flow exists for a policy version bump. If the version-bump question above is answered "yes," building that flow is separate follow-up work.

## Fixed: consent checkbox was gating Login too, not just Signup (2026-09-16)
Bug: the checkbox/gate applied to BOTH `authMode`s. Only Signup creates a
brand-new profile with `policy_accepted_at` still NULL; a returning account
signing back in already has that column set from its own signup, so
requiring the tick again on Login was wrong (and blocked login entirely
until it was checked, mirroring a box that no longer even needs to be
there).

- `src/screens/Login.jsx:21-28` — new `consentOk = !isSignup || s.policyConsent`, used in place of the bare `s.policyConsent` in `valid`'s two branches.
- `src/screens/Login.jsx:138` — checkbox block now `{!awaitingCode && isSignup && (...)}` (was `{!awaitingCode && (...)}`).
- `src/state/GocContext.jsx:1995-2001` `codeRequestSubmit` — guard changed to `if (s.authMode === 'signup' && !s.policyConsent) return;` (handles both Login and Signup's email-code request).
- `src/state/GocContext.jsx:2018-2019` `passwordSignupSubmit` — unchanged, still always gated (signup-only function).
- `src/state/GocContext.jsx:2038-2039` `passwordLoginSubmit` — `if (!s.policyConsent) return;` removed entirely (login-only function, never gated).
- `apps/ios/BanbeApp/Views/LoginView.swift:43-49` `canRequest` — guard changed to `if mode == .signup && !app.policyConsent { return false }`.
- `apps/ios/BanbeApp/Views/LoginView.swift:159` checkbox block now `if !auth.codeSent && mode == .signup { ... }` (was `if !auth.codeSent`).
- `apps/ios/BanbeApp/State/AppState.swift:135` — `policyConsent` property itself unchanged; all gating logic lives in `LoginView.canRequest`, not in AppState.

No change to `syncUser()`'s existing auto-stamp (`GocContext.jsx` ~line 428: writes `policy_accepted_at`/`policy_version` for any profile missing it on sign-in) — that's separate bookkeeping for legacy accounts predating this column and is unaffected by where the checkbox itself renders.

Tests updated in `tests/auth-notifications.spec.js`: `openLogin()` no longer ticks the checkbox unconditionally (it doesn't exist on the default Login tab anymore); a new `consentToSignup(page)` helper is called instead, right after each test's `Đăng ký` tab switch, before any actual signup submit. `tests/auth-and-booking.spec.js`'s tab-switch test needed no change (never submits). Full fast suite re-run: 88 passed, 0 failed.
