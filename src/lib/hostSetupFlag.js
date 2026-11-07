// Remembers, per account and per browser, that the first-time host setup was finished or skipped
// so it never re-opens. Storage can be unavailable (private window), so every access is guarded.
const key = uid => `banbe.hostSetup.v1:${uid}`;

export function hostSetupResolved(uid) {
  if (!uid) return true;
  try { return !!localStorage.getItem(key(uid)); } catch { return false; }
}
export function markHostSetup(uid, value) {
  if (!uid) return;
  try { localStorage.setItem(key(uid), value); } catch { /* ignore */ }
}
