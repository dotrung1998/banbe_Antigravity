import { useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { supabase } from '../lib/supabase.js';
import { findEvent, haversineKm, distanceLabel } from '../data/events.js';
import { liveEventOverrides } from '../lib/countdown.js';
import { densityHotspot } from '../lib/densityHotspot.js';
import { FILTER_DEFS } from './Home.jsx';
import { paper, ink, rule, alert, photoPill, fieldGlass, cardGlass, inkButton } from '../theme.js';
import 'maplibre-gl/dist/maplibre-gl.css';

// Category glyph per FILTER_DEFS key — no icon set exists anywhere else in
// this app (see .claude/notes/11-realtime-map.md), so these are plain
// minimal glyphs rather than an invented illustrated icon language.
const CAT_GLYPH = { all: '▪︎', supper: '🍽️', fashion: '👗', gallery: '🖼️', music: '🎵' };

// Same disabled-button opacity this app already uses everywhere else
// (apps/ios/BanbeApp/Views/Components.swift:151, Login.jsx's loginBtnStyle)
// — reused verbatim for the compass button while location is denied.
const DISABLED_OPACITY = 0.16;

// Same poll cadence as GocContext.jsx's notification poll (07-notifications.md) —
// this app has no realtime subscriptions anywhere, everything polls.
const POLL_MS = 5000;

const SHEET_SNAPS = { tall: 0.30, mid: 0.58, peek: 0.86 }; // fraction of viewport height reserved for the visible map strip above the sheet

async function fetchLiveEvents({ bounds, limit = 60, offset = 0 } = {}) {
  let q = supabase
    .from('events')
    .select('id, key, name, cat_key, cat_label, area, lat, lng, starts_at, event_date, event_time, price_vnd, seats_remaining, status')
    .eq('status', 'live')
    .not('lat', 'is', null)
    .not('lng', 'is', null)
    .order('starts_at', { ascending: true })
    .range(offset, offset + limit - 1);
  if (bounds) {
    q = q.gte('lat', bounds.south).lte('lat', bounds.north).gte('lng', bounds.west).lte('lng', bounds.east);
  }
  const { data, error } = await q;
  if (error) { console.warn('Failed to load map events:', error); return []; }
  return (data || []).map(row => {
    const cosmetic = findEvent(row.id);
    // 2026-09-25 fix pass (Task 0 audit) — real bug: `when` below used to
    // be the static catalogue's own frozen `cosmetic.when` verbatim (the
    // comment here used to claim that was "not reformatted from starts_at
    // ... so it never disagrees with the rest of the app," which was
    // exactly backwards once the rest of the app started reading the real
    // date). `row` here is a real `events` row from THIS query (already
    // filtered `status = 'live'`), so it can drive the same
    // `liveEventOverrides` merge every other screen uses directly.
    const dateOverrides = cosmetic ? liveEventOverrides(row, cosmetic) : null;
    return {
      id: row.id,
      catKey: row.cat_key || cosmetic?.catKey || 'all',
      name: row.name || cosmetic?.name,
      area: row.area || cosmetic?.meta,
      lat: row.lat,
      lng: row.lng,
      seatsRemaining: row.seats_remaining,
      startsAt: row.starts_at,
      price: cosmetic?.price,
      img: cosmetic?.img,
      when: dateOverrides?.when || cosmetic?.when,
      urgent: row.seats_remaining != null && row.seats_remaining <= 5,
      isNew: (dateOverrides?.until ?? cosmetic?.until) != null && (dateOverrides?.until ?? cosmetic?.until) <= 1,
      // Live seats_remaining is this screen's own established "real-time-ish"
      // signal (already used for `urgent` above) — reused for sold-out too,
      // falling back to the static catalogue's flag only when a row has no
      // seats_remaining of its own to check.
      soldOut: row.seats_remaining != null ? row.seats_remaining <= 0 : !!cosmetic?.soldOut,
    };
  });
}

export default function MapExplore() {
  const { state: s, T, goEvent, backFromMapExplore, allowLocation, setMapExploreState } = useGoc();
  // Restored once, at mount, if MapExplore.jsx's own CTA saved a snapshot
  // right before navigating to Event Detail (bug 2) — App.jsx's Shell
  // unmounts/remounts this whole component on every `screen` change, so
  // without this every local useState below would just reset to its
  // hardcoded default the instant the user comes back. Read into a ref
  // once so later renders (after the snapshot is consumed/cleared) don't
  // keep re-reading a stale closure.
  const restoredRef = useRef(s.mapExploreState);
  const restored = restoredRef.current;
  const mapDivRef = useRef(null);
  const mapRef = useRef(null);
  const markersRef = useRef([]);
  const listRef = useRef(null);
  const listScrollRestoredRef = useRef(false);
  const [events, setEvents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [catFilter, setCatFilter] = useState(() => restored?.catFilter ?? 'all');
  const [openNowOnly, setOpenNowOnly] = useState(() => restored?.openNowOnly ?? false);
  const [sortByDistance, setSortByDistance] = useState(() => restored?.sortByDistance ?? false);
  // Task 6 (2026-09-21 follow-up) — "Open in Map"'s own snapshot
  // (GocContext.jsx's openEventOnMap) never sets `sheetSnap` (only
  // camera/selectedId), so a genuine MapExplore-to-MapExplore restore
  // (which DOES carry a real `sheetSnap`) is untouched; only the "arrives
  // with a card already selected, no restored sheet position of its own"
  // case defaults to 'mid' instead of 'tall', same reasoning as
  // `selectEvent`'s own snap-down below.
  const [sheetSnap, setSheetSnap] = useState(() => restored?.sheetSnap ?? (restored?.selectedId ? 'mid' : 'tall'));
  const [boundsChanged, setBoundsChanged] = useState(false);
  const [page, setPage] = useState(0);
  const lastQueriedBounds = useRef(null);
  // The pin/list-row currently showing the compact in-map preview card —
  // null when nothing is selected. Not a second data source: it's just an
  // id into the same `events`/`visibleEvents` this screen already loads.
  const [selectedId, setSelectedId] = useState(() => restored?.selectedId ?? null);
  const lastAnimatedPinIdRef = useRef(null);
  // Hoisted above the sheet-drag section below (which also reads/writes
  // dragOffsetVh) purely so selectEvent() — defined before that section —
  // can compute the sheet's current pixel height for the camera padding.
  const [dragOffsetVh, setDragOffsetVh] = useState(0);
  const mapStripFraction = Math.min(0.95, Math.max(0.05, SHEET_SNAPS[sheetSnap] + dragOffsetVh));
  const sheetTopVh = mapStripFraction * 100;
  // Bug 1 fix: the selected-event preview card's own vertical anchor is
  // deliberately NOT tied to the sheet's continuous, freely-dragged
  // position above — only two states exist for the card: "upper" (used for
  // BOTH tall and mid, so it never gets pulled down into the middle of the
  // screen just because the sheet is at mid) and "lower" (only once the
  // sheet is genuinely all the way down at peek). `mapStripFraction`
  // (which does vary continuously while dragging) is still exactly what
  // the SHEET itself uses for its own `top`, and still what the camera
  // padding below reads for a precise "how much of the screen is the sheet
  // covering right now" — only the CARD's anchor is pinned to the nearest
  // snap point instead.
  //
  // Follow-up (top-controls overlap, 11-realtime-map.md): "upper" used to
  // be a fixed viewport-height fraction (`SHEET_SNAPS.tall`) — on some
  // viewport sizes that put the card's own top edge above the back/compass/
  // "Tìm ở đây" row entirely. `topControlsBottom`/`cardHeight` below are
  // the row's and card's own ACTUALLY MEASURED pixel geometry (via refs +
  // `ResizeObserver`), not a guessed constant — see `cardBottomPx`.
  const backRef = useRef(null);
  const compassRef = useRef(null);
  const searchHereRef = useRef(null);
  const cardRef = useRef(null);
  const [topControlsBottom, setTopControlsBottom] = useState(56);
  const [cardHeight, setCardHeight] = useState(150);
  const [viewportHeight, setViewportHeight] = useState(() => window.innerHeight);
  const CARD_TOP_GAP = 12;

  useEffect(() => {
    const onResize = () => setViewportHeight(window.innerHeight);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);

  // Re-measures whenever "Tìm ở đây" appears/disappears (it can be the
  // taller of the row when shown, on some locales/font sizes) or the
  // viewport itself resizes/rotates.
  useEffect(() => {
    const els = [backRef.current, compassRef.current, searchHereRef.current].filter(Boolean);
    if (!els.length) return;
    const measure = () => setTopControlsBottom(Math.max(...els.map(el => el.getBoundingClientRect().bottom)));
    measure();
    const ro = new ResizeObserver(measure);
    els.forEach(el => ro.observe(el));
    return () => ro.disconnect();
  }, [boundsChanged]);

  useEffect(() => {
    if (!cardRef.current) return;
    const measure = () => setCardHeight(cardRef.current.getBoundingClientRect().height);
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(cardRef.current);
    return () => ro.disconnect();
  }, [selectedId]);

  // A single, always-px `bottom` value (never mixing vh/px units across
  // states) so the CSS `transition` below interpolates smoothly whichever
  // way the anchor changes — same reasoning as the iOS fix's single
  // `cardBottomPadding` (both replace what used to be a fixed-fraction
  // computation with one driven by real, measured geometry for the
  // "upper" case; "peek" is unchanged, already nowhere near the top
  // controls).
  const cardBottomPx = sheetSnap === 'peek'
    ? viewportHeight * (1 - SHEET_SNAPS.peek) + 10
    : Math.max(8, viewportHeight - topControlsBottom - CARD_TOP_GAP - cardHeight - 8);

  // ---- location permission state (drives the compass button's opacity) ----
  const [locPermission, setLocPermission] = useState('prompt'); // 'granted' | 'denied' | 'prompt'
  useEffect(() => {
    if (s.located === true) { setLocPermission('granted'); return; }
    if (s.located === false) { setLocPermission('denied'); return; }
    if (!navigator.permissions?.query) return;
    let sub;
    navigator.permissions.query({ name: 'geolocation' }).then(status => {
      setLocPermission(status.state);
      status.onchange = () => setLocPermission(status.state);
      sub = status;
    }).catch(() => {});
    return () => { if (sub) sub.onchange = null; };
  }, [s.located]);

  const recenterOnUser = useCallback(() => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLocPermission('granted');
        allowLocation();
        mapRef.current?.flyTo({ center: [pos.coords.longitude, pos.coords.latitude], zoom: 14 });
      },
      () => setLocPermission('denied'),
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }, [allowLocation]);

  // ---- pin/list-row selection: camera zoom + compact in-map preview card ----
  // Reuses the same `events`/`visibleEvents` this screen already loads —
  // selecting is just remembering an id, never a second query.
  const selectEvent = useCallback((ev) => {
    setSelectedId(ev.id);
    // Task 6 (2026-09-21 follow-up) — selecting an event at the tallest
    // sheet snap ('tall' = 0.30 map-strip fraction, the least visible map)
    // used to leave the sheet right there, squeezing the map into a sliver
    // right when its own pin/info card most needs room to be seen. Drops
    // to 'mid' only from 'tall'; already being at 'mid'/'peek' (more map
    // visible than 'tall') is left alone.
    setSheetSnap(prev => (prev === 'tall' ? 'mid' : prev));
    const map = mapRef.current;
    if (!map) return;
    // Padding keeps the selected pin above BOTH the bottom sheet and the
    // compact preview card that's about to appear just above it (point 2 —
    // "not hidden beneath the bottom sheet"), rather than flying to a
    // geometric center that a real user can't actually see. sheetPx here
    // mirrors the exact same math the sheet's own `top: ${sheetTopVh}vh`
    // style uses, so this stays correct across List lớn/List nhỏ/mid-drag.
    const sheetPx = window.innerHeight * (1 - mapStripFraction);
    const CARD_ALLOWANCE = 150; // approx. compact card height + gap
    map.flyTo({
      center: [ev.lng, ev.lat],
      zoom: Math.max(map.getZoom(), 15.5),
      padding: { top: 80, bottom: sheetPx + CARD_ALLOWANCE, left: 30, right: 30 },
      duration: 550,
    });
  }, [mapStripFraction]);

  const clearSelection = useCallback(() => setSelectedId(null), []);

  // Once a restored snapshot has been read into `restoredRef` (above), clear
  // context's own copy — it's served its purpose for this mount, and
  // leaving it sitting in context risks a second, unrelated mount
  // mistakenly reusing the exact same snapshot later.
  useEffect(() => {
    if (restored) setMapExploreState(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ---- initial load: density-hotspot center (never the user's own GPS), then draw the map ----
  useEffect(() => {
    let active = true;
    (async () => {
      const initial = await fetchLiveEvents({});
      if (!active) return;
      setEvents(initial);
      setLoading(false);

      // Bug 2: a restored camera center takes priority over density-hotspot
      // centering — re-running that computation on every return from Event
      // Detail would silently discard exactly where the user had the map
      // (possibly after their own manual pan/zoom), even though the whole
      // point of restoring is "don't re-initialize." Hotspot centering only
      // ever runs for a genuinely fresh visit (no restored snapshot).
      const center = restored?.cameraCenter
        || densityHotspot(initial.map(e => ({ lat: e.lat, lng: e.lng }))) || { lat: 10.7769, lng: 106.7009 };

      // maplibre-gl 6.x ships pure named ESM exports — there is no
      // `default` export. `(await import(...)).default` was silently
      // `undefined`, so `new maplibregl.Map(...)` threw and the map never
      // initialized (11-realtime-map.md: "web map doesn't render at all").
      const maplibregl = await import('maplibre-gl');
      // maplibre-gl locates its tile-decoding worker at runtime via
      // `new URL('./maplibre-gl-worker.mjs', import.meta.url)`, computed
      // from a variable rather than a static string literal — Vite/
      // Rollup's special `new Worker(new URL(...))` bundling only
      // recognizes a literal, so it never bundles this worker at all; a
      // production build then never emits `maplibre-gl-worker.mjs` and the
      // URL 404s (a static host's SPA fallback can mask this as an HTTP
      // 200 of index.html) — the map style/sprite/source *metadata* still
      // load fine over plain fetch from the main thread, but no vector
      // tile is ever decoded into pixels, so only markers (plain DOM
      // elements, not part of the tile canvas) paint; the base map stays
      // blank/gray. Confirmed via Playwright's `page.on('worker', ...)`:
      // the worker was created and immediately closed. vite.config.js's
      // `maplibreWorkerFiles()` plugin serves/emits the worker file (and
      // the sibling `maplibre-gl-shared.mjs` it itself imports — a bare
      // `?url` copy of just the worker file breaks that relative import
      // once it's alone in a hashed output directory) at this fixed path,
      // identically in dev and in a production build, so this path always
      // resolves regardless of mode. See 11-realtime-map.md.
      maplibregl.setWorkerUrl('/maplibre-gl-worker/maplibre-gl-worker.mjs');
      if (!active || !mapDivRef.current || mapRef.current) return;

      const map = new maplibregl.Map({
        container: mapDivRef.current,
        style: 'https://tiles.openfreemap.org/styles/positron',
        center: [center.lng, center.lat],
        zoom: restored?.cameraZoom ?? 13,
      });
      map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
      map.on('moveend', () => {
        if (!lastQueriedBounds.current) { lastQueriedBounds.current = map.getBounds(); return; }
        setBoundsChanged(true);
      });
      // A tap on the map background (not a pin — those are separate marker
      // DOM elements, never reaches this) clears the selected-event card.
      // This is a genuine click, not `moveend`, so it can never be confused
      // with "Search here" (that's tied only to the explicit button).
      map.on('click', () => setSelectedId(null));
      // Task 7 fix (2026-09-21 follow-up) — `restored.singleEventFocus`
      // ("Open in Map", GocContext.jsx's openEventOnMap) sets `cameraZoom:
      // 15.5`, a deliberately tight single-pin view meant only for the
      // VISUAL camera. Seeding `lastQueriedBounds` from `map.getBounds()`
      // at that same tight zoom meant the very first freshness poll
      // (below) silently replaced the full loaded `events` set with just
      // the one or two events inside that tiny box — every other pin
      // vanished a few seconds after opening, independent of any filter
      // tap (a filter tap merely made the already-collapsed dataset's
      // narrowing visible). A wide box around the same center — matching
      // the density-hotspot default's own city-wide feel — keeps the data
      // query broad while the map still visually zooms in tight on the pin.
      lastQueriedBounds.current = restored?.singleEventFocus
        ? { getNorth: () => center.lat + 0.06, getSouth: () => center.lat - 0.06, getEast: () => center.lng + 0.06, getWest: () => center.lng - 0.06 }
        : map.getBounds();
      mapRef.current = map;
      // Test-only hook (Task 2b, 11-realtime-map.md follow-up) — there's no
      // other way for Playwright to read the live map's own center/zoom
      // from outside; never read by any app code.
      if (typeof window !== 'undefined') window.__mapExploreMapForTests = map;
    })();
    return () => {
      active = false;
      if (typeof window !== 'undefined' && window.__mapExploreMapForTests === mapRef.current) {
        window.__mapExploreMapForTests = null;
      }
      mapRef.current?.remove();
      mapRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ---- freshness poll: re-query current view on the same cadence as the rest of the app ----
  useEffect(() => {
    const interval = setInterval(async () => {
      const bounds = lastQueriedBounds.current ? boundsToBox(lastQueriedBounds.current) : null;
      const fresh = await fetchLiveEvents({ bounds });
      setEvents(fresh);
    }, POLL_MS);
    return () => clearInterval(interval);
  }, []);

  // ---- draw/refresh pins whenever the event list or selection changes ----
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    markersRef.current.forEach(m => m.remove());
    markersRef.current = [];
    let cancelled = false;
    (async () => {
      const maplibregl = await import('maplibre-gl');
      if (cancelled) return;
      for (const ev of events) {
        const isSelected = ev.id === selectedId;
        // Follow-up (11-realtime-map.md, "first post-return polling cycle
        // does not reset map state"): a real, confirmed, pre-existing bug —
        // MapLibre's own `Marker._update()` unconditionally OVERWRITES
        // `this._element.style.transform` (translate-for-position only, no
        // scale) every time it's called, which happens synchronously
        // inside `addTo()` itself, not just on a later `move`. Since every
        // poll tick rebuilds every marker from scratch (`markersRef.current
        // .forEach(m => m.remove())` above, then brand-new `el`s here),
        // whichever pin stays selected got a FRESH element with no ongoing
        // `gocPinPop` animation (deliberately not replayed — see below) to
        // paper over this: previously the SAME `el` carried both our own
        // inline `transform:scale(...)` AND Marker's position transform,
        // and only the pop keyframe's `fill-mode: both` accidentally kept
        // the scale visible after the FIRST selection (a running CSS
        // animation's computed value overrides a later plain inline-style
        // write to the same property) — the instant a later poll rebuilt
        // the marker with no animation to replay, Marker's own `_update()`
        // silently wiped the scale back to identity with nothing left to
        // mask it. Fixed at the root: the scale/animation/border/shadow
        // styling now lives on an INNER child div (`pinEl`) that Marker
        // never touches at all — `el` (the one actually handed to
        // `new Marker({element: el})`) stays a plain, transform-free
        // positioning shell, so Marker is free to fully own its own
        // transform forever without erasing anything of ours.
        const el = document.createElement('div');
        el.style.cssText = 'position:relative;';
        const pinEl = document.createElement('div');
        pinEl.style.cssText = `width:30px;height:30px;border-radius:50%;background:${paper};border:1.5px solid ${ink};display:flex;align-items:center;justify-content:center;font-size:14px;cursor:pointer;box-shadow:${isSelected ? `0 0 0 3px ${ink}, ` : ''}0 2px 6px rgba(27,25,22,0.3);transform:scale(${isSelected ? 1.15 : 1});z-index:${isSelected ? 1 : 0};`;
        pinEl.setAttribute('data-testid', `map-pin-${ev.id}`);
        pinEl.textContent = CAT_GLYPH[ev.catKey] || CAT_GLYPH.all;
        if (ev.urgent || ev.isNew) {
          const dot = document.createElement('span');
          dot.style.cssText = `position:absolute;top:-2px;right:-2px;width:9px;height:9px;border-radius:50%;background:${ev.urgent ? '#9A3E2D' : '#48582F'};border:1.5px solid ${paper};`;
          pinEl.appendChild(dot);
        }
        if (isSelected && lastAnimatedPinIdRef.current !== ev.id) {
          pinEl.style.animation = 'gocPinPop 0.32s cubic-bezier(.22,.61,.36,1) both';
          lastAnimatedPinIdRef.current = ev.id;
        }
        pinEl.addEventListener('click', (e) => { e.stopPropagation(); selectEvent(ev); });
        el.appendChild(pinEl);
        const marker = new maplibregl.Marker({ element: el }).setLngLat([ev.lng, ev.lat]).addTo(map);
        markersRef.current.push(marker);
      }
    })();
    return () => { cancelled = true; };
  }, [events, selectedId, selectEvent]);

  const searchHere = useCallback(async () => {
    const map = mapRef.current;
    if (!map) return;
    const bounds = boundsToBox(map.getBounds());
    lastQueriedBounds.current = map.getBounds();
    setBoundsChanged(false);
    setPage(0);
    setLoading(true);
    const fresh = await fetchLiveEvents({ bounds });
    setEvents(fresh);
    setLoading(false);
  }, []);

  const loadMore = useCallback(async () => {
    const next = page + 1;
    const bounds = lastQueriedBounds.current ? boundsToBox(lastQueriedBounds.current) : null;
    const more = await fetchLiveEvents({ bounds, offset: next * 60 });
    if (more.length) { setEvents(prev => [...prev, ...more]); setPage(next); }
  }, [page]);

  const visibleEvents = useMemo(() => {
    let list = events;
    if (catFilter !== 'all') list = list.filter(e => e.catKey === catFilter);
    if (openNowOnly) list = list.filter(e => e.seatsRemaining > 0);
    if (sortByDistance && s.userCoords) {
      list = [...list].sort((a, b) => haversineKm(s.userCoords, a) - haversineKm(s.userCoords, b));
    }
    return list;
  }, [events, catFilter, openNowOnly, sortByDistance, s.userCoords]);

  // Design change (11-realtime-map.md follow-up): the selected event's
  // preview card is intentionally decoupled from the list's active filter.
  // This used to read `visibleEvents` (the FILTERED list) — meaning
  // selecting an event, then tapping ANY filter chip (including "Tất cả"
  // itself, since the underlying `events`/`visibleEvents` identity changes
  // on every render regardless), silently cleared the card the instant the
  // selection didn't happen to match whatever filter was now active.
  // Reading the FULL, unfiltered `events` here instead — the exact same
  // data source the map's own pins already draw from regardless of
  // category (see the marker-drawing effect below, `for (const ev of
  // events)`, never `visibleEvents`) — means a selection now persists
  // through any filter change, and (since this is the ONLY place
  // `visibleEvents` fed into the selection at all) a current selection can
  // never narrow or otherwise affect what the list itself shows either.
  const selectedEvent = useMemo(
    () => (selectedId ? events.find(e => e.id === selectedId) || null : null),
    [events, selectedId],
  );

  // Task 2b (11-realtime-map.md follow-up): reuses the EXACT SAME
  // `densityHotspot` import the initial-load effect above calls, scoped
  // here to `visibleEvents` (already reflecting the just-changed
  // `catFilter`, plus whichever other filters are active) instead of every
  // loaded event, so the camera moves to wherever THIS filter's own
  // results are most concentrated. `catFilterMountedRef` mirrors iOS's
  // `.onChange` semantics (never fires for the value a mount starts with,
  // only for a later, genuine change) — `useEffect` itself has no such
  // built-in distinction, so it's done explicitly here.
  const catFilterMountedRef = useRef(false);
  useEffect(() => {
    if (!catFilterMountedRef.current) { catFilterMountedRef.current = true; return; }
    const map = mapRef.current;
    if (!map) return;
    const points = visibleEvents.map(e => ({ lat: e.lat, lng: e.lng }));
    const center = densityHotspot(points);
    if (!center) return; // no matching events for this filter — leave the camera where it is
    map.flyTo({ center: [center.lng, center.lat], zoom: 13, duration: 700 });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [catFilter]);

  // Design change (11-realtime-map.md follow-up): this effect used to key
  // off `visibleEvents` (via the old `selectedEvent` derivation above) —
  // the FILTERED list — which meant a category/open-now filter change, or
  // even re-selecting "Tất cả", could silently clear an unrelated
  // selection the instant it didn't match whatever filter was now active.
  // That coupling is removed entirely, not just patched: `selectedEvent`
  // is now derived from the FULL, unfiltered `events` (above), so this
  // effect only ever clears the selection because the underlying event
  // itself is genuinely gone from the loaded data — cancelled, deleted, or
  // (a poll re-query) no longer inside whatever bounds were last queried —
  // never merely because it doesn't match the active category/open-now
  // filter. No second query: this still only ever reads the same `events`
  // the map's own pins already draw from regardless of filter.
  //
  // Guarded on `!loading`: a restored `selectedId` (bug 2) is set on the
  // very first render, before the initial fetchLiveEvents() call has
  // resolved — `events` is still `[]` at that instant, so `selectedEvent`
  // is momentarily null too. Without this guard, that
  // transient "not loaded yet" state was indistinguishable from "genuinely
  // filtered out" and cleared the restored selection before its own data
  // even arrived, every single time.
  useEffect(() => {
    if (!loading && selectedId && !selectedEvent) setSelectedId(null);
  }, [loading, selectedId, selectedEvent]);

  // Bug 2: best-effort list-scroll restore — once, the first time the list
  // actually has rows to scroll through. A plain scrollTop pixel value
  // (unlike a SwiftUI List's opaque scroll position) round-trips exactly
  // on web, so this restores precisely rather than approximately.
  useEffect(() => {
    if (listScrollRestoredRef.current) return;
    if (!restored?.listScrollTop || visibleEvents.length === 0) return;
    if (listRef.current) listRef.current.scrollTop = restored.listScrollTop;
    listScrollRestoredRef.current = true;
  }, [visibleEvents, restored]);

  // Bug 1 (camera half): "the selected pin must remain visible ... at all
  // detents" — re-applies the padding (not the center/zoom, so this never
  // re-triggers the selection pop or re-centers unnecessarily) whenever the
  // sheet's snap state itself changes while something stays selected, e.g.
  // selecting at "tall" then switching to "List nhỏ" afterward.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !selectedEvent) return;
    const sheetPx = window.innerHeight * (1 - mapStripFraction);
    const CARD_ALLOWANCE = 150;
    map.easeTo({ padding: { top: 80, bottom: sheetPx + CARD_ALLOWANCE, left: 30, right: 30 }, duration: 300 });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sheetSnap]);

  // Bug 2: snapshot everything MapExplore itself owns right before handing
  // off to the full-screen Event Detail screen, so returning restores it
  // instead of re-initializing from scratch. Saved into GocContext (not
  // local state) because App.jsx's Shell unmounts this whole component the
  // instant `screen` changes away from 'mapExplore'.
  const openEventDetail = useCallback((id) => {
    const map = mapRef.current;
    const center = map?.getCenter();
    setMapExploreState({
      cameraCenter: center ? { lat: center.lat, lng: center.lng } : null,
      cameraZoom: map?.getZoom() ?? null,
      sheetSnap,
      catFilter,
      openNowOnly,
      sortByDistance,
      selectedId,
      listScrollTop: listRef.current?.scrollTop ?? 0,
    });
    goEvent(id);
  }, [sheetSnap, catFilter, openNowOnly, sortByDistance, selectedId, goEvent, setMapExploreState]);

  // Task 1 (11-realtime-map.md follow-up): web has no edge-swipe-back
  // gesture at all (confirmed by inspection, App.jsx's Shell has no
  // dual-rendering/backdrop concept the way RootView's edge-swipe does on
  // iOS) — the only Map-Explore-closing-to-Home trigger here is this
  // button, so there's no "live drag progress" to track. This gives the
  // button the same shrink/bubble VISUAL as iOS's button+swipe both get
  // (see `cardBottomPx`'s sibling `closingProgress` below), just without a
  // gesture behind it — animate to fully closed, THEN actually navigate,
  // matching iOS's own button timing (`closeMap()` there).
  const [closingProgress, setClosingProgress] = useState(0);

  // An explicit exit (as opposed to "on my way to Event Detail, be right
  // back") clears the snapshot — reopening the map later from Home should
  // start fresh, not silently resume a session from an unrelated visit.
  const closeMap = useCallback(() => {
    setClosingProgress(1);
    // Matches the sheet's own `transform` transition duration (0.42s, the
    // same bounce curve the restore-only bubble already uses) so the
    // shrink actually finishes playing before this component unmounts,
    // rather than being cut short partway through.
    setTimeout(() => {
      setMapExploreState(null);
      backFromMapExplore();
    }, 420);
  }, [setMapExploreState, backFromMapExplore]);

  // ---- drag-to-resize bottom sheet (pointer events, translateY, snap on release) ----
  const sheetRef = useRef(null);
  const dragState = useRef(null);

  const onHandlePointerDown = (e) => {
    dragState.current = { startY: e.clientY, startSnap: SHEET_SNAPS[sheetSnap] };
    // Capture on the handle itself (`e.currentTarget`, the element this
    // handler is actually attached to) — capturing on `sheetRef`'s outer
    // container instead was a real, pre-existing bug: pointer capture
    // retargets subsequent pointermove/pointerup events to the CAPTURING
    // element and bubbles from there, so with the sheet (an ancestor of
    // this handle) as the capture target, those events could never reach
    // this handle's own onPointerMove/onPointerUp at all — the drag never
    // progressed past the very first pixel. Confirmed by instrumenting a
    // real drag end-to-end (the sheet's own `top` never changed no matter
    // how far or slow the drag), not just inferred from reading the code.
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const onHandlePointerMove = (e) => {
    if (!dragState.current) return;
    const deltaVh = ((e.clientY - dragState.current.startY) / window.innerHeight);
    setDragOffsetVh(deltaVh);
  };
  const onHandlePointerUp = () => {
    if (!dragState.current) return;
    const current = dragState.current.startSnap + dragOffsetVh;
    const nearest = Object.entries(SHEET_SNAPS).reduce((best, [key, val]) =>
      Math.abs(val - current) < Math.abs(SHEET_SNAPS[best] - current) ? key : best, 'tall');
    setSheetSnap(nearest);
    setDragOffsetVh(0);
    dragState.current = null;
  };

  const compassOpacity = locPermission === 'granted' ? 1 : DISABLED_OPACITY;

  // ANIMATION REQUIREMENT (11-realtime-map.md follow-up): a soft "bubble"
  // settle for the sheet, but ONLY on a genuine restore — `bubbleIn` starts
  // `true` exclusively when this mount received a `restored` snapshot (the
  // same one-shot `restoredRef`/`restored` read used for every other bug 2
  // field above), and is flipped to `false` exactly once via the effect
  // below, never touched again by a filter change or the 5s poll. A fresh
  // (non-restored) open starts at `false` already, so it never bubbles.
  const [bubbleIn, setBubbleIn] = useState(() => !!restored);
  useEffect(() => {
    if (!bubbleIn) return;
    // Double rAF: the initial (offset) inline style needs to actually
    // paint on screen for at least one frame before flipping the state
    // that removes it, or the browser can coalesce both style values into
    // the same paint and the CSS `transition` below never has a "from"
    // state to animate away from.
    const raf1 = requestAnimationFrame(() => {
      requestAnimationFrame(() => setBubbleIn(false));
    });
    return () => cancelAnimationFrame(raf1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div style={{ position: 'fixed', inset: 0, background: paper }} data-screen-label="MapExplore">
      <div ref={mapDivRef} style={{ position: 'absolute', inset: 0 }} />

      {/* Follow-up discovery (11-realtime-map.md): maplibre-gl.css gives its
          own `.maplibregl-ctrl-top-right` an explicit `z-index: 2` — this
          screen's own floating controls had no z-index at all (defaulting
          to the same stacking level as the plain map container), so the
          library's own zoom +/- control (added below, `top-right`) was
          silently sitting ON TOP of the compass button in that exact
          corner, intercepting real clicks/taps meant for it. Confirmed via
          `document.elementFromPoint` at the compass's own center returning
          the maplibre control's icon, not this button. `zIndex: 3` on all
          three of this screen's own floating pills — not just the compass —
          for consistency, since any of them sharing a corner with a future
          maplibre control would have the identical problem. */}
      {/* Follow-up (11-realtime-map.md, bug 2): this used to omit
          `fontWeight` (falling back to the browser default, normal/400)
          and use a narrower `padding` ('8px 12px') than "Tìm ở đây" below
          (600/'8px 16px') — same `photoPill()` base (background/color
          token), so the two never actually differed in color by value,
          but the lighter weight read as a visibly different tint at a
          glance. Matched to "Tìm ở đây"'s own padding/fontWeight exactly
          (fontSize was already 12 by default from `photoPill()`, so no
          change needed there) — same height, same look, no new token. */}
      <div ref={backRef} onClick={closeMap} data-testid="map-back" style={{ ...photoPill({}), top: 16, left: 16, padding: '8px 16px', fontWeight: 600, zIndex: 3 }}>
        ← {T('Đóng', 'Close')}
      </div>

      <div
        ref={compassRef}
        onClick={recenterOnUser}
        data-testid="map-compass"
        style={{ ...photoPill({}), top: 16, right: 16, width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18, opacity: compassOpacity, zIndex: 3 }}
      >
        🧭
      </div>

      {boundsChanged && (
        <div
          ref={searchHereRef}
          onClick={searchHere}
          data-testid="map-search-here"
          style={{ ...photoPill({}), top: 16, left: '50%', transform: 'translateX(-50%)', padding: '8px 16px', fontSize: 12, fontWeight: 600, zIndex: 3 }}
        >
          {T('Tìm ở đây', 'Search here')}
        </div>
      )}

      {/* Compact in-map preview — never a full-screen modal. Anchored to the
          card's own two-state anchor (bug 1: "upper" for both tall/mid so
          it never gets pulled down mid-screen just because the sheet moved
          to mid; "lower", tucked above the sheet, only once the sheet is
          genuinely at peek) — not the sheet's continuously-dragged
          position, which is what caused the card to slide down early. */}
      {selectedEvent && (
        <div
          ref={cardRef}
          data-testid="map-selected-card"
          style={{
            ...cardGlass({}), position: 'absolute', left: 16, right: 16,
            bottom: cardBottomPx,
            transition: 'bottom 0.28s cubic-bezier(.22,.61,.36,1)',
            padding: 12, display: 'flex', flexDirection: 'column', gap: 10,
            boxShadow: '0 10px 28px rgba(27,25,22,0.22)',
          }}
        >
          {/* Task 4 (11-realtime-map.md follow-up): tapping anywhere in this
              non-CTA row re-flies the camera back to the selected event —
              reuses `selectEvent(_)` verbatim (the exact same fly/zoom
              logic used when the event was first selected), not a new
              camera animation. The "×" close span (a descendant of this
              row) calls `e.stopPropagation()` first so it doesn't ALSO
              trigger this recenter on its way up; the CTA button below is a
              separate sibling div, never a descendant, so it needs no such
              guard. */}
          <div
            onClick={() => selectEvent(selectedEvent)}
            data-testid="map-card-recenter"
            style={{ display: 'flex', gap: 10, cursor: 'pointer' }}
          >
            {selectedEvent.img && (
              <div data-testid="map-card-photo" style={{ backgroundImage: `url(${selectedEvent.img})`, backgroundSize: 'cover', backgroundPosition: 'center', width: 64, height: 64, borderRadius: 10, flexShrink: 0 }} />
            )}
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 }}>
                <div data-testid="map-card-title" style={{ fontSize: 14, fontWeight: 700, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{selectedEvent.name}</div>
                <span
                  onClick={(e) => { e.stopPropagation(); clearSelection(); }}
                  data-testid="map-card-close"
                  style={{ cursor: 'pointer', color: ink, opacity: 0.5, fontSize: 18, lineHeight: 1, flex: 'none' }}
                >×</span>
              </div>
              <div style={{ fontSize: 11, color: ink, opacity: 0.65, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {[selectedEvent.when, selectedEvent.area].filter(Boolean).join(' ▪︎ ')}
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 6 }}>
                {selectedEvent.price && <span style={{ fontSize: 13, color: ink, fontWeight: 600 }}>{selectedEvent.price}</span>}
                <span style={{ fontSize: 11, fontWeight: 600, color: selectedEvent.soldOut ? alert : ink }}>
                  {selectedEvent.soldOut ? T('Hết chỗ', 'Sold out') : T('Còn chỗ', 'Available')}
                </span>
              </div>
            </div>
          </div>
          <div
            onClick={() => openEventDetail(selectedEvent.id)}
            data-testid="map-card-cta"
            style={{ ...inkButton({}), padding: '10px 0', fontSize: 13 }}
          >
            {T('Xem chi tiết', 'View details')}
          </div>
        </div>
      )}

      <div
        ref={sheetRef}
        data-testid="map-sheet"
        style={{
          position: 'absolute', left: 0, right: 0, bottom: 0, top: `${sheetTopVh}vh`,
          background: paper, borderRadius: '20px 20px 0 0', boxShadow: '0 -6px 24px rgba(27,25,22,0.18)',
          display: 'flex', flexDirection: 'column',
          // ANIMATION REQUIREMENT: the extra `transform` (only non-identity
          // while `bubbleIn`) is what gives a restore its soft overshoot —
          // `cubic-bezier(0.34, 1.56, 0.64, 1)` is a standard "back out"
          // curve (briefly overshoots past 1 before settling), the closest
          // CSS-easing equivalent of the iOS build's
          // `.interpolatingSpring` for the same restore-only bubble. `top`
          // keeps its own existing drag-snap easing, untouched. Task 1
          // follow-up: `closingProgress` (only ever non-zero while
          // `closeMap()` is in flight) composes into the SAME transform,
          // shrinking the sheet down as it closes — see `closeMap()`'s own
          // comment for why web only has a button trigger for this, not a
          // live-tracked drag.
          transform: `translateY(${(bubbleIn ? 14 : 0) + 70 * closingProgress}px) scale(${(bubbleIn ? 0.985 : 1) * (1 - 0.15 * closingProgress)})`,
          transition: dragState.current
            ? 'none'
            : 'top 0.28s cubic-bezier(.22,.61,.36,1), transform 0.42s cubic-bezier(0.34, 1.56, 0.64, 1)',
        }}
      >
        {/* Bug 3: `touchAction: 'none'` used to sit on the WHOLE sheet div
            above — since touch-action's "used value" for a touch is the
            intersection of the touched element's own value AND every
            ancestor's, an ancestor declaring 'none' disables native touch
            scrolling for every descendant too, including the list further
            down, regardless of that list's own (default/auto) touch-action.
            That's what made the list unscrollable at mid: the drag-vs-scroll
            *pointer handlers* were already correctly scoped to just this
            handle (never attached to the sheet or the list), only the CSS
            was too broad. Scoping `touchAction: 'none'` to just this small
            handle element — the only thing that actually needs to suppress
            the browser's native pan/scroll to do its own pointer-based
            drag — leaves the list with its default touch-action, so it
            scrolls normally at every detent. */}
        <div
          onPointerDown={onHandlePointerDown}
          onPointerMove={onHandlePointerMove}
          onPointerUp={onHandlePointerUp}
          data-testid="map-sheet-handle"
          style={{ padding: '10px 0 6px', display: 'flex', justifyContent: 'center', cursor: 'grab', touchAction: 'none' }}
        >
          <div style={{ width: 36, height: 4, borderRadius: 2, background: rule }} />
        </div>

        {/* Primary, always-present control for the list/map balance — the
            drag handle above still works as an additional way to move
            between snap points, but these two buttons are the explicit,
            tap-driven way, per the ticket. "tall" (list large, small map
            strip) is today's default; "peek" (list small, map large) was
            previously only reachable by dragging all the way down. */}
        <div style={{ display: 'flex', gap: 8, padding: '0 16px 10px' }}>
          <div
            onClick={() => setSheetSnap('tall')}
            data-testid="map-sheet-list-large"
            style={{ ...fieldGlass({}), flex: 1, textAlign: 'center', padding: '7px 0', fontSize: 12, cursor: 'pointer', color: ink, fontWeight: sheetSnap === 'tall' ? 700 : 400, border: sheetSnap === 'tall' ? `1px solid ${ink}` : 'none' }}
          >
            {T('List lớn', 'Big list')}
          </div>
          <div
            onClick={() => setSheetSnap('peek')}
            data-testid="map-sheet-list-small"
            style={{ ...fieldGlass({}), flex: 1, textAlign: 'center', padding: '7px 0', fontSize: 12, cursor: 'pointer', color: ink, fontWeight: sheetSnap === 'peek' ? 700 : 400, border: sheetSnap === 'peek' ? `1px solid ${ink}` : 'none' }}
          >
            {T('List nhỏ', 'Big map')}
          </div>
        </div>

        {/* Task 2a (11-realtime-map.md follow-up): wraps onto as many rows
            as needed instead of requiring horizontal scrolling to see
            every category — every filter is visible up front now. */}
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, padding: '0 16px 10px' }}>
          {FILTER_DEFS.map(f => (
            <div
              key={f.key}
              onClick={() => setCatFilter(f.key)}
              data-testid={`map-cat-${f.key}`}
              style={{ ...fieldGlass({}), padding: '6px 12px', fontSize: 12, whiteSpace: 'nowrap', cursor: 'pointer', color: ink, fontWeight: catFilter === f.key ? 700 : 400, border: catFilter === f.key ? `1px solid ${ink}` : 'none' }}
            >
              {CAT_GLYPH[f.key]} {T(f.vi, f.en)}
            </div>
          ))}
        </div>

        <div style={{ display: 'flex', gap: 8, padding: '0 16px 10px' }}>
          <div
            onClick={() => setOpenNowOnly(v => !v)}
            data-testid="map-chip-open-now"
            style={{ ...fieldGlass({}), padding: '5px 10px', fontSize: 11, cursor: 'pointer', color: ink, fontWeight: openNowOnly ? 700 : 400 }}
          >
            {T('Còn chỗ', 'Open now')}
          </div>
          {locPermission === 'granted' && (
            <div
              onClick={() => setSortByDistance(v => !v)}
              data-testid="map-chip-nearby"
              style={{ ...fieldGlass({}), padding: '5px 10px', fontSize: 11, cursor: 'pointer', color: ink, fontWeight: sortByDistance ? 700 : 400 }}
            >
              {T('Gần bạn', 'Nearby')}
            </div>
          )}
        </div>

        <div
          ref={listRef}
          data-testid="map-list-scroll"
          style={{ flex: 1, overflowY: 'auto', padding: '0 16px 24px' }}
          onScroll={(e) => {
            const el = e.currentTarget;
            if (el.scrollHeight - el.scrollTop - el.clientHeight < 120) loadMore();
          }}
        >
          {loading && visibleEvents.length === 0 && <div style={{ padding: 20, color: ink, opacity: 0.6, fontSize: 13 }}>{T('Đang tải…', 'Loading…')}</div>}
          {!loading && visibleEvents.length === 0 && <div style={{ padding: 20, color: ink, opacity: 0.6, fontSize: 13 }}>{T('Không có sự kiện nào ở khu vực này.', 'No events in this area.')}</div>}
          {visibleEvents.map(ev => (
            <div
              key={ev.id}
              onClick={() => selectEvent(ev)}
              data-testid={`map-list-item-${ev.id}`}
              style={{ display: 'flex', gap: 12, padding: '10px 0', borderBottom: `1px solid ${rule}`, cursor: 'pointer', alignItems: 'center' }}
            >
              {ev.img && <div style={{ width: 52, height: 52, borderRadius: 10, backgroundImage: `url(${ev.img})`, backgroundSize: 'cover', backgroundPosition: 'center', flexShrink: 0 }} />}
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 600, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ev.name}</div>
                <div style={{ fontSize: 11, color: ink, opacity: 0.6 }}>
                  {ev.area}
                  {/* Task 3 (11-realtime-map.md follow-up): shown whenever
                      location permission is already granted, independent
                      of "Gần bạn" — that chip still only controls
                      SORTING/filtering by distance, unchanged; this is
                      purely about whether the km figure is DISPLAYED. */}
                  {/* BUG 2 (2026-09-22 tenth follow-up) — now built on the
                      SAME canonical `distanceLabel()` helper EventDetail's
                      `stripKm()` and the story card use, instead of its own
                      separate `.toFixed(1)` (which also silently used a
                      dot decimal, "2.3 km", instead of this app's
                      Vietnamese comma convention every other km display
                      uses — a real, if minor, formatting divergence this
                      also fixes). */}
                  {(() => { const d = (sortByDistance || locPermission === 'granted') ? distanceLabel(s.userCoords, true, ev) : null; return d ? ` ▪︎ ${d}` : ''; })()}
                </div>
              </div>
              {ev.price && <div style={{ fontSize: 12, color: ink, whiteSpace: 'nowrap' }}>{ev.price}</div>}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function boundsToBox(bounds) {
  return { north: bounds.getNorth(), south: bounds.getSouth(), east: bounds.getEast(), west: bounds.getWest() };
}
