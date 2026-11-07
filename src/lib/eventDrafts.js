// Host event drafts (iOS Lib/EventDrafts.swift parity): up to MAX_DRAFTS saved, not-yet-submitted new events per
// account, on this browser. IndexedDB, not localStorage: a draft keeps its staged photo Files (Blobs), which are far
// too big for localStorage. Text fields are the BanBeContext `create*` keys below; photos/cover/step are CreateEvent's
// own local state.

export const MAX_DRAFTS = 5;

/** The BanBeContext form keys a draft keeps (all plain JSON). */
export const DRAFT_FIELDS = [
  'createName', 'createCats', 'createDesc', 'createIntro', 'createKeywords', 'createChatGreeting', 'createChatGreetingEn',
  'createIncludedItems', 'createDetails', 'createKwDismissed', 'createPrice', 'createPriceCurrency', 'createSeats', 'createVisibility', 'createHostGoal', 'createCriteria',
  'createEventDate', 'createEventTime',
  'createLoc', 'createLocLabel', 'createLocConfirmed', 'createLat', 'createLng', 'createAddressLine', 'createDistrict',
  'createCity', 'createPostalCode', 'createCountryCode', 'createStateProvince', 'createNeighborhood', 'createTz',
];

const DB_NAME = 'banbe-event-drafts';
const STORE = 'drafts';

function openDb() {
  return new Promise((resolve, reject) => {
    if (typeof indexedDB === 'undefined') { reject(new Error('no indexedDB')); return; }
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      const store = req.result.createObjectStore(STORE, { keyPath: 'id' });
      store.createIndex('uid', 'uid');
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

function run(mode, fn) {
  return openDb().then(db => new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, mode);
    const out = fn(tx.objectStore(STORE));
    tx.oncomplete = () => { db.close(); resolve(out?.result ?? out); };
    tx.onerror = () => { db.close(); reject(tx.error); };
  }));
}

/** This account's drafts, newest first. Empty on any storage failure. */
export async function listDrafts(uid) {
  if (!uid) return [];
  try {
    const rows = await run('readonly', store => store.index('uid').getAll(uid));
    return (rows || []).sort((a, b) => b.savedAt - a.savedAt);
  } catch { return []; }
}

/** Picks the draft-kept fields out of BanBeContext state. */
export function draftFields(state) {
  const out = {};
  for (const k of DRAFT_FIELDS) out[k] = state[k] ?? null;
  return out;
}

/**
 * Saves a new draft or replaces the one with the same id.
 * `photos`: CreateEvent's staged items ({ kind: 'new', file }) in order. Returns { ok, id } or { ok: false, reason: 'full' | 'error' }.
 */
export async function saveDraft(uid, { id, fields, photos, coverIndex, step }) {
  if (!uid) return { ok: false, reason: 'error' };
  const existing = await listDrafts(uid);
  if (!existing.some(d => d.id === id) && existing.length >= MAX_DRAFTS) return { ok: false, reason: 'full' };
  const record = {
    id: id || (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`),
    uid, savedAt: Date.now(), step: step || 0, coverIndex: coverIndex || 0, fields,
    photos: (photos || []).filter(p => p.kind === 'new' && p.file).map(p => ({ blob: p.file, name: p.file.name || 'photo.jpg', type: p.file.type || 'image/jpeg' })),
  };
  try {
    await run('readwrite', store => store.put(record));
    return { ok: true, id: record.id };
  } catch { return { ok: false, reason: 'error' }; }
}

export async function deleteDraft(id) {
  try { await run('readwrite', store => store.delete(id)); } catch { /* already gone */ }
}

/** A draft's photos as staged CreateEvent items (fresh object URLs; the caller owns revoking them). */
export function draftPhotoItems(draft) {
  return (draft?.photos || []).map(p => {
    const file = new File([p.blob], p.name, { type: p.type });
    return { kind: 'new', file, url: URL.createObjectURL(file) };
  });
}
