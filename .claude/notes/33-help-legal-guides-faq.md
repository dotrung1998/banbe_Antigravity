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
