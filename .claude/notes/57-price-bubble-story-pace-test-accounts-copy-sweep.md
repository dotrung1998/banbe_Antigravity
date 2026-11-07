# 57 — Price slider bubble, slower "How banbe works", Test Accounts (bottom button, admin delete), copy sweep

**Status:** IMPLEMENTED LOCALLY (web + iOS + `api/auth`), not committed. No migration.
Source: the owner's iPhone screenshots (2026-10-22) and 4 requests.

## 1. Price slider jumped right while dragging (iOS)
- **Root cause.** `PriceMarketView` (`Views/RecipeSheet.swift`) drew the "770kđ" value bubble inside the slider's
  `ZStack(alignment: .topLeading)` with `.alignmentGuide(.leading) { $0.width / 2 }`. That widened the stack by half
  the bubble's width. The stack was framed `.topLeading`, so the whole slider (bars, track, knob) shifted right as
  soon as the bubble appeared.
- **Fix.** The bubble now lives in an `.overlay(alignment: .topLeading)` and is placed with `.position(...)`, so it
  never takes part in layout. Its centre is clamped to 30pt from each edge.
- Web was not affected: it uses a native range input.

## 2. "How banbe works" entrance slowed again (web + iOS)
- **Tile:** 1.1s, starts after 0.2s.
- **Points:** 1.0s each, starting at 0.7s and then 0.35s apart.
- Same easeOutQuint curve, no bounce.
- **Files:** iOS `StoryPointsView` (`WelcomeView.swift`); web `.bb-story-pop` / `.bb-story-rise` in `index.css` plus
  the row delays in `Welcome.jsx`.

## 3. Admin › Test Accounts
- **Capitalised:** "Test Accounts" / "Tài Khoản Thử Nghiệm", in both the title and the Review & Moderation row (web
  + iOS).
- **"Find account" pinned to the very bottom.**
  - iOS: `.safeAreaInset(edge: .bottom)`.
  - Web: a sticky footer in a flex column.
  - Return/Enter in the email field also searches.
- **TESTING PHASE: "Delete account" on the found account card** (hidden for admins).
  - The confirmation names the email and says the deletion can't be undone.
  - Server: `/api/auth` `type: 'admin_delete_account'`, body `{ userId }`.
  - The caller must have `profiles.role = 'admin'`.
  - Refusals:
    - yourself: `INVALID_TARGET`
    - another admin: `TARGET_IS_ADMIN`
    - not a UUID: `INVALID_VALUE`
    - unknown user: `USER_NOT_FOUND`
    - owns a live or in-review event: `ACCOUNT_DELETION_BLOCKED_OPEN_EVENT`, with the list of events
  - An `admin_action_log` row (`user_deleted`, `target_email`, `meta`) is written BEFORE anything is deleted.
  - The deletion then runs the same workflow as self-service deletion. `handleDeleteAccount` was split into
    `checkDeletionAllowed` and `performAccountDeletion`, and both handlers use them. Tracking rows get
    `reason_code = 'admin_deleted'`.
  - The email is reusable afterwards (`email_registrations.auth_user_id` is `ON DELETE SET NULL`).
  - The iOS call lives in `AdminTestAccountsView` itself.
- **Verified against the LOCAL Supabase stack** (scratchpad scripts, not in the repo): 12/12 checks.
  - non-admin refused; self refused; admin target refused; bad id refused; host with an open event refused
  - success, then: auth user gone, profile gone, registry unlinked, log row written, tracking row `done`, and the
    same email can sign up again
  - The self-service `delete_account` still works after the refactor.
  - The local DB was missing 189's `admin_action_log.meta` column, so it was added there by hand.
- **Before public release, remove:** the handler and its dispatch branch in `api/auth/index.js`, the Delete UI on
  both platforms, and the admin guide's "Deleting a test account" block. Or put it behind a feature switch.

## 4. Copy sweep: no "—", "–", " - " or ";" joining ideas in user-visible text
- **Scope:** web `src/**`, iOS `apps/ios/BanbeApp/**`, the help guides and Q&A (regenerated `HelpContent.swift`),
  and the iOS demo data `Resources/events.json` (copied from the web `src/data/events.js`).
- **Rule:**
  - a period between full sentences, with a capital after it ("banbe" stays lowercase);
  - a comma for fragments and short lists;
  - kept: ranges (1–3, 700k–900k), hyphenated words, lone "—" empty-value placeholders, "·" / "▪︎", and dashes in
    data such as bank details copied to the clipboard.
  - The Terms (`Policy.jsx` / `PolicyView`) got punctuation-only changes. `POLICY_VERSION` was NOT bumped.
- **Wording that must stay identical across web, iOS and the guides:**
  - the Manage events blocker lines, now comma-joined: "1 active booking, the host must cancel the event"
  - "Never booked, can be deleted permanently."
  - "Wipe permanently, testing (N)"
  - "Step 1. Verify it's you"
  - "ON. Nobody has to verify by SMS."
- **NOT changed (needs follow-up):**
  - Text the DATABASE writes (notification titles and bodies, system chat messages) still contains dashes, e.g.
    "— chỗ của bạn vẫn được giữ". Changing it needs a migration.
  - The clients' VI match patterns in `systemMessageLocale.js` / `SystemMessageLocale.swift` must change together
    with that migration. Only their EN output was changed.
  - `SecurityView` capitalises "Banbe" at the start of one sentence.
- **Verified:**
  - web `npm run test:unit` 338/338 (`adminEvents.test.mjs` updated to the comma wording), `vite build`, guide
    structure check
  - iOS: see the final report of this pass.
