// Web twin of iOS TicketRetentionStore: "Cancelled / expired" list housekeeping.
// Removing a row only hides it for THIS account in this browser; the booking row
// (the record behind any refund claim) is never deleted. Rows also leave the list
// 30 days after first being seen as cancelled/expired, except while a refund is open.
import { supabase } from './supabase.js';

const RETENTION_MS = 30 * 24 * 3600 * 1000;
const k = (suffix, uid) => `ticketRetention.${suffix}.${uid}`;

function read(key, fallback) {
  try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; }
}
function write(key, v) {
  try { localStorage.setItem(key, JSON.stringify(v)); } catch { /* storage unavailable */ }
}

export function loadHiddenTickets(uid) {
  return new Set(uid ? read(k('hidden', uid), []) : []);
}

/** Starts the 30-day clock for new rows and hides expired ones (not `protectedIds`). Returns the hidden set. */
export function reconcileTickets(uid, inactiveIds, protectedIds = new Set(), now = Date.now()) {
  if (!uid) return new Set();
  const hidden = new Set(read(k('hidden', uid), []));
  const seen = read(k('seen', uid), {});
  let changed = false;
  for (const id of inactiveIds) if (seen[id] == null) { seen[id] = now; changed = true; }
  for (const id of inactiveIds) {
    if (!hidden.has(id) && !protectedIds.has(id) && now - seen[id] >= RETENTION_MS) { hidden.add(id); changed = true; }
  }
  if (changed) { write(k('hidden', uid), [...hidden]); write(k('seen', uid), seen); }
  return hidden;
}

export function removeTickets(uid, ids) {
  const hidden = loadHiddenTickets(uid);
  ids.forEach(id => hidden.add(id));
  write(k('hidden', uid), [...hidden]);
  pushHiddenTickets(uid, ids);
  return hidden;
}

/** Pushes this device's hidden ids to the account (migration 176) so every device agrees. Best-effort. */
export async function pushHiddenTickets(uid, ids) {
  const rows = [...ids].map(booking_id => ({ user_id: uid, booking_id }));
  if (!uid || !rows.length) return;
  try { await supabase.from('ticket_list_hidden').upsert(rows, { onConflict: 'user_id,booking_id', ignoreDuplicates: true }); }
  catch (e) { console.warn('pushHiddenTickets failed:', e); }
}

/** Merges the account's hidden ids into this browser's, pushes any local-only ones. Returns the union. */
export async function syncHiddenTickets(uid) {
  if (!uid) return new Set();
  const local = loadHiddenTickets(uid);
  try {
    const { data, error } = await supabase.from('ticket_list_hidden').select('booking_id').eq('user_id', uid);
    if (error) throw error;
    const remote = new Set((data || []).map(r => r.booking_id));
    const union = new Set([...local, ...remote]);
    if (union.size !== local.size) write(k('hidden', uid), [...union]);
    await pushHiddenTickets(uid, [...local].filter(id => !remote.has(id)));
    return union;
  } catch (e) { console.warn('syncHiddenTickets failed:', e); return local; }
}
