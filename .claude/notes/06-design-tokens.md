# Design tokens (source of truth: iOS `BanbeTheme.swift`/`Palette`)

## Canonical values

| Token | Light | Dark |
|---|---|---|
| paper (background) | `#F7F4EC` | `#14120E` |
| ink (text/ink) | `#1B1916` | `#F2EDE1` |
| ink-deep | `#0C0B09` | `#F2EDE1` |
| rule (divider) | `rgba(27,25,22,0.16)` | `rgba(242,237,225,0.20)` |
| field (input/card bg) | `#EEE8DA` | `#4A4439` |
| alert (accent, same both themes) | `#9A3E2D` | `#9A3E2D` |

Button (`--bb-button`/`--bb-button-text`) and glass-recipe surfaces
(`--bb-card`, `--bb-card2`, `--bb-white`, `--bb-shadow`) are web-only
compositing helpers (translucent gradients/blur) with no direct iOS
equivalent — iOS renders the same visual result with flat
`Color`+`RoundedRectangle` fills. Not diffed line-for-line; the underlying
`ink`/`paper`/`field` colors they're built from already match.

## Step 3 diff (as found, before this pass)

| Token | iOS (`BanbeTheme.swift`/`Palette`) | Web (`src/index.css`/`theme.js`, before fix) | Match? |
|---|---|---|---|
| Background (paper) | `#F7F4EC` (light) / `#14120E` (dark) | `--bb-bg` same values | **Yes** |
| Text (ink) | `#1B1916` / `#F2EDE1` | `--bb-fg` same values | **Yes** |
| Divider (rule) | `ink.opacity(0.16)` / `ink.opacity(0.20)` | `--bb-rule` same values | **Yes** |
| Field/card bg | `#EEE8DA` / `#4A4439` | `--bb-field` same values | **Yes** |
| Primary button (e.g. "Khách đúng ▪︎ cấp vé") | solid `palette.ink` | solid `ink` (`Action`/`actionButton` components) | **Yes** |
| Secondary/outline button ("Mở lại chỗ") | `Color.clear` fill + `palette.rule` stroke | `transparent` fill + `rule` stroke (`ghost` variant) | **Yes** |
| Accent/error (`alert`) | `#9A3E2D`, one named constant (`BanbeTheme.alert`) | `'#9A3E2D'` hardcoded as a literal string independently in **20 files** (Verifications, Disputes, DisputeChatPanel, PaymentDetails, Reserve, Login, Home, Account, Billing, Payout, Security, ResetPassword, EditName, CreateEvent, Attendance, QrScanSheet, ReasonSheet) — no shared export existed | **Values matched, structure did not** — real drift risk, now fixed |
| Inbox divider | `palette.rule` (all dividers use this) | `Inbox.jsx:18` hardcoded `#191919` (solid, opaque, ignores dark mode) | **No** — found bug, fixed |
| Corner radius: card/row | `14` (dispute rows, admin cards) | `cardGlass()`/`fieldGlass()` both fixed at `12` | Minor mismatch, **not changed this pass** (see below) |
| Corner radius: button | `12` (`AdminDashboardView`/`VerificationsView` action buttons) | `12` (`Action`/`actionButton` inline style) | **Yes** |
| Display/title font | System `.rounded` design, weight `.semibold` (iOS ships no custom font files) | `Jost`/`Be Vietnam Pro`, weight `600` | **No** — accepted platform gap, not "fixed" (see below) |
| Spacing scale | No formal token on either platform — ad-hoc literals (8/10/12/14/16/18/22px) used consistently on both sides already | same | **N/A**, no discrete scale to diff |

## What was changed (web only — `apps/ios` untouched)

1. **New shared token**: `--bb-alert: #9A3E2D` added to `src/index.css:22`
   (`:root` block only — same in both themes, matching `BanbeTheme.alert`
   being defined once, outside iOS's light/dark `Palette`). Exported as
   `alert` from `src/theme.js:12`.
2. **Every hardcoded `'#9A3E2D'` replaced with the `alert` import** (import
   line + literal, one `sed` pass each) in:
   `src/screens/Verifications.jsx`, `Security.jsx`, `ResetPassword.jsx`,
   `Reserve.jsx`, `Payout.jsx`, `PaymentDetails.jsx`, `Login.jsx`,
   `Home.jsx`, `EditName.jsx`, `Disputes.jsx`, `DisputeChatPanel.jsx`,
   `CreateEvent.jsx`, `Billing.jsx`, `Attendance.jsx`, `Account.jsx`,
   `sheets/QrScanSheet.jsx`, `sheets/ReasonSheet.jsx`.
3. **Real bug fixed**: `src/screens/Inbox.jsx:18` — thread-row divider was
   `1px solid #191919` (solid, opaque, ignores dark mode entirely) instead
   of the shared `rule` token every other divider in the app uses. Now
   `` `1px solid ${rule}` ``, imported at `Inbox.jsx:3`.

## Deliberately NOT changed this pass

- **Card/row corner radius** (iOS `14` vs web `cardGlass()`/`fieldGlass()`
  fixed at `12`): `cardGlass`/`fieldGlass` are shared by nearly every screen
  in the app, not just the dispute/admin screens this ticket named —
  changing their default radius would restyle the whole app's cards, well
  beyond "make colors match." Flagged here for a future, deliberate,
  broader-scoped pass if wanted.
- **Display font** (iOS: system rounded, no bundled font files; web:
  Jost/Be Vietnam Pro): iOS's own code comment (`BanbeTheme.swift:42-44`)
  already states this is "the closest stock match without shipping the
  fonts" — an acknowledged approximation, not a bug. Making web use system
  fonts to "match" would be a typographic regression on web, not a fix;
  the real fix (bundling the actual font files into the iOS target) is
  explicitly out of scope (`apps/ios` must not be touched).

## Verification

`vite build` clean; 75/75 Playwright tests pass. No visual/screenshot
diffing was run (no such tooling in this repo) — verification was
build-clean + a full repo grep confirming zero remaining hardcoded
`9A3E2D` literals outside `index.css`/`theme.js` themselves.
