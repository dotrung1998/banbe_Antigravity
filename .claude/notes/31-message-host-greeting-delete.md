# 31 — Message host: opening message, lazy threads, inbox delete (web)

Status: IMPLEMENTED (web), build passes; NOT exercised against a DB with migration 156. iOS done separately.
Migration `20261207000156_156_chat_greeting_and_thread_delete.sql` (`events.chat_greeting` <=500, `thread_preferences.deleted_at`) MUST be applied via `supabase db push`. Code degrades without it.

## What changed
- Host name: Chat header/composer/"Message X"/Refunded use organizer name (`ev.orgName`/`chatOtherName`), never `hostShort`. `openThread()` now resolves the other party's name itself (organizer name for a guest, profile display name for an organizer) when the caller (notification tap) passes none.
- Opening message: Create/Edit Event textarea (`createChatGreeting`, max 500) -> `events.chat_greeting` via a best-effort owner update after the RPCs in `createSubmit` (blank on edit clears it). `shapeRealEvent.chatGreeting`, `shapeRealEventAsCurEvent.greeting`. Chat shows `s.chatGreeting` as a first host bubble (display only, no id, no delete). Catalogue events fall back to their hardcoded `greeting`. Shown for guests only (openChatFor/openThread-as-guest).
- Lazy threads: `openChatFor` only looks up an existing thread; otherwise `chatDraftOrganizerId` is set (draft). `ensureChatThread()` inserts the row at first send (`chatSend`, `sendChatAttachment`; race retry kept, in-flight promise shared via `chatThreadCreateRef`). `loadInboxThreads` hides zero-message threads.
- Delete: Inbox row menu (the "..." reveals Star/Archive/Delete) + confirm sheet; `deleteThreadForMe` upserts `thread_preferences.deleted_at` (= last message time, skew-safe), optimistic. `loadInboxThreads` and the dock unread poll hide a thread while `last message <= deleted_at`.
- Missing-column handling: `withR2Columns` (src/lib/mediaUrls.js) now also flips `isChatGreetingColumnMissing()` on a `chat_greeting` error and retries; `realEventColumns` includes `chat_greeting` unless flagged; `fetchThreadPrefRows` retries without `deleted_at`. Without the column, delete warns and restores the row.

## Caveats
- `deleted_at` is never cleared (reappearance is purely timestamp-based).
- Dashboard.jsx still uses `findEvent(myOrgEventKeys[0])` (not chat related).
- Tests that click "Message <hostShort>" text or expect an auto-created thread / greeting for real events may need rework.

## Update: bilingual greeting (migration 157)
- Migration `20261207000157_157_backfill_chat_greetings.sql` adds `events.chat_greeting_en` and backfills varied vi/en greetings. Also needs `supabase db push`.
- Create/Edit Event has two textareas (Vietnamese -> `chat_greeting`, English -> `chat_greeting_en`, 500 each, blank clears). Both carried by `shapeRealEvent` (`chatGreeting`, `chatGreetingEn`) and `realEventColumns`.
- Chat display (`src/lib/chatGreeting.js`): app language's text, else the other language, else a built-in localized default picked by string hash of the event key % 5 (only variant 0 names the organizer). Catalogue events no longer use their hardcoded Vietnamese `greeting` (it can't be localized) unless the DB row has one. `chatGreetingFor` gates it to the guest side.
- `withR2Columns` tolerates a missing `chat_greeting` and/or `chat_greeting_en` independently (`chatGreetingColumnList()`); the save retries without the EN column if only 156 is applied.
