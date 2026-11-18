// Search screen (note 50) — replaces "the magnifier opens Map". Route: /search.
// Empty query: recent searches (this browser only), trending (Banbe Pulse), category + area shortcuts.
// Typing: live results from the ONE shared matcher (src/lib/search.js — the same documents Map searches),
// grouped Events · Hosts · Areas, each with its count. "See on map" carries the query to Map.
// iOS twin: Views/SearchView.swift. Search never counts toward the streak (note 36).
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { takeSearchOrigin } from '../lib/searchOrigin.js';
import { searchBarStore, useSearchBar } from '../lib/searchBarStore.js';
import { searchBarTop } from '../components/PersistentSearchBar.jsx';
import { SAFE_TOP } from '../lib/viewport.js';
import { useBanBe } from '../state/BanBeContext.jsx';
import { EVENTS, bg, catalogStartMs } from '../data/events.js';
import { paper, ink, ink2, rule, display, fieldGlass, RADIUS } from '../theme.js';
import { inlineEmptyAction } from '../components/ui/InlineEmpty.jsx';
import { buildEventSearchDoc, matchesSearchQuery, normalizeSearchText } from '../lib/search.js';
import { buildLocationSearchIndex, searchLocationTree } from '../lib/locationTree.js';
import { formatVnEventDate } from '../lib/countdown.js';
import { formatMoney } from '../lib/eventMarket.js';
import { CategoryGlyph, CATEGORY_DEFS, CategorySheet } from '../components/home/HomeDiscoveryParts.jsx';
import EventRowV23 from '../components/list/EventRowV23.jsx';
import { categorySheetKeys, DEFAULT_FILTERS } from '../lib/homeDiscovery.js';
import { flagOn } from '../lib/featureFlags.js';
import { ownedFilterCount } from '../lib/unifiedDiscovery.js';
import NativeSheet from '../components/NativeSheet.jsx';
import { DATE_LABELS, SORT_LABELS } from './sheets/HomeFilterSheet.jsx';

const RECENT_KEY = 'banbe_recent_searches_v1';
const RECENT_MAX = 8;
const readRecent = () => { try { const v = JSON.parse(localStorage.getItem(RECENT_KEY) || '[]'); return Array.isArray(v) ? v.filter(x => typeof x === 'string').slice(0, RECENT_MAX) : []; } catch { return []; } };
const writeRecent = (list) => { try { localStorage.setItem(RECENT_KEY, JSON.stringify(list)); } catch { /* private mode: recents are a convenience */ } };
export function pushRecent(list, q) {
  const t = q.trim();
  if (!t) return list;
  const key = normalizeSearchText(t);
  return [t, ...list.filter(x => normalizeSearchText(x) !== key)].slice(0, RECENT_MAX);
}

const ENDED_AFTER_MS = 12 * 3600000; // note 38: a live row 12h past its start is over

export default function Search({ overlay = false }) {
  const {
    state: s, set, T, goEvent, goHome, loadDiscoveryEvents, loadPulse, openOrganizerProfile, pickArea, locationTree, pickFilter,
    setHomeFilters, toggleFav,
  } = useBanBe();
  // The text lives in the ONE persistent bar's store (the bar is hosted in App.jsx and edits it directly). Seeded from
  // the global query on first render (silent: the bar re-reads on its own commit).
  useState(() => { searchBarStore.seedSearchQuery(s.searchQuery || ''); });
  const q = useSearchBar(b => b.searchQuery);
  const setQ = searchBarStore.setSearchQuery;
  // Note 99 (switch unified_discovery): Search, Home and the Map share one query and one set of filters. Under that
  // switch Search is also the prototype's bottom sheet (its own field + Xong), so it no longer borrows the shared top
  // bar — PersistentSearchBar steps aside while this is open and Map keeps it.
  const ud = flagOn(s.featureFlags, 'simple_shell') && flagOn(s.featureFlags, 'home_v23') && flagOn(s.featureFlags, 'unified_discovery');
  // As an overlay, "leaving" just closes it (Home is already there underneath).
  const leave = overlay ? () => set({ searchOverlayOpen: false }) : goHome;
  const [recent, setRecent] = useState(readRecent);
  const [catSheetOpen, setCatSheetOpen] = useState(false);
  const [fieldFocused, setFieldFocused] = useState(false);
  const sheetInputRef = useRef(null);
  // "See on map": the page fades out while the map fades in (no hard cut).
  const [leavingToMap, setLeavingToMap] = useState(false);

  // Entrance from Home's search bar: the field starts where Home's bar was and glides up into the header while the
  // back button grows in and the rest of the page fades in. No origin (opened from elsewhere) = the usual fade-in.
  const [origin] = useState(() => takeSearchOrigin());
  const rootRef = useRef(null);
  const headerRef = useRef(null);
  useLayoutEffect(() => {
    const reduce = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (!origin || reduce || ud) return;
    const ease = 'cubic-bezier(.22,.9,.3,1)';
    const dur = 420;
    // Overlay: the paper fades in over the live Home, the header's own fill with it, and the results drop in from the top.
    rootRef.current?.querySelectorAll(':scope > [data-search-backdrop]').forEach(el => {
      el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 300, easing: 'ease-out' });
    });
    const h = headerRef.current;
    if (overlay && h) {
      const cs = getComputedStyle(h);
      h.animate([{ backgroundColor: 'rgba(0,0,0,0)', borderBottomColor: 'rgba(0,0,0,0)' }, { backgroundColor: cs.backgroundColor, borderBottomColor: cs.borderBottomColor }], { duration: 300, easing: 'ease-out' });
    }
    rootRef.current?.querySelectorAll(':scope > :not([data-search-header]):not([data-search-backdrop]):not([data-search-body]), :scope > [data-search-body] > *').forEach(el => {
      el.animate([{ opacity: 0, transform: overlay ? 'translateY(-24px)' : 'none' }, { opacity: 1, transform: 'none' }], { duration: 300, delay: 140, easing: ease, fill: 'backwards' });
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  // Back: when Search came from Home's bar, the field glides back down onto it (the reverse of the entrance) and the
  // rest fades, then Home takes over.
  const closingRef = useRef(false);
  const close = () => {
    // The bottom sheet has no field to glide back onto: Xong / Esc / a scrim press closes it where it is, keeping the
    // typed words in this browser's recents.
    if (ud) {
      const next = pushRecent(recent, q);
      setRecent(next); writeRecent(next);
      leave();
      return;
    }
    const reduce = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (!origin || reduce) { leave(); return; }
    if (closingRef.current) return;
    closingRef.current = true;
    searchBarStore.blur();
    searchBarStore.setAtHome(true); // the persistent bar glides back down onto Home's own bar while the page fades
    const ease = 'cubic-bezier(.4,0,.2,1)';
    const dur = 420;
    rootRef.current?.querySelectorAll(':scope > :not([data-search-header]):not([data-search-backdrop]):not([data-search-body]), :scope > [data-search-body] > *').forEach(el => {
      el.animate([{ opacity: 1, transform: 'none' }, { opacity: 0, transform: overlay ? 'translateY(-24px)' : 'none' }], { duration: 200, easing: 'ease-in', fill: 'forwards' });
    });
    rootRef.current?.querySelectorAll(':scope > [data-search-backdrop]').forEach(el => {
      el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: dur, easing: ease, fill: 'forwards' });
    });
    const h = headerRef.current;
    if (overlay && h) h.animate([{}, { backgroundColor: 'rgba(0,0,0,0)', borderBottomColor: 'rgba(0,0,0,0)' }], { duration: dur, easing: ease, fill: 'forwards' });
    setTimeout(leave, dur - 20);
  };
  // The keyboard comes up once the field has (nearly) landed, not on top of the glide.
  useEffect(() => {
    // The sheet owns its field: once it has risen, ask for the keyboard (the dialog focuses its first focusable element,
    // but not every browser opens the keyboard for a programmatic focus).
    if (ud) {
      const t = setTimeout(() => sheetInputRef.current?.focus({ preventScroll: true }), 320);
      return () => clearTimeout(t);
    }
    if (!origin) { searchBarStore.focus(); return undefined; }
    const t = setTimeout(() => searchBarStore.focus(), 320);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => { if (!(s.discoveryEvents || []).length) loadDiscoveryEvents(); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (!(s.pulseDaily || []).length) loadPulse('daily'); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { set({ searchQuery: q }); }, [q, set]);
  // Register with the persistent bar (re-registered each render so its callbacks are current; only owner clears).
  const commitRef = useRef(null);
  commitRef.current = (text) => { const next = pushRecent(recent, text); setRecent(next); writeRecent(next); };
  useLayoutEffect(() => {
    searchBarStore.register({ owner: 'search', placeholder: T('Tìm sự kiện, host, khu vực, vibe…', 'Search events, hosts, areas, vibes…'),
      back: close, submit: (text) => commitRef.current?.(text ?? ''), cancel: () => {}, filters: null, badge: 0, hasFilters: false });
  });
  useLayoutEffect(() => () => searchBarStore.clear('search'), []);

  // One searchable list: real public events + the demo catalogue, upcoming only, same doc builder as Map.
  const docs = useMemo(() => {
    const now = Date.now();
    const real = (s.discoveryEvents || [])
      .filter(e => e.status === 'live' && e.visibility === 'public' && !(e.startsAt && now - new Date(e.startsAt).getTime() > ENDED_AFTER_MS))
      .map(e => ({ key: e.key, name: e.name, img: e.photoUrl, organizerId: e.organizerId, organizerName: e.organizerName, area: e.area, catKey: e.catKey,
        startsAt: e.startsAt, priceVnd: e.priceVnd, currency: e.currency, tz: e.tz, doc: buildEventSearchDoc(e) }));
    const realKeys = new Set(real.map(e => e.key));
    const demo = EVENTS.filter(e => !realKeys.has(e.key) && !e.inviteOnly).map(e => ({
      key: e.key, name: e.name, img: e.img, organizerId: null, organizerName: e.hostShort, area: e.locationLabel, catKey: e.cat,
      startsAt: catalogStartMs(e, s.homeLiveEvents?.[e.key]?.starts_at), price: e.price,
      doc: buildEventSearchDoc({ ...e, catLabel: e.cat, area: e.locationLabel, organizerName: e.hostShort, description: e.desc, details: s.homeLiveEvents?.[e.key]?.details }),
    }));
    return [...real, ...demo.filter(d => d.startsAt == null || now - d.startsAt <= ENDED_AFTER_MS)];
  }, [s.discoveryEvents, s.homeLiveEvents]);

  const query = q.trim();
  // Note 99: the event hits are narrowed to what Home's filters (type, time, price, seats) let through. Home is live
  // under this overlay and publishes those keys (s.unifiedKeys); opened as its own screen there is no Home, so nothing
  // is narrowed.
  const hf = s.homeFilters || DEFAULT_FILTERS;
  const udOwned = ud ? ownedFilterCount(hf, s.homeSort) : 0;
  const udNarrows = ud && overlay && s.unifiedKeys != null && (udOwned > 0 || hf.date !== 'any');
  const udKeySet = useMemo(() => (udNarrows ? new Set(String(s.unifiedKeys).split('|')) : null), [udNarrows, s.unifiedKeys]);
  const eventHits = useMemo(() => (query ? docs.filter(d => matchesSearchQuery(d.doc, query) && (!udKeySet || udKeySet.has(d.key))) : []), [docs, query, udKeySet]);
  const hostHits = useMemo(() => {
    if (!query) return [];
    const byName = new Map();
    for (const d of docs) {
      if (!d.organizerName || !matchesSearchQuery(normalizeSearchText(d.organizerName), query)) continue;
      const k = normalizeSearchText(d.organizerName);
      const cur = byName.get(k) || { name: d.organizerName, organizerId: d.organizerId, count: 0 };
      cur.count++; if (!cur.organizerId && d.organizerId) cur.organizerId = d.organizerId;
      byName.set(k, cur);
    }
    return [...byName.values()].sort((a, b) => b.count - a.count).slice(0, 5);
  }, [docs, query]);
  const locIndex = useMemo(() => buildLocationSearchIndex(locationTree), [locationTree]);
  const areaHits = useMemo(() => {
    if (!query) return [];
    const r = searchLocationTree(locationTree, locIndex, query);
    if (!r) return [];
    return [...r.matchIds].map(id => locationTree.byId.get(id)).filter(n => n && n.count > 0).slice(0, 5);
  }, [locationTree, locIndex, query]);

  const commit = (text = q) => { const next = pushRecent(recent, text); setRecent(next); writeRecent(next); };
  const openEv = (key) => { commit(); goEvent(key); };
  const whenOf = (d) => {
    if (!d.startsAt) return '';
    const { weekdayShort, dayMonth, time } = formatVnEventDate(new Date(d.startsAt), d.tz || undefined); // venue zone (migration 195)
    return `${weekdayShort}, ${dayMonth} · ${time}`;
  };
  const priceOf = (d) => (d.price != null ? d.price : d.priceVnd ? formatMoney(d.priceVnd, d.currency) : T('Miễn phí', 'Free'));
  const total = eventHits.length + hostHits.length + areaHits.length;

  // Prototype v2's Search sheet lists the SAME result set the Map shows: one event row per result, narrowed by the
  // shared query and the shared Home/Map filters, with no host/area groups and no trending block.
  const udBase = ud ? (udKeySet ? docs.filter(d => udKeySet.has(d.key)) : docs) : [];
  const udList = ud ? (query ? eventHits : udBase) : [];
  const udRows = ud ? udList.map(d => {
    const cat = CATEGORY_DEFS.find(c => c.key === d.catKey);
    return { key: d.key, name: d.name, img: d.img, when: whenOf(d), type: cat ? T(cat.vi, cat.en) : null,
      place: d.area, priceLabel: priceOf(d), isFree: d.price === 'Miễn phí' || d.priceVnd === 0,
      saved: (s.favorites || []).includes(d.key) };
  }) : [];
  const metaChipStyle = { display: 'inline-flex', alignItems: 'center', gap: 5, height: 26, padding: '0 10px', borderRadius: 999, background: 'var(--bb-block)', color: ink2, fontSize: 11.5, fontWeight: 600, whiteSpace: 'nowrap' };
  const udSChip = { flex: 'none', display: 'inline-flex', alignItems: 'center', gap: 6, height: 38, padding: '0 14px', borderRadius: 999, background: 'var(--bb-surface-2)', color: ink, border: 'none', fontFamily: 'inherit', fontSize: 14, fontWeight: 500, whiteSpace: 'nowrap', cursor: 'pointer' };
  const goMap = () => {
    commit();
    const go = () => { searchBarStore.setMapQuery(query); set({ screen: 'mapExplore', mapExploreState: { focusSearch: false, searchQuery: query } }); };
    const reduce = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduce) { go(); return; }
    setLeavingToMap(true);
    setTimeout(go, 220);
  };

  const groupTitle = (label, n, testId) => (
    <div data-testid={testId} style={{ display: 'flex', alignItems: 'baseline', gap: 8, padding: '18px 20px 10px' }}>
      <span style={{ ...display(16) }}>{label}</span><span style={{ fontSize: 12.5, opacity: 0.6 }}>{n}</span>
    </div>
  );
  const chip = (key, label, onClick, testId, icon) => (
    <button key={key} type="button" onClick={onClick} data-testid={testId}
      style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 36, padding: '0 14px', borderRadius: RADIUS.pill, border: `1px solid ${rule}`, background: 'none', color: ink, fontFamily: 'inherit', fontSize: 13.5, cursor: 'pointer', whiteSpace: 'nowrap' }}>
      {icon}{label}
    </button>
  );

  // The overlay is fixed to the window (it opens over the full-bleed Home hero), so its header must clear the
  // status-bar strip itself; as a root screen it sits inside the scroll viewport that already starts below that inset.
  // The persistent bar (PersistentSearchBar.jsx) draws into this slot at the same offset.
  const topPad = overlay ? `calc(${searchBarTop()}px + ${SAFE_TOP})` : `${searchBarTop()}px`;
  // The prototype's Search is a bottom sheet: it starts 48 px below the status strip, rounds its top 28 px, and carries
  // its own grabber, field and Xong. The panel itself is the scroller, so the head stays put and the map CTA keeps its
  // place at the bottom while the rows move under it.
  const sheetBase = {
    position: 'relative', display: 'flex', flexDirection: 'column',
    width: '100%', height: `calc(100% - 48px - ${SAFE_TOP})`, background: paper, color: ink,
    borderRadius: '28px 28px 0 0', overflow: 'hidden',
    animation: 'banbeSheetIn 0.38s cubic-bezier(.22,.9,.3,1) both',
  };
  const panel = (
    <div ref={rootRef} data-screen-label="Search" data-search-sheet={ud ? 'true' : undefined}
      style={ud
        ? (leavingToMap ? { ...sheetBase, animation: 'none', opacity: 0, transition: 'opacity 0.22s ease', pointerEvents: 'none' } : sheetBase)
        : leavingToMap ? { position: overlay ? 'fixed' : 'relative', inset: overlay ? 0 : undefined, zIndex: overlay ? 45 : undefined, minHeight: '100%', background: paper, color: ink, opacity: 0, transition: 'opacity 0.22s ease', pointerEvents: 'none' } : overlay
        ? { position: 'fixed', inset: 0, zIndex: 45, overflowY: 'auto', color: ink, paddingBottom: 120, animation: origin ? undefined : 'banbeFade 0.2s ease both' }
        : { minHeight: '100%', background: paper, color: ink, paddingBottom: 120, animation: origin ? undefined : 'banbeIn 0.25s ease both' }}>
      {overlay && !ud && <div data-search-backdrop aria-hidden style={{ position: 'fixed', inset: 0, background: paper, zIndex: -1 }} />}
      <div ref={headerRef} data-search-header style={ud
        ? { flex: 'none', zIndex: 3, background: paper, padding: '0 0 10px' }
        : { padding: `${topPad} 16px 10px`, display: 'flex', alignItems: 'center', gap: 10, position: 'sticky', top: 0, background: paper, zIndex: 2, borderBottom: `1px solid ${rule}` }}>
        {ud ? (
          <>
            <div aria-hidden style={{ display: 'grid', placeItems: 'center', height: 20 }}>
              <i style={{ display: 'block', width: 38, height: 5, borderRadius: 3, background: 'rgba(var(--bb-fg-rgb), 0.2)' }} />
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '2px 16px 0' }}>
              <label data-testid="search-sheet-field"
                style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', gap: 10, height: 48, padding: '0 6px 0 16px', borderRadius: 999, background: 'var(--bb-surface-2)', border: `1.5px solid ${fieldFocused ? 'var(--bb-clay)' : 'transparent'}`, transition: 'border-color 0.15s' }}>
                <svg aria-hidden="true" width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="var(--bb-clay)" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ flex: 'none' }}>
                  <circle cx="11" cy="11" r="7" /><path d="M21 21l-4.35-4.35" />
                </svg>
                <input ref={sheetInputRef} data-bare data-testid="search-sheet-input" value={q} onChange={(e) => setQ(e.target.value)}
                  onFocus={() => setFieldFocused(true)} onBlur={() => setFieldFocused(false)}
                  onKeyDown={(e) => { if (e.key === 'Enter' && !e.isComposing && e.keyCode !== 229) { commit(); e.currentTarget.blur(); } }}
                  type="text" inputMode="search" enterKeyHint="search" autoComplete="off" spellCheck={false}
                  placeholder={T('Sự kiện, host, khu vực…', 'Events, hosts, areas…')} aria-label={T('Tìm sự kiện', 'Search events')}
                  style={{ flex: 1, minWidth: 0, height: '100%', border: 0, outline: 0, background: 'none', fontFamily: 'inherit', fontSize: 16, color: ink }} />
                {q !== '' && (
                  <button type="button" data-testid="search-sheet-clear" aria-label={T('Xoá nội dung tìm kiếm', 'Clear search')}
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => { setQ(''); sheetInputRef.current?.focus({ preventScroll: true }); }}
                    style={{ flex: 'none', width: 36, height: 36, marginInlineEnd: -4, borderRadius: '50%', border: 'none', background: 'none', color: ink2, display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
                    <svg aria-hidden="true" width={15} height={15} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round"><path d="M6 6l12 12M18 6L6 18" /></svg>
                  </button>
                )}
              </label>
              <button type="button" data-testid="search-sheet-done" onClick={close}
                style={{ flex: 'none', minHeight: 44, padding: '0 2px', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>
                {T('Xong', 'Done')}
              </button>
            </div>
          </>
        ) : (
          /* The persistent search bar (App.jsx) draws here: back + field. */
          <div data-search-bar-slot aria-hidden style={{ height: 44, flex: 1 }} />
        )}
      </div>

      {/* Prototype `.search-meta`: the source chips sit under the field and stay put while the body scrolls. */}
      {ud && (
        <div style={{ flex: 'none', display: 'flex', flexWrap: 'wrap', gap: 6, padding: '10px 16px 0' }}>
          <span data-testid="search-source" style={metaChipStyle}>
            <svg aria-hidden="true" width={13} height={13} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><path d="M4 10.5 12 4l8 6.5V19a1 1 0 0 1-1 1h-4.5v-5.5h-5V20H5a1 1 0 0 1-1-1z" /></svg>
            {T('Từ Trang chủ', 'From Home')}
          </span>
          <span style={{ ...metaChipStyle, background: 'none', border: `1px solid ${rule}`, color: ink2 }}>
            <svg aria-hidden="true" width={13} height={13} viewBox="0 0 24 24" fill="none" stroke="var(--bb-moss, #4E6A30)" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><path d="M21 12a9 9 0 0 1-15 6.7L3 16M3 12a9 9 0 0 1 15-6.7L21 8" /><path d="M3 21v-5h5M21 3v5h-5" /></svg>
            {T('Trang chủ + Bản đồ', 'Home + Map')}
          </span>
        </div>
      )}

      {/* The sheet's own scroller: the head stays put and the map CTA stays at the bottom of the panel while these
          rows move under it (recent, filter, results). Without the switch this wrapper is `display: contents`, so the
          full-screen Search screen is laid out exactly as before. */}
      <div data-search-body style={ud
        ? { flex: 1, minHeight: 0, overflowY: 'auto', overflowX: 'hidden', WebkitOverflowScrolling: 'touch', overscrollBehavior: 'contain', padding: '0 0 120px' }
        : { display: 'contents' }}>

      {ud && recent.length > 0 && !query && (
        <div data-testid="search-recent-block">
          <div style={{ padding: '18px 20px 8px', fontSize: 11, fontWeight: 600, letterSpacing: '.12em', textTransform: 'uppercase', color: 'var(--bb-fg-3)' }}>{T('Gần đây', 'Recent')}</div>
          <div data-hscroll style={{ display: 'flex', gap: 8, overflowX: 'auto', padding: '0 20px 2px', scrollbarWidth: 'none' }}>
            {recent.map(r => (
              <button key={r} type="button" onClick={() => setQ(r)} data-testid="search-recent" style={udSChip}>
                <svg aria-hidden="true" width={15} height={15} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" style={{ opacity: 0.55 }}><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></svg>
                {r}
              </button>
            ))}
          </div>
        </div>
      )}

      {ud && (() => {
        const cat = hf.cats?.[0] ? CATEGORY_DEFS.find(c => c.key === hf.cats[0]) : null;
        const parts = [
          cat && T(cat.vi, cat.en),
          hf.free ? T('Miễn phí', 'Free') : (hf.priceMin != null || hf.priceMax != null) && T('Theo khoảng giá', 'Price range'),
          hf.seatsLeft && T('Còn chỗ', 'Seats left'), hf.almostFull && T('Sắp hết', 'Almost full'),
          s.homeSort && s.homeSort !== 'soonest' && SORT_LABELS[s.homeSort] && T(...SORT_LABELS[s.homeSort]),
        ].filter(Boolean);
        const when = DATE_LABELS[hf.date] ? T(...DATE_LABELS[hf.date]) : T('Mọi lúc', 'Any time');
        return (
          <button type="button" data-testid="search-filters-link" onClick={() => set({ homeFilterSheetOpen: true })}
            aria-label={parts.length ? T(`Bộ lọc, đang bật ${udOwned}: ${parts.join(', ')}`, `Filters, ${udOwned} on: ${parts.join(', ')}`) : T('Bộ lọc', 'Filters')}
            style={{ display: 'flex', alignItems: 'center', gap: 10, margin: '14px 16px 0', width: 'calc(100% - 32px)', minHeight: 52, padding: '0 10px 0 14px', borderRadius: 16, border: 'none', background: 'var(--bb-block)', color: ink, fontFamily: 'inherit', textAlign: 'left', cursor: 'pointer' }}>
            <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></svg>
            <span style={{ flex: 1, minWidth: 0, fontSize: 14, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {parts.length ? <><b style={{ fontWeight: 600 }}>{T('Bộ lọc:', 'Filters:')}</b> {parts.join(' · ')}</> : T('Bộ lọc', 'Filters')}
              <span style={{ color: 'var(--bb-fg-3)' }}> · {parts.length ? when : T(`loại, giá, sắp xếp · ${when}`, `type, price, sort · ${when}`)}</span>
            </span>
            {udOwned > 0 && <span style={{ minWidth: 20, height: 20, padding: '0 6px', borderRadius: 999, background: 'var(--bb-clay)', color: '#fff', fontSize: 11.5, fontWeight: 700, display: 'grid', placeItems: 'center' }}>{udOwned}</span>}
            <span aria-hidden="true" style={{ opacity: 0.5 }}>›</span>
          </button>
        );
      })()}

      {!query && !ud && (
        <div data-testid="search-idle">
          {recent.length > 0 && (
            <div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '12px 20px 6px' }}>
                <span style={{ ...display(16) }}>{T('Tìm gần đây', 'Recent')}</span>
                <button type="button" onClick={() => { setRecent([]); writeRecent([]); }} data-testid="search-recent-clear"
                  style={{ border: 'none', background: 'none', color: ink, opacity: 0.6, fontFamily: 'inherit', fontSize: 12.5, cursor: 'pointer' }}>{T('Xoá', 'Clear')}</button>
              </div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, padding: '0 20px' }}>
                {recent.map(r => chip(r, r, () => setQ(r), 'search-recent'))}
              </div>
            </div>
          )}
          <div style={{ padding: '12px 20px 6px' }}><span style={{ ...display(16) }}>{T('Danh mục', 'Categories')}</span></div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, padding: '0 20px' }}>
            {CATEGORY_DEFS.filter(c => c.key !== 'all').slice(0, 4).map(c => chip(c.key, T(c.vi, c.en), () => { pickFilter(c.key); goHome(); }, `search-cat-${c.key}`, <CategoryGlyph cat={c.key} size={16} />))}
            {chip('show-all', T('Xem tất cả', 'Show all'), () => setCatSheetOpen(true), 'search-cat-show-all')}
          </div>
          {(s.pulseDaily || []).length > 0 && (
            <>
              <div style={{ padding: '22px 20px 10px' }}><span style={{ ...display(16) }}>{T('Đang được quan tâm', 'Trending today')}</span></div>
              {(s.pulseDaily || []).slice(0, 5).map((p, i) => (
                <button key={p.event_id} type="button" onClick={() => goEvent(p.event_id)} data-testid="search-trending"
                  style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', padding: '8px 20px', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', textAlign: 'left', cursor: 'pointer' }}>
                  <span style={{ width: 22, fontWeight: 700, opacity: 0.5, fontVariantNumeric: 'tabular-nums' }}>{i + 1}</span>
                  <span style={{ flex: 1, minWidth: 0, fontSize: 14.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.event_name}</span>
                  <span aria-hidden="true" style={{ opacity: 0.4 }}>›</span>
                </button>
              ))}
            </>
          )}
        </div>
      )}

      {query && !ud && (
        <div data-testid="search-results" data-count={total}>
          {total === 0 && (
            <div data-testid="search-empty" style={{ padding: '28px 24px 0', textAlign: 'center' }}>
              <div style={{ ...display(17) }}>{T(`Không có kết quả cho "${query}"`, `Nothing for "${query}"`)}</div>
              <div style={{ fontSize: 13, color: ink2, marginTop: 6 }}>{T('Thử một từ ngắn hơn, tên khu vực, hoặc một danh mục.', 'Try a shorter word, an area, or a category.')}</div>
              {/* Calm Pass phase 2: a way forward instead of a dead end. Categories are the real list, not suggestions. */}
              <div style={{ display: 'flex', gap: 8, justifyContent: 'center', flexWrap: 'wrap', marginTop: 14 }}>
                <button type="button" className="bb-press" data-testid="search-empty-all" onClick={() => { pickFilter('all'); goHome(); }} style={inlineEmptyAction}>
                  {T('Xem tất cả sự kiện', 'See all events')}
                </button>
                <button type="button" className="bb-press" data-testid="search-empty-clear" onClick={() => setQ('')} style={inlineEmptyAction}>
                  {T('Xoá tìm kiếm', 'Clear search')}
                </button>
              </div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, justifyContent: 'center', marginTop: 18 }}>
                {CATEGORY_DEFS.filter(c => c.key !== 'all').slice(0, 4).map(c => chip(c.key, T(c.vi, c.en), () => { pickFilter(c.key); goHome(); }, `search-empty-cat-${c.key}`, <CategoryGlyph cat={c.key} size={16} />))}
                {chip('show-all', T('Xem tất cả', 'Show all'), () => setCatSheetOpen(true), 'search-empty-cat-show-all')}
              </div>
            </div>
          )}
          {eventHits.length > 0 && groupTitle(T('Sự kiện', 'Events'), eventHits.length, 'search-group-events')}
          {eventHits.slice(0, 30).map(d => (
            <div key={d.key} onClick={() => openEv(d.key)} data-testid={`search-event-${d.key}`} role="link" tabIndex={0}
              onKeyDown={(e) => { if (e.key === 'Enter') openEv(d.key); }}
              style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '0 20px 12px', cursor: 'pointer' }}>
              <div style={d.img ? bg(d.img, { width: 56, height: 56, borderRadius: RADIUS.thumb, flex: 'none', filter: 'none' }) : { width: 56, height: 56, borderRadius: RADIUS.thumb, flex: 'none', background: 'rgba(var(--bb-fg-rgb),0.08)' }} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', gap: 10, alignItems: 'baseline' }}>
                  <span style={{ ...display(15, { flex: 1, minWidth: 0, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{d.name}</span>
                  <span style={{ fontSize: 13, fontWeight: 700, whiteSpace: 'nowrap' }}>{priceOf(d)}</span>
                </div>
                <div style={{ fontSize: 12, opacity: 0.65, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{[whenOf(d), d.area].filter(Boolean).join(' · ')}</div>
              </div>
            </div>
          ))}
          {hostHits.length > 0 && groupTitle(T('Host', 'Hosts'), hostHits.length, 'search-group-hosts')}
          {hostHits.map(h => (
            <button key={h.name} type="button" data-testid="search-host"
              onClick={() => { commit(); if (h.organizerId) openOrganizerProfile(h.organizerId, overlay ? 'home' : 'search'); else setQ(h.name); }}
              style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', padding: '6px 20px 10px', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', textAlign: 'left', cursor: 'pointer' }}>
              <span style={{ width: 40, height: 40, borderRadius: '50%', flex: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 700, background: 'rgba(var(--bb-fg-rgb),0.08)' }}>{h.name.charAt(0).toUpperCase()}</span>
              <span style={{ flex: 1, minWidth: 0 }}>
                <span style={{ display: 'block', fontSize: 14.5, fontWeight: 600 }}>{h.name}</span>
                <span style={{ fontSize: 12, opacity: 0.6 }}>{T(`${h.count} sự kiện sắp tới`, `${h.count} upcoming event${h.count === 1 ? '' : 's'}`)}</span>
              </span>
              <span aria-hidden="true" style={{ opacity: 0.4 }}>›</span>
            </button>
          ))}
          {areaHits.length > 0 && groupTitle(T('Khu vực', 'Areas'), areaHits.length, 'search-group-areas')}
          {areaHits.map(n => (
            <button key={n.id} type="button" data-testid="search-area"
              onClick={() => { commit(); pickArea(n.id); goHome(); }}
              style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', padding: '6px 20px 10px', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', textAlign: 'left', cursor: 'pointer' }}>
              <span aria-hidden="true" style={{ width: 40, height: 40, borderRadius: RADIUS.tile, flex: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(var(--bb-fg-rgb),0.08)' }}>
                <svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z" /><circle cx="12" cy="9.5" r="2.5" /></svg>
              </span>
              <span style={{ flex: 1, minWidth: 0 }}>
                <span style={{ display: 'block', fontSize: 14.5, fontWeight: 600 }}>{n.value}</span>
                <span style={{ fontSize: 12, opacity: 0.6 }}>{T(`${n.count} sự kiện`, `${n.count} event${n.count === 1 ? '' : 's'}`)}</span>
              </span>
              <span aria-hidden="true" style={{ opacity: 0.4 }}>›</span>
            </button>
          ))}
          <div style={{ padding: total === 0 ? '10px 20px 18px' : '6px 20px 18px', display: 'flex', justifyContent: total === 0 ? 'center' : 'flex-start' }}>
            <button type="button" data-testid="search-see-on-map"
              onMouseDown={(e) => e.preventDefault()} /* keep the bar focused: the keyboard carries over to Map */
              onClick={() => {
                commit();
                const go = () => { searchBarStore.setMapQuery(query); set({ screen: 'mapExplore', mapExploreState: { focusSearch: false, searchQuery: query } }); };
                const reduce = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
                if (reduce) { go(); return; }
                setLeavingToMap(true);
                setTimeout(go, 220);
              }}
              style={{ border: `1px solid ${rule}`, borderRadius: RADIUS.pill, background: 'none', color: ink, fontFamily: 'inherit', fontSize: 13.5, fontWeight: 600, height: 40, padding: '0 16px', cursor: 'pointer' }}>
              {T('Xem trên bản đồ', 'See on map')} ›
            </button>
          </div>
        </div>
      )}
      {ud && (
        <div data-testid="search-results" data-count={udRows.length}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12, padding: '24px 20px 12px' }}>
            <h3 style={{ margin: 0, fontSize: 19, fontWeight: 400, letterSpacing: '-.01em' }}>
              {query ? T(`${udRows.length} kết quả cho “${query}”`, `${udRows.length} result${udRows.length === 1 ? '' : 's'} for “${query}”`)
                : T(`${udRows.length} sự kiện`, `${udRows.length} ${udRows.length === 1 ? 'event' : 'events'}`)}
            </h3>
            <small style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 12, color: 'var(--bb-fg-3)', whiteSpace: 'nowrap' }}>
              <i aria-hidden="true" style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--bb-moss, #4E6A30)' }} />
              {T('Cùng kết quả với bản đồ', 'Same results as the map')}
            </small>
          </div>
          {udRows.map(r => (
            <EventRowV23 key={r.key} row={r} T={T} testId={`search-event-${r.key}`} onOpen={() => openEv(r.key)} onToggleSave={toggleFav} />
          ))}
          {!udRows.length && (
            <div data-testid="search-empty" style={{ margin: '0 20px', padding: '16px 18px', borderRadius: 16, background: 'var(--bb-block)' }}>
              <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: '.12em', textTransform: 'uppercase', color: 'var(--bb-fg-3)' }}>{T('Tìm kiếm', 'Search')}</div>
              <b style={{ display: 'block', fontSize: 16, fontWeight: 500, margin: '6px 0 4px' }}>{T('Không có sự kiện nào khớp.', 'Nothing matches.')}</b>
              <p style={{ margin: '0 0 12px', fontSize: 13, color: ink2 }}>
                {query ? T(`Không có gì khớp “${query}”. Thử một từ khác hoặc bỏ bộ lọc.`, `Nothing matches “${query}”. Try another word or drop the filters.`)
                  : T('Thử bỏ bớt bộ lọc, hoặc chọn Mọi lúc.', 'Try fewer filters, or pick Any time.')}
              </p>
              <button type="button" data-testid="search-empty-clear"
                onClick={() => { setQ(''); set({ searchQuery: '' }); setHomeFilters({ ...DEFAULT_FILTERS }); set({ homeSort: 'soonest' }); }}
                style={{ minHeight: 40, padding: '0 16px', borderRadius: 999, border: 'none', background: ink, color: paper, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>
                {T('Xoá bộ lọc', 'Clear filters')}
              </button>
            </div>
          )}
        </div>
      )}

      </div>
      {/* Prototype `.search-cta`: pinned to the bottom of the sheet, not the end of the list. */}
      {ud && udRows.length > 0 && (
        <button type="button" data-testid="search-see-on-map" onMouseDown={(e) => e.preventDefault()} onClick={goMap}
          style={{ position: 'absolute', left: 16, right: 16, bottom: 'calc(30px + env(safe-area-inset-bottom, 0px))', minHeight: 54, borderRadius: 999, border: 'none', background: ink, color: paper, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10, fontFamily: 'inherit', fontSize: 15.5, fontWeight: 600, boxShadow: '0 10px 26px rgba(12,11,9,.24)', cursor: 'pointer' }}>
          <svg aria-hidden="true" width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round"><path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2z" /><path d="M9 4v14M15 6v14" /></svg>
          {T('Xem trên bản đồ', 'See on the map')}
          <span style={{ minWidth: 24, height: 24, padding: '0 7px', boxSizing: 'border-box', borderRadius: 999, border: '1px solid currentColor', display: 'grid', placeItems: 'center', fontSize: 12, opacity: 0.85 }}>{udRows.length}</span>
        </button>
      )}
      {catSheetOpen && (
        <CategorySheet keys={categorySheetKeys(CATEGORY_DEFS, s.lang === 'en' ? 'en' : 'vi')} counts={null} values={[]} T={T}
          onPick={(k) => { setCatSheetOpen(false); pickFilter(k); goHome(); }} onClose={() => setCatSheetOpen(false)} />
      )}
    </div>
  );
  // Unified discovery: the panel IS the prototype's sheet, so it goes inside the app's native dialog sheet (top layer,
  // focus containment, Esc / back-gesture dismissal, a press on the scrim). Without the switch the panel stays the
  // full-screen Search screen it always was.
  if (ud) {
    return (
      <NativeSheet open onClose={close} label={T('Tìm kiếm', 'Search')} testId="search-sheet" zIndex={2200}>
        {panel}
      </NativeSheet>
    );
  }
  return panel;
}
