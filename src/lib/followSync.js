// Framework-free follow synchroniser for the signed-in user's own `follows` rows. Every async
// step re-checks that the account is still the one that started it, so a response that lands
// after sign-out / an account switch can never write into the new account's state.
//
//   api: { listFollows(uid), listOrganizers(ids), insertFollow(uid, id), deleteFollow(uid, id) }
//        each resolves { data, error } (the supabase-js shape).
//   getUid(): the CURRENT signed-in user id (or null).
//   onState(state): called with a fresh snapshot after every change.
//   onFollowChange(organizerId, following): lets other views (profile, Pulse sheet) patch themselves.
import { applyFollowChange, buildFollowedHosts, followWriteOk } from './follows.js';

export const initialFollowState = () => ({ ids: [], hosts: [], status: 'idle', error: '', writeError: '' });

export function createFollowSync({ api, getUid, onState = () => {}, onFollowChange = () => {}, messages = {} }) {
  let state = initialFollowState();
  let owner = null; // uid the current state belongs to
  const busy = new Set();
  const msg = (k, fallback) => messages[k] || fallback;
  const commit = (patch) => { state = { ...state, ...patch }; onState(state); };

  /** Call when the signed-in account may have changed; clears everything that is not this account's. */
  function sync() {
    const uid = getUid() || null;
    if (owner === uid) return false;
    owner = uid;
    busy.clear();
    state = initialFollowState();
    onState(state);
    return true;
  }

  async function load({ silent = false } = {}) {
    sync();
    const uid = getUid();
    if (!uid) return;
    if (!silent) commit({ status: state.status === 'loaded' ? 'loaded' : 'loading', error: '' });
    const fail = () => commit({ status: state.status === 'loaded' ? 'loaded' : 'error', error: msg('loadFailed', "Couldn't load the hosts you follow.") });
    const f = await api.listFollows(uid);
    if (getUid() !== uid) return;
    if (f.error) return fail();
    const ids = [...new Set((f.data || []).map(r => r.organizer_id).filter(Boolean))];
    let orgs = [];
    if (ids.length) {
      const o = await api.listOrganizers(ids);
      if (getUid() !== uid) return;
      if (o.error) return fail();
      orgs = o.data || [];
    }
    if (busy.size) return; // a write is in flight; its own completion re-reads, so don't undo it
    commit({ ids, hosts: buildFollowedHosts(f.data, orgs), status: 'loaded', error: '' });
  }

  function patch(organizerId, following) {
    commit({
      ids: applyFollowChange(state.ids, organizerId, following),
      hosts: following ? state.hosts : state.hosts.filter(h => h.organizerId !== organizerId),
    });
    onFollowChange(organizerId, following);
  }

  async function setFollowing(organizerId, following) {
    sync();
    const uid = getUid();
    if (!uid || !organizerId) return false;
    if (busy.has(organizerId)) return false; // one write per host at a time (double taps)
    busy.add(organizerId);
    const before = state.ids.includes(organizerId);
    const hostRow = state.hosts.find(h => h.organizerId === organizerId);
    commit({ writeError: '' });
    patch(organizerId, following);
    let ok = false;
    try {
      const { error } = following ? await api.insertFollow(uid, organizerId) : await api.deleteFollow(uid, organizerId);
      ok = followWriteOk(error, following);
    } catch { ok = false; }
    if (getUid() !== uid) return ok; // account changed mid-write: sync() already reset state
    busy.delete(organizerId);
    if (!ok) {
      patch(organizerId, before);
      if (before && hostRow && !state.hosts.some(h => h.organizerId === organizerId)) commit({ hosts: [...state.hosts, hostRow] });
      commit({ writeError: following ? msg('followFailed', "Couldn't follow right now. Please try again.") : msg('unfollowFailed', "Couldn't unfollow right now. Please try again.") });
      return false;
    }
    await load({ silent: true });
    return true;
  }

  /** A server-fresh flag (e.g. from get_organizer_profile) folded into the list. Returns true if it differed. */
  function reconcile(organizerId, following) {
    sync();
    if (state.status !== 'loaded' || state.ids.includes(organizerId) === following) return false;
    commit({ ids: applyFollowChange(state.ids, organizerId, following) });
    return true;
  }

  return { sync, load, setFollowing, reconcile, getState: () => state, isBusy: (id) => busy.has(id) };
}
