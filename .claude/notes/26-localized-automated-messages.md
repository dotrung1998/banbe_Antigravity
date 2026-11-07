# Automated emails / notifications / system messages follow the language setting (2026-10-05)

## Status: PARTIALLY WORKING — JS + Swift translators unit-tested; the SQL migration (142) was NOT executed (no Postgres in the sandbox, only simulated with the same regexes in Python) — apply it and check it before relying on it.

What was actually true before: **emails** already followed `profiles.locale` (api/notify.js, api/auth, api/dispute-resolved-email.js; default `vi`), except the organizer's dispute email, which was hard-coded `vi`. **In-app notifications** were written in Vietnamese by ~50 SQL functions and shown as stored, so the language setting did nothing for them. **Chat system messages** were a mix of Vietnamese, English and bilingual ("vi / en") text, shown raw.

## What changed
- `api/dispute-resolved-email.js`: organizer email now uses the organizer's own `profiles.locale`.
- Migration 142 (`142_localized_notifications.sql`): `notifications.orig_title/orig_body` keep the Vietnamese original; a BEFORE INSERT trigger stores title/body in the recipient's locale; an AFTER UPDATE OF `profiles.locale` trigger re-localizes that user's existing notifications from the originals (so switching language, either way, switches what they already have). Table-driven: `notification_i18n_titles` (exact), `notification_i18n_body_rules` (ordered regex; names/amounts/codes captured and passed through), `notification_i18n_reasons` (fixed reason labels). No rule = left as written; the function swallows errors so it can never block an insert.
- Chat system messages are shared by two people, so they are translated at DISPLAY time, per viewer: `src/lib/systemMessageLocale.js` ↔ `apps/ios/BanbeApp/Lib/SystemMessageLocale.swift` (keep in step; tests on both sides). Wired into `Chat.jsx` and `MessagingViews.swift`. `classifySystemMessage` still reads the raw body.

## Adding a new automated message
- New notification written in SQL: add its Vietnamese title to `notification_i18n_titles` and its body pattern to `notification_i18n_body_rules` (new migration; do not edit 142 once applied), else English users get the Vietnamese text.
- New system chat wording: add it to BOTH `systemMessageLocale.js` and `SystemMessageLocale.swift`.

## Not covered
- Free text people typed (chat messages, free-text cancel reasons, `new_message`/`dispute_message` previews) is never translated.
- Telegram alerts to the ops group (`api/_lib/alerts.js`) stay Vietnamese on purpose.
- A host-written apology email (note 25) is drafted in the host's app language, not each guest's.
- No push is sent today (note 07), so nothing to localize there yet; it would read the same stored title/body.
