// Supabase-aware wrappers over mediaResolver for event photos, covers and
// organizer avatars, plus the shared "column may not exist yet" select retry
// (migration 153 adds r2_ref / cover_r2_ref / avatar_r2_ref).
import { supabase } from './supabase.js';
import { resolveMediaUrl, isR2Ref } from './mediaResolver.js';

/** A legacy column may itself hold a ref (R2-only uploads write storage_path = ref). */
function pickRef(r2Ref, legacyPath) {
  return r2Ref || (isR2Ref(legacyPath) ? legacyPath : null);
}

/** Synchronous public URL of an event photo/cover. Null for private-bucket paths. */
export function publicEventPhotoUrl(storagePath, r2Ref, variant = 'card') {
  const legacy = !storagePath || isR2Ref(storagePath) || storagePath.startsWith('event-photos-private/')
    ? null
    : supabase.storage.from('event-photos').getPublicUrl(storagePath.replace(/^event-photos\//, '')).data.publicUrl;
  return resolveMediaUrl({ r2Ref: pickRef(r2Ref, storagePath), legacyUrl: legacy, variant }) || null;
}

/** Public URL of an organizer avatar ('' when none). */
export function organizerAvatarPublicUrl(avatarPath, r2Ref, variant = 'card') {
  const legacy = !avatarPath || isR2Ref(avatarPath)
    ? null
    : supabase.storage.from('organizer-photos').getPublicUrl(avatarPath).data.publicUrl;
  return resolveMediaUrl({ r2Ref: pickRef(r2Ref, avatarPath), legacyUrl: legacy, variant }) || '';
}

export function isMissingColumnError(error) {
  if (!error) return false;
  return error.code === '42703' || /column .* does not exist/i.test(error.message || '');
}

let r2ColumnsMissing = false;
// `events.chat_greeting` (migration 156) and `chat_greeting_en` (157) — same
// degrade-gracefully idea as the r2 columns, tracked separately so a DB that
// has some migrations but not others keeps whichever columns it does have.
let chatGreetingColumnMissing = false;
let chatGreetingEnColumnMissing = false;
export const isChatGreetingColumnMissing = () => chatGreetingColumnMissing;
/** The greeting columns the DB is known (or not yet known) to have. */
export const chatGreetingColumnList = () => [
  ...(chatGreetingColumnMissing ? [] : ['chat_greeting']),
  ...(chatGreetingColumnMissing || chatGreetingEnColumnMissing ? [] : ['chat_greeting_en']),
];

/**
 * Runs `build(withR2)` (returns a thenable PostgREST query). First tries with
 * the new r2 columns; if the DB does not have them yet, retries once without
 * and remembers that for the rest of the session. An error naming
 * `chat_greeting`/`chat_greeting_en` flips only that flag (callers read it
 * through chatGreetingColumnList() when building their column list).
 */
export async function withR2Columns(build) {
  let res;
  for (let attempt = 0; attempt < 4; attempt++) {
    res = await build(!r2ColumnsMissing);
    if (!isMissingColumnError(res?.error)) return res;
    const msg = res.error.message || '';
    if (/chat_greeting_en/i.test(msg) && !chatGreetingEnColumnMissing) { chatGreetingEnColumnMissing = true; continue; }
    if (/chat_greeting/i.test(msg) && !/chat_greeting_en/i.test(msg) && !chatGreetingColumnMissing) { chatGreetingColumnMissing = true; continue; }
    if (r2ColumnsMissing) return res;
    r2ColumnsMissing = true;
  }
  return res;
}
