// Undo after leaving a new-event draft (iOS AppState.createBack / CreateUndoToast parity).
//
// The draft's text fields live in BanBeContext state and survive leaving Create on their own (only
// startCreate resets them). What does not survive is CreateEvent's own local state: the staged photo
// Files, the cover and the current step. CreateEvent mirrors those here as they change; when the
// screen leaves 'create' with input, BanBeContext keeps that mirror as the "left" draft and shows the
// Undo toast. Undo hands it back to the next CreateEvent mount. Kept outside React state on purpose:
// it holds File objects and object URLs, and must not depend on effect order (StrictMode remounts).

export const CREATE_UNDO_MS = 6000;

let live = null;     // { items, coverKey, step, hasUnsavedInput } of the mounted CreateEvent
let left = null;     // the draft just left, held for Undo
let restore = null;  // handed to the next CreateEvent mount by Undo

const newUrls = (d) => (d?.items || []).filter(it => it.kind === 'new').map(it => it.url);

function revokeUnlessInUse(urls) {
  const keep = new Set([...newUrls(live), ...newUrls(left), ...newUrls(restore)]);
  urls.forEach(u => { if (!keep.has(u)) URL.revokeObjectURL(u); });
}

export function mirrorCreateDraft(draft) { live = draft; }

/** CreateEvent unmounted: free its photo URLs later, unless they are still held (Undo, or a StrictMode remount). */
export function releaseCreateDraft(items) {
  // `live` is left alone: BanBeContext reads it right after this unmount to hold the draft for Undo.
  const urls = (items || []).filter(it => it.kind === 'new').map(it => it.url);
  setTimeout(() => revokeUnlessInUse(urls), 2000);
}

/** The screen left 'create'. True when the draft had input and is now held for Undo. */
export function holdLeftCreateDraft() {
  const d = live;
  if (!d?.hasUnsavedInput) return false;
  discardLeftCreateDraft();
  left = d;
  return true;
}

/** Undo tapped: the held draft goes to the next CreateEvent mount. */
export function beginCreateDraftRestore() { restore = left; left = null; }

/** Read by CreateEvent's state initialisers (safe to call twice); cleared by its mount effect. */
export function peekCreateDraftRestore() { return restore; }
export function clearCreateDraftRestore() { restore = null; }

/** The toast ran out, or a fresh draft started: the held draft is gone for good. */
export function discardLeftCreateDraft() {
  const urls = newUrls(left);
  if (live === left) live = null;  // the stale mirror of that same left draft
  left = null;
  revokeUnlessInUse(urls);
}
