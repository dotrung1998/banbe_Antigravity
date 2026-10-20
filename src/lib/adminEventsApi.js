// Admin > Manage events — the network calls (note 54). Pure wording helpers live in adminEvents.js.
import { supabase } from './supabase.js';

const isMissingFunction = (error) => {
  const m = `${error?.message || ''} ${error?.code || ''}`;
  return /PGRST202|42883|could not find the function|removal_reason/i.test(m);
};

export async function loadAdminManagedEvents({ status, search }) {
  let q = supabase.from('events').select('id, name, status, starts_at, removal_reason, removed_at, organizer_id, organizers(name)');
  if (status) q = q.eq('status', status);
  const term = (search || '').trim().replace(/[%_,()]/g, ' ').trim();
  if (term) q = q.ilike('name', `%${term}%`);
  const { data, error } = await q.order('starts_at', { ascending: false, nullsFirst: false }).limit(200);
  if (error) return { rows: [], error: isMissingFunction(error) ? 'NOT_DEPLOYED' : 'NETWORK' };
  return { rows: (data || []).map(r => ({ ...r, organizer_name: r.organizers?.name || '' })), error: null };
}

export async function loadAdminEventChecks(ids) {
  const out = {};
  for (let i = 0; i < ids.length; i += 200) {
    const { data, error } = await supabase.rpc('admin_event_removal_check', { p_event_ids: ids.slice(i, i + 200) });
    if (error || !data?.success) continue;
    (data.events || []).forEach(c => { out[c.event_id] = c; });
  }
  return out;
}

const RPC = { remove: 'admin_remove_events', restore: 'admin_restore_events', purge: 'admin_purge_events' };

export async function runAdminEventAction(action, ids, reason = '') {
  const params = action === 'restore' ? { p_event_ids: ids } : { p_event_ids: ids, p_reason: reason };
  const { data, error } = await supabase.rpc(RPC[action], params);
  if (error) return { error: isMissingFunction(error) ? 'NOT_DEPLOYED' : 'NETWORK', done: 0, skipped: [] };
  if (!data?.success) return { error: data?.error || 'NETWORK', done: 0, skipped: [] };
  return { error: null, done: data.removed ?? data.restored ?? data.purged ?? 0, skipped: (data.results || []).filter(r => !r.ok) };
}
