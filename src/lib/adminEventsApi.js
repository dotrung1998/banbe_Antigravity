// Admin > Manage events — the network calls (note 54). Pure wording helpers live in adminEvents.js.
import { supabase } from './supabase.js';
import { ADMIN_EVENTS_PAGE, needsAnotherPage } from './adminEvents.js';
import { marketColumnList, marketColumnsRejected } from './mediaUrls.js';

const isMissingFunction = (error) => {
  const m = `${error?.message || ''} ${error?.code || ''}`;
  return /PGRST202|42883|could not find the function|removal_reason/i.test(m);
};

export async function loadAdminManagedEvents({ status, search }) {
  const term = (search || '').trim().replace(/[%_,()]/g, ' ').trim();
  const rows = [];
  // Paged (2026-10-21): a single .limit(200) cut off older events, which is where orphaned drafts/ended events sit.
  for (let page = 0; ; page += 1) {
    const from = page * ADMIN_EVENTS_PAGE;
    // Location + per-event zone/currency (migration 195; retried without them on a DB that lacks them) so
    // times and prices read in the event's own zone and currency.
    const run = () => {
      let q = supabase.from('events').select(['id, name, status, starts_at, created_at, submitted_at, price_vnd, capacity, seats_remaining, area, country_code, state_province', ...marketColumnList(), 'removal_reason, removed_at, organizer_id, organizers(name, owner_id, user_id)'].join(', '));
      if (status) q = q.eq('status', status);
      if (term) q = q.ilike('name', `%${term}%`);
      return q.order('starts_at', { ascending: false, nullsFirst: false }).order('id').range(from, from + ADMIN_EVENTS_PAGE - 1);
    };
    let { data, error } = await run();
    if (marketColumnsRejected(error)) ({ data, error } = await run());
    if (error) return { rows: [], error: isMissingFunction(error) ? 'NOT_DEPLOYED' : 'NETWORK' };
    (data || []).forEach(r => rows.push({
      ...r,
      organizer_name: r.organizers?.name || '',
      organizer_owner_id: r.organizers?.owner_id || null,
      organizer_user_id: r.organizers?.user_id || null,
      organizer_missing: !!r.organizer_id && !r.organizers,
    }));
    if (!needsAnotherPage((data || []).length, rows.length)) break;
  }
  return { rows, error: null };
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
