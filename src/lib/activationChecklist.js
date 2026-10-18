// Home "Get started with banbe" checklist — web mirror of iOS `Lib/ActivationChecklist.swift` (note 43).
// Switched on only after someone answers the onboarding questions; this browser only, per account.
// Web has no Face ID, so the items are: open an event, save an event.

export const CHECKLIST_ITEMS = ['openEvent', 'saveEvent'];

const key = (uid) => `banbe.activation.v1.${uid}`;
const storageOrNull = () => (typeof localStorage !== 'undefined' ? localStorage : null);
const EMPTY = Object.freeze({ enabled: false, dismissed: false, openedEvent: false });

export function loadChecklist(uid, storage = storageOrNull()) {
  if (!uid || !storage) return { ...EMPTY };
  try {
    const v = JSON.parse(storage.getItem(key(uid)) || 'null');
    return v && typeof v === 'object' ? { ...EMPTY, ...v } : { ...EMPTY };
  } catch { return { ...EMPTY }; }
}

export function saveChecklist(state, uid, storage = storageOrNull()) {
  if (!uid || !storage) return;
  try { storage.setItem(key(uid), JSON.stringify({ enabled: !!state.enabled, dismissed: !!state.dismissed, openedEvent: !!state.openedEvent })); } catch { /* ignore */ }
}

export function itemDone(item, state, hasSavedEvent) {
  return item === 'openEvent' ? !!state.openedEvent : item === 'saveEvent' ? !!hasSavedEvent : false;
}

/** Visible while switched on, not dismissed, and something is left to do. */
export function checklistVisible(state, hasSavedEvent) {
  if (!state?.enabled || state.dismissed) return false;
  return CHECKLIST_ITEMS.some(i => !itemDone(i, state, hasSavedEvent));
}
