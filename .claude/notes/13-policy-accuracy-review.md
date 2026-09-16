# Policy accuracy review — banbe_User_Policy.md vs. real code behavior (2026-09-16)

## Status: 10 factual corrections applied (web + iOS + source .md); 7 conflicts flagged, not auto-corrected

## What this was
Cross-checked every checkable factual/technical claim in `banbe_User_Policy.md` v1.0 against notes 05, 07, 08, 09, 10, 11 and a handful of targeted greps where those notes didn't cover a specific claim (e.g. confirming no message-purge cron and no account-deletion code path exist anywhere). Corrected the ten passages that were factually wrong or silently omitted something a user should be told; did **not** touch legal phrasing, tone, or invent new legal language anywhere. Full redline with a summary table and annotated "why" for each change: published as an Artifact (title "Policy Accuracy Redline").

## Files changed identically (three copies of the same text, kept in sync)
- `banbe_User_Policy.md` (repo root, the canonical source)
- `src/screens/Policy.jsx` (web renderer — duplicates the .md's text as JSX string props, does not render the .md file directly)
- `apps/ios/BanbeApp/Views/PolicyView.swift` (iOS renderer — same duplication pattern)

## The 10 corrections (see the redline artifact for full old/new text + code citations)
1. B2 — "we do not collect device location" was a direct contradiction: the app has requested/used real device GPS since before this ticket (feed's distance-from-you string, `LocationService.swift`/`GocContext.jsx`'s `userCoords`) and now also for the map's centering/nearby-sort (note 11). Corrected to state location is read only with permission, processed on-device, never sent to or stored on the server — confirmed by grep that `userCoords`/`Coordinates` never appear in any Supabase write on either platform.
2-4. B2 table — three new rows: invoices/receipts (08), Google/Facebook sign-in data (10), in-app notifications (07) — all real, populated data categories the policy never listed at all.
5. B3 — new paragraph disclosing when banbe emails automatically: dispute resolution always emails both parties (05); payment-document upload only if `profiles.auto_email_documents` is on, replacement always emails regardless (08).
6. B4 — new row: admin (including staff) cannot view invoices/receipts — confirmed via 08's own audit that no admin SELECT policy exists on `payment_documents`, checked twice (Task 1 and Task 7).
7. B5 — Google's processor role extended to cover OAuth sign-in, Meta/Facebook added (10) — previously only listed as an email sender.
8. B7 — the single "Chat: erased 12 months after event ends, unless disputed" row was wrong for both populations it was trying to describe: **ordinary chat has no automatic erasure anywhere in the code at all** (grepped every migration for a message-purge cron — none exists; only a real per-message user-delete from 07's 2026-09-17 Task B), and **dispute chat's real number is 72 hours after resolution**, not 12 months, and not self-deletable by the user at all (`dispute_threads.purge_after = resolved_at + 72h`, 04/05).
9-10. B7 — two new rows: invoice/receipt retention (12 months post-event, 24h for a superseded copy — 08's 2026-09-20 follow-up) and in-app notification retention (no auto-erasure, real user-delete — 07).

## The 7 flagged conflicts (not edited — need a legal or product decision)
1. **Most severe**: self-service + inactivity-based account deletion (A3/A8/B7/B8's central promise) does not exist anywhere in the codebase — no delete-account UI/RPC on either platform, no inactivity check, no scheduled deletion job. Confirmed by grepping both clients and every migration.
2. `POLICY_VERSION` (`src/lib/policy.js`) was never bumped when placeholder legal text was replaced with this real text (09's own open question, carried forward) — existing `policy_accepted_at` stamps may not reflect actual consent to this document.
3. A4/B2's "we keep no record of any money" is in tension with the real invoice/receipt upload feature (08) — banbe still never moves money, but a host-uploaded receipt is itself a durable record of what was charged.
4. A7's "staff read chats only on a report, a dispute, or a legal demand" — the "dispute" ground is real and verified; no explicit "report" feature was found anywhere.
5. B5's blanket "processes only on our instructions" framing may not correctly describe Google/Meta's role as independent OAuth identity providers — a data-protection classification question.
6. The dispute-resolution email's PDF transcript attachment is isolated in its own try/catch specifically so a render failure doesn't block the email (05) — the email always sends, but the PDF is not guaranteed, and this path is still unverified on the live Vercel runtime specifically. Correction #5 above was worded to promise only the confirmation email, not the attachment, to stay accurate regardless.
7. A3's whole account model assumes "your own verified phone number" as the identity anchor, but the real signup paths (email+password, emailed code, Google/Facebook OAuth) don't require or produce one at all; phone+OTP sign-in does call a real Supabase API, but B5's `[Vietnamese SMS provider]` bracket is still unfilled.

## Verification
`npx vite build --mode production` clean; iOS Debug + Release `xcodebuild` clean; fast Playwright suite (`--grep-invert "real backend"`, chromium) 92/92 pass — no test exercises Policy.jsx/PolicyView.swift's rendered text directly, so nothing needed updating there.
