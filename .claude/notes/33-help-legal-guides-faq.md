# 33 — Help & Legal: Terms, Guides, Q&A (web + iOS)

Status: IMPLEMENTED (web + iOS). iOS builds (xcodebuild, simulator) but was not run/UI-tested. `tests/help-legal.spec.js` written but NOT run green: `setupToHome` times out in this environment (existing specs fail identically), so only `vite build` is verified.

- Account "Help & Legal" row now opens `accountGroup` key `helpLegal` (AccountGroup.jsx): Terms (-> Policy screen), Guide: Personal, Guide: Host, Q&A.
- Screens `guide` (`/help/guides/:personal|host|admin`) and `faq` (`/help/faq`), both rendered by `src/screens/HelpReader.jsx` (clickable TOC, jump top/bottom, diacritic-insensitive search with highlight).
- Content is bilingual data in `src/data/help/` (block format documented in HelpReader.jsx). Update it when behaviour changes.
- Content deliberately avoids unverified/conflicting claims (review turnaround time, "3-5 business days", Wallet, push, age enforcement). Re-check before adding them.
- Admin guide is gated by `accountType === 'admin'` in Guide.jsx.
- iOS: `HelpReaderView.swift` (+ `HelpGuideView`/`HelpFaqView`), screens `.helpGuide`/`.helpFaq`, group key `helpLegal` in AccountGroupView. Content is GENERATED: after editing `src/data/help/*.js` run `node scripts/gen-help-content-ios.mjs` to refresh `apps/ios/BanbeApp/Models/HelpContent.swift`.
- Admin guide is NOT in Help & Legal: it is an "Admin Guide" row on the Admin tab (web + iOS), back returns to Account.
- Fixed a pre-existing blank-page crash: declinePolicyGate used `logout` in its deps before its declaration (TDZ) — keep it defined after logout.

## 2026-10-10 iOS: Contents (TOC) rows barely tappable

Symptom: on iOS, tapping Contents items in a guide didn't jump to the section. Root cause (reproduced on a
simulator, in a harness with the app's edge-swipe/animation environment): each TOC row is a
`Button` with `.buttonStyle(.plain)` whose label was just the underlined `Text`, so only the glyphs were
hit-testable. A fingertip beside/between words or right of a short title (e.g. "8. Hoàn tiền") hit nothing
— the scroll code itself (`ScrollViewReader.scrollTo("sec-…", anchor: .top)`) was fine; tapping the exact
text worked. Fix (`HelpReaderView.swift` `toc(_:)`): label is `.frame(maxWidth: .infinity, alignment: .leading)`
+ `.contentShape(Rectangle())`, so the whole row is the target (the Contents header already had a
contentShape). Verified the same empty-space tap now scrolls the section to the top. Web unaffected (reported
iOS only). Not re-verified on a physical device.

## 2026-10-22: all three guides brought up to date (notes 34–56)
- Rewritten from code-verified findings (exact EN/VI labels grepped in `src/` and the iOS app):
  - **Personal:** guest browsing + Welcome + "How banbe works", Facebook greyed out, new `onboarding`, rebuilt `browse` (search bar, Pulse ticker, filters/sort/quick chips, Next up, Search screen, For You on Map), new `event` page layout + "Who can reserve", new `schedule`, sticky reserve bar, "can't find it" 2-day chat, host announcements, notifications via bell/Account, following, `rewards` (worded "when banbe turns it on"), `reports`, Delete account "Before you go" + date-of-birth check.
  - **Host:** 5-step create flow, smart defaults, recipe, criteria, review tabs, Dashboard sections + "Removed by banbe", "Past events" excludes cancelled (refunds → Refund Center), new `announce`, reports redesign.
  - **Admin:** new `manage` (incl. the iOS testing-phase wipe), `features`, "Bypass SMS for everyone", the per-blocker wording from the note 54 follow-up, and the admin reports view.
- Remote check (2026-10-22, read-only via the REST OpenAPI): migrations 162/165/166/181/186/187/188/189 ARE applied, despite those notes saying "not applied". `rewards` flag is OFF; `phone_bypass_all` is ON.
- Section id `refund` is kept: `tests/help-legal.spec.js` clicks `guide-personal-toc-refund`.
- Q&A: one line fixed (Notifications tab → bell/Account). The rest of the Q&A was not reviewed.
- Verified: structure check, `npm run test:unit` 338/338, `vite build`, iOS build. `tests/help-legal.spec.js` still fails at `setupToHome` (test account DOB gate), before any guide opens.
- When the TESTING-PHASE wipe is removed (note 54 checklist), also delete the admin guide's "Test event wipe" subsection and its Feature switches bullet, then regenerate.
