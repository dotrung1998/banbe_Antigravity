// Shared state of the ONE persistent search bar (twin of iOS PersistentSearchBar + AppState.searchBarHandlers /
// homeSearchBarFrame / searchBarAtHome / mapSearchText). A tiny external store (not BanBeContext) so a keystroke or a
// focus change re-renders only the bar and the screens that read it.
import { useSyncExternalStore } from 'react';

let st = { handlers: null, focused: false, mapQuery: '', searchQuery: '', homeFrame: null, atHome: false };
const subs = new Set();
// Latest callbacks of the registered screen: kept out of `st` so a screen re-rendering never re-renders the bar.
let fns = {};
let inputEl = null;
let pendingFocus = false;

const emit = () => subs.forEach(f => f());
const patch = (p) => { st = { ...st, ...p }; emit(); };
const DATA_KEYS = ['owner', 'placeholder', 'badge', 'hasFilters', 'hidden'];

export const searchBarStore = {
  get: () => st,
  subscribe: (f) => { subs.add(f); return () => subs.delete(f); },
  fns: () => fns,
  /** A screen says what the bar should do for it. Notifies only when the visible data changed. */
  register(h) {
    const { back, submit, cancel, filters, ...data } = h;
    fns = { back, submit, cancel, filters };
    const cur = st.handlers;
    if (cur && DATA_KEYS.every(k => cur[k] === data[k])) return;
    patch({ handlers: data });
  },
  /** Only the owner clears (a screen going away must not clear the one coming in). */
  clear(owner) { if (st.handlers && st.handlers.owner === owner) { fns = {}; patch({ handlers: null }); } },
  setMapQuery: (v) => { if (v !== st.mapQuery) patch({ mapQuery: v }); },
  /** Initial value for a screen's first render (no notification: the bar re-reads on its own commit). */
  seedMapQuery: (v) => { st = { ...st, mapQuery: v }; },
  seedSearchQuery: (v) => { st = { ...st, searchQuery: v }; },
  /** Re-render subscribers after a silent seed. */
  notify: () => { st = { ...st }; emit(); },
  setSearchQuery: (v) => { if (v !== st.searchQuery) patch({ searchQuery: v }); },
  setFocused: (v) => { if (v !== st.focused) patch({ focused: v }); },
  setHomeFrame: (r) => { if (r && r.width > 0) st = { ...st, homeFrame: { left: r.left, top: r.top, width: r.width, height: r.height } }; },
  setAtHome: (v) => { if (v !== st.atHome) patch({ atHome: v }); },
  attachInput(el) {
    inputEl = el;
    if (el && pendingFocus) { pendingFocus = false; try { el.focus({ preventScroll: true }); } catch { /* ignore */ } }
  },
  /** Focus now, or as soon as the bar's input exists (screens ask during their own mount). */
  focus() { if (inputEl) { try { inputEl.focus({ preventScroll: true }); } catch { /* ignore */ } } else pendingFocus = true; },
  blur() { pendingFocus = false; inputEl?.blur(); },
};

export function useSearchBar(select = (s) => s) {
  return select(useSyncExternalStore(searchBarStore.subscribe, searchBarStore.get, searchBarStore.get));
}
