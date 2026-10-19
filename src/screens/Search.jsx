// Search screen (note 50) — replaces "the magnifier opens Map". Route: /search.
// Empty query: recent searches (this browser only), trending (Banbe Pulse), category + area shortcuts.
// Typing: live results from the ONE shared matcher (src/lib/search.js — the same documents Map searches),
// grouped Events · Hosts · Areas, each with its count. "See on map" carries the query to Map.
// iOS twin: Views/SearchView.swift. Search never counts toward the streak (note 36).
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { takeSearchOrigin } from '../lib/searchOrigin.js';
import { useBanBe } from '../state/BanBeContext.jsx';
import { EVENTS, bg, catalogStartMs } from '../data/events.js';
import { paper, ink, rule, display, fieldGlass, RADIUS } from '../theme.js';
import { buildEventSearchDoc, matchesSearchQuery, normalizeSearchText } from '../lib/search.js';
import { buildLocationSearchIndex, searchLocationTree } from '../lib/locationTree.js';
import { formatVnEventDate } from '../lib/countdown.js';
import { formatVnd } from '../lib/paymentDocument.js';
import { CategoryGlyph, CATEGORY_DEFS } from '../components/home/HomeDiscoveryParts.jsx';

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
  } = useBanBe();
  const [q, setQ] = useState(s.searchQuery || '');
  // As an overlay, "leaving" just closes it (Home is already there underneath).
  const leave = overlay ? () => set({ searchOverlayOpen: false }) : goHome;
  const [recent, setRecent] = useState(readRecent);
  const inputRef = useRef(null);

  // Entrance from Home's search bar: the field starts where Home's bar was and glides up into the header while the
  // back button grows in and the rest of the page fades in. No origin (opened from elsewhere) = the usual fade-in.
  const [origin] = useState(() => takeSearchOrigin());
  const rootRef = useRef(null);
  const headerRef = useRef(null);
  const backRef = useRef(null);
  const formRef = useRef(null);
  useLayoutEffect(() => {
    const f = formRef.current;
    const reduce = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (!origin || !f?.animate || reduce) return;
    const r = f.getBoundingClientRect();
    const ease = 'cubic-bezier(.22,.9,.3,1)';
    const dur = 420;
    backRef.current?.animate([{ width: '0px', marginRight: '-10px', opacity: 0 }, { width: '40px', marginRight: '0px', opacity: 1 }], { duration: dur, easing: ease });
    f.animate([{ transform: `translateY(${origin.top + (origin.height - r.height) / 2 - r.top}px)` }, { transform: 'none' }], { duration: dur, easing: ease });
    // Overlay: the paper fades in over the live Home, the header's own fill with it, and the results drop in from the top.
    rootRef.current?.querySelectorAll(':scope > [data-search-backdrop]').forEach(el => {
      el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 300, easing: 'ease-out' });
    });
    const h = headerRef.current;
    if (overlay && h) {
      const cs = getComputedStyle(h);
      h.animate([{ backgroundColor: 'rgba(0,0,0,0)', borderBottomColor: 'rgba(0,0,0,0)' }, { backgroundColor: cs.backgroundColor, borderBottomColor: cs.borderBottomColor }], { duration: 300, easing: 'ease-out' });
    }
    rootRef.current?.querySelectorAll(':scope > :not([data-search-header]):not([data-search-backdrop])').forEach(el => {
      el.animate([{ opacity: 0, transform: overlay ? 'translateY(-24px)' : 'none' }, { opacity: 1, transform: 'none' }], { duration: 300, delay: 140, easing: ease, fill: 'backwards' });
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  // Back: when Search came from Home's bar, the field glides back down onto it (the reverse of the entrance) and the
  // rest fades, then Home takes over.
  const closingRef = useRef(false);
  const close = () => {
    const f = formRef.current;
    const reduce = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (!origin || !f?.animate || reduce) { leave(); return; }
    if (closingRef.current) return;
    closingRef.current = true;
    inputRef.current?.blur();
    const r = f.getBoundingClientRect();
    const ease = 'cubic-bezier(.4,0,.2,1)';
    const dur = 320;
    backRef.current?.animate([{ width: '40px', marginRight: '0px', opacity: 1 }, { width: '0px', marginRight: '-10px', opacity: 0 }], { duration: dur, easing: ease, fill: 'forwards' });
    f.animate([{ transform: 'none' }, { transform: `translateY(${origin.top + (origin.height - r.height) / 2 - r.top}px)` }], { duration: dur, easing: ease, fill: 'forwards' });
    rootRef.current?.querySelectorAll(':scope > :not([data-search-header]):not([data-search-backdrop])').forEach(el => {
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
    if (!origin) { inputRef.current?.focus(); return undefined; }
    const t = setTimeout(() => inputRef.current?.focus({ preventScroll: true }), 320);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => { if (!(s.discoveryEvents || []).length) loadDiscoveryEvents(); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (!(s.pulseDaily || []).length) loadPulse('daily'); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { set({ searchQuery: q }); }, [q, set]);

  // One searchable list: real public events + the demo catalogue, upcoming only, same doc builder as Map.
  const docs = useMemo(() => {
    const now = Date.now();
    const real = (s.discoveryEvents || [])
      .filter(e => e.status === 'live' && e.visibility === 'public' && !(e.startsAt && now - new Date(e.startsAt).getTime() > ENDED_AFTER_MS))
      .map(e => ({ key: e.key, name: e.name, img: e.photoUrl, organizerId: e.organizerId, organizerName: e.organizerName, area: e.area,
        startsAt: e.startsAt, priceVnd: e.priceVnd, doc: buildEventSearchDoc(e) }));
    const realKeys = new Set(real.map(e => e.key));
    const demo = EVENTS.filter(e => !realKeys.has(e.key) && !e.inviteOnly).map(e => ({
      key: e.key, name: e.name, img: e.img, organizerId: null, organizerName: e.hostShort, area: e.locationLabel,
      startsAt: catalogStartMs(e, s.homeLiveEvents?.[e.key]?.starts_at), price: e.price,
      doc: buildEventSearchDoc({ ...e, catLabel: e.cat, area: e.locationLabel, organizerName: e.hostShort, description: e.desc }),
    }));
    return [...real, ...demo.filter(d => d.startsAt == null || now - d.startsAt <= ENDED_AFTER_MS)];
  }, [s.discoveryEvents, s.homeLiveEvents]);

  const query = q.trim();
  const eventHits = useMemo(() => (query ? docs.filter(d => matchesSearchQuery(d.doc, query)) : []), [docs, query]);
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
    const { weekdayShort, dayMonth, time } = formatVnEventDate(new Date(d.startsAt));
    return `${weekdayShort}, ${dayMonth} · ${time}`;
  };
  const priceOf = (d) => (d.price != null ? d.price : d.priceVnd ? formatVnd(d.priceVnd) : T('Miễn phí', 'Free'));
  const total = eventHits.length + hostHits.length + areaHits.length;

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

  return (
    <div ref={rootRef} data-screen-label="Search"
      style={overlay
        ? { position: 'fixed', inset: 0, zIndex: 45, overflowY: 'auto', color: ink, paddingBottom: 120, animation: origin ? undefined : 'banbeFade 0.2s ease both' }
        : { minHeight: '100%', background: paper, color: ink, paddingBottom: 120, animation: origin ? undefined : 'banbeIn 0.25s ease both' }}>
      {overlay && <div data-search-backdrop aria-hidden style={{ position: 'fixed', inset: 0, background: paper, zIndex: -1 }} />}
      <div ref={headerRef} data-search-header style={{ padding: '58px 16px 10px', display: 'flex', alignItems: 'center', gap: 10, position: 'sticky', top: 0, background: paper, zIndex: 2, borderBottom: `1px solid ${rule}` }}>
        <button ref={backRef} type="button" onClick={close} aria-label={T('Quay lại', 'Back')} data-testid="search-back"
          style={{ overflow: 'hidden', width: 40, height: 40, borderRadius: '50%', border: 'none', background: 'rgba(var(--bb-fg-rgb),0.07)', color: ink, fontSize: 20, cursor: 'pointer', flex: 'none' }}>‹</button>
        <form ref={formRef} onSubmit={(e) => { e.preventDefault(); commit(); inputRef.current?.blur(); }} style={{ flex: 1, display: 'flex' }}>
          <input ref={inputRef} value={q} onChange={(e) => setQ(e.target.value)} type="search" enterKeyHint="search" data-testid="search-input"
            placeholder={T('Tìm sự kiện, host, khu vực, vibe…', 'Search events, hosts, areas, vibes…')}
            aria-label={T('Tìm kiếm', 'Search')}
            style={{ ...fieldGlass({ borderRadius: RADIUS.pill }), flex: 1, height: 44, border: 'none', padding: '0 16px', fontSize: 15, color: ink, fontFamily: 'inherit', outline: 'none' }} />
        </form>
      </div>

      {!query && (
        <div data-testid="search-idle">
          {recent.length > 0 && (
            <div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '18px 20px 10px' }}>
                <span style={{ ...display(16) }}>{T('Tìm gần đây', 'Recent')}</span>
                <button type="button" onClick={() => { setRecent([]); writeRecent([]); }} data-testid="search-recent-clear"
                  style={{ border: 'none', background: 'none', color: ink, opacity: 0.6, fontFamily: 'inherit', fontSize: 12.5, cursor: 'pointer' }}>{T('Xoá', 'Clear')}</button>
              </div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, padding: '0 20px' }}>
                {recent.map(r => chip(r, r, () => setQ(r), 'search-recent'))}
              </div>
            </div>
          )}
          <div style={{ padding: '18px 20px 10px' }}><span style={{ ...display(16) }}>{T('Danh mục', 'Categories')}</span></div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, padding: '0 20px' }}>
            {CATEGORY_DEFS.filter(c => c.key !== 'all').map(c => chip(c.key, T(c.vi, c.en), () => { pickFilter(c.key); goHome(); }, `search-cat-${c.key}`, <CategoryGlyph cat={c.key} size={16} />))}
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

      {query && (
        <div data-testid="search-results" data-count={total}>
          {total === 0 && (
            <div data-testid="search-empty" style={{ padding: '36px 24px', textAlign: 'center' }}>
              <div style={{ ...display(17) }}>{T(`Không có kết quả cho "${query}"`, `Nothing for "${query}"`)}</div>
              <div style={{ fontSize: 13, opacity: 0.65, marginTop: 6 }}>{T('Thử một từ ngắn hơn, tên khu vực, hoặc một danh mục.', 'Try a shorter word, an area, or a category.')}</div>
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
          <div style={{ padding: '18px 20px' }}>
            <button type="button" data-testid="search-see-on-map"
              onClick={() => { commit(); set({ screen: 'mapExplore', mapExploreState: { focusSearch: false, searchQuery: query } }); }}
              style={{ border: `1px solid ${rule}`, borderRadius: RADIUS.pill, background: 'none', color: ink, fontFamily: 'inherit', fontSize: 13.5, fontWeight: 600, height: 40, padding: '0 16px', cursor: 'pointer' }}>
              {T('Xem trên bản đồ', 'See on map')} ›
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
