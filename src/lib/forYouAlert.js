// "For You" attention state: which preference-matching events are NEW to this
// account since it last looked. Pure state machine (no React/DOM) - the iOS
// mirror is apps/ios/BanbeApp/Lib/ForYouAlert.swift; keep both in sync.
//
// State: { baselined, prefsVersion, seen:{id:version}, order:[id...], pending:{id:version} }
//   `order` = insertion order of `seen` (oldest first) so the bound can drop oldest.
//
// VERSION per event (built by `forYouEventVersion`): reviewed_at | submitted_at | status | visibility.
// No `updated_at` is selected on `events` today, so the publication moment is
// the best stable field: admin approval stamps `reviewed_at`, a resubmission
// stamps `submitted_at`, and status+visibility are appended so a draft->live or
// invite->public flip also bumps it. Ordinary edits (price tweak, seats sold)
// do NOT change it, so polling never re-alerts.
//
// Only events already in the For You match set are ever passed in; ranking and
// reservation eligibility are not touched here.

export const SEEN_LIMIT = 1000;

export const emptyAlertState = () => ({ baselined: false, prefsVersion: null, seen: {}, order: [], pending: {} });

export function forYouEventVersion(e) {
  return [e?.reviewedAt ?? '', e?.submittedAt ?? '', e?.status ?? '', e?.visibility ?? ''].join('|');
}

const accessible = (m) => m && m.id != null && m.accessible !== false && m.draft !== true && m.status !== 'draft';

function bound(seen, order, limit) {
  if (order.length <= limit) return { seen, order };
  const drop = order.length - limit;
  const nextOrder = order.slice(drop);
  const nextSeen = { ...seen };
  for (const id of order.slice(0, drop)) delete nextSeen[id];
  return { seen: nextSeen, order: nextOrder };
}

/** matches: [{id, version, accessible?, draft?, status?}]. Returns a NEW state (or the same one when nothing applies). */
export function observe(state, matches, { prefsVersion = 0, loading = false, limit = SEEN_LIMIT } = {}) {
  if (loading) return state;
  const list = (matches || []).filter(accessible).map(m => ({ id: String(m.id), version: String(m.version ?? '') }));
  if (!state.baselined || state.prefsVersion !== prefsVersion) {
    const seen = {}; const order = [];
    for (const m of list) { if (!(m.id in seen)) order.push(m.id); seen[m.id] = m.version; }
    return { baselined: true, prefsVersion, ...bound(seen, order, limit), pending: {} };
  }
  const seen = { ...state.seen }; const order = state.order.slice(); const pending = {};
  const present = new Set(list.map(m => m.id));
  for (const [id, v] of Object.entries(state.pending)) if (present.has(id)) pending[id] = v;
  for (const m of list) {
    if (seen[m.id] !== m.version) {
      if (!(m.id in seen)) order.push(m.id);
      seen[m.id] = m.version;
      pending[m.id] = m.version;
    }
  }
  return { baselined: true, prefsVersion, ...bound(seen, order, limit), pending };
}

/** Opening For You: clear only the ids currently loaded; later arrivals stay pending. */
export function acknowledge(state, loadedIds) {
  const ids = new Set((loadedIds || []).map(String));
  const pending = {};
  for (const [id, v] of Object.entries(state.pending)) if (!ids.has(id)) pending[id] = v;
  return Object.keys(pending).length === Object.keys(state.pending).length ? state : { ...state, pending };
}

export const hasPending = (state) => Object.keys(state.pending).length > 0;
export const pendingIds = (state) => Object.keys(state.pending);

// ---- persistence (per account) ----
export const alertStorageKey = (userId) => `banbe.forYouAlert.v1:${userId}`;

export function loadAlertState(userId, storage) {
  if (!userId) return emptyAlertState();
  try {
    const raw = (storage ?? globalThis.localStorage)?.getItem(alertStorageKey(userId));
    if (!raw) return emptyAlertState();
    const p = JSON.parse(raw);
    if (!p || typeof p !== 'object' || typeof p.seen !== 'object' || typeof p.pending !== 'object') return emptyAlertState();
    const order = Array.isArray(p.order) ? p.order.filter(id => id in p.seen) : Object.keys(p.seen);
    return { baselined: !!p.baselined, prefsVersion: p.prefsVersion ?? null, seen: p.seen, order, pending: p.pending };
  } catch { return emptyAlertState(); }
}

export function saveAlertState(userId, state, storage) {
  if (!userId) return;
  try { (storage ?? globalThis.localStorage)?.setItem(alertStorageKey(userId), JSON.stringify(state)); } catch { /* private mode / quota */ }
}
