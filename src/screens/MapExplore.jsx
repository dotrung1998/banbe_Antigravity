import { useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { supabase } from '../lib/supabase.js';
import { findEvent, haversineKm } from '../data/events.js';
import { densityHotspot } from '../lib/densityHotspot.js';
import { FILTER_DEFS } from './Home.jsx';
import { paper, ink, rule, photoPill, fieldGlass } from '../theme.js';
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
      urgent: row.seats_remaining != null && row.seats_remaining <= 5,
      isNew: cosmetic ? cosmetic.until != null && cosmetic.until <= 1 : false,
    };
  });
}

export default function MapExplore() {
  const { state: s, T, goEvent, backFromMapExplore, allowLocation } = useGoc();
  const mapDivRef = useRef(null);
  const mapRef = useRef(null);
  const markersRef = useRef([]);
  const [events, setEvents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [catFilter, setCatFilter] = useState('all');
  const [openNowOnly, setOpenNowOnly] = useState(false);
  const [sortByDistance, setSortByDistance] = useState(false);
  const [sheetSnap, setSheetSnap] = useState('tall');
  const [boundsChanged, setBoundsChanged] = useState(false);
  const [page, setPage] = useState(0);
  const lastQueriedBounds = useRef(null);

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

  // ---- initial load: density-hotspot center (never the user's own GPS), then draw the map ----
  useEffect(() => {
    let active = true;
    (async () => {
      const initial = await fetchLiveEvents({});
      if (!active) return;
      setEvents(initial);
      setLoading(false);

      const center = densityHotspot(initial.map(e => ({ lat: e.lat, lng: e.lng }))) || { lat: 10.7769, lng: 106.7009 };

      // maplibre-gl 6.x ships pure named ESM exports — there is no
      // `default` export. `(await import(...)).default` was silently
      // `undefined`, so `new maplibregl.Map(...)` threw and the map never
      // initialized (11-realtime-map.md: "web map doesn't render at all").
      const maplibregl = await import('maplibre-gl');
      if (!active || !mapDivRef.current || mapRef.current) return;

      const map = new maplibregl.Map({
        container: mapDivRef.current,
        style: 'https://tiles.openfreemap.org/styles/positron',
        center: [center.lng, center.lat],
        zoom: 13,
      });
      map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
      map.on('moveend', () => {
        if (!lastQueriedBounds.current) { lastQueriedBounds.current = map.getBounds(); return; }
        setBoundsChanged(true);
      });
      lastQueriedBounds.current = map.getBounds();
      mapRef.current = map;
    })();
    return () => { active = false; mapRef.current?.remove(); mapRef.current = null; };
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

  // ---- draw/refresh pins whenever the event list changes ----
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
        const el = document.createElement('div');
        el.style.cssText = `width:30px;height:30px;border-radius:50%;background:${paper};border:1.5px solid ${ink};display:flex;align-items:center;justify-content:center;font-size:14px;cursor:pointer;box-shadow:0 2px 6px rgba(27,25,22,0.3);position:relative;`;
        el.textContent = CAT_GLYPH[ev.catKey] || CAT_GLYPH.all;
        if (ev.urgent || ev.isNew) {
          const dot = document.createElement('span');
          dot.style.cssText = `position:absolute;top:-2px;right:-2px;width:9px;height:9px;border-radius:50%;background:${ev.urgent ? '#9A3E2D' : '#48582F'};border:1.5px solid ${paper};`;
          el.appendChild(dot);
        }
        el.addEventListener('click', () => goEvent(ev.id));
        const marker = new maplibregl.Marker({ element: el }).setLngLat([ev.lng, ev.lat]).addTo(map);
        markersRef.current.push(marker);
      }
    })();
    return () => { cancelled = true; };
  }, [events, goEvent]);

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

  // ---- drag-to-resize bottom sheet (pointer events, translateY, snap on release) ----
  const sheetRef = useRef(null);
  const dragState = useRef(null);
  const [dragOffsetVh, setDragOffsetVh] = useState(0);

  const onHandlePointerDown = (e) => {
    dragState.current = { startY: e.clientY, startSnap: SHEET_SNAPS[sheetSnap] };
    sheetRef.current?.setPointerCapture(e.pointerId);
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

  const mapStripFraction = Math.min(0.95, Math.max(0.05, SHEET_SNAPS[sheetSnap] + dragOffsetVh));
  const sheetTopVh = mapStripFraction * 100;

  const compassOpacity = locPermission === 'granted' ? 1 : DISABLED_OPACITY;

  return (
    <div style={{ position: 'fixed', inset: 0, background: paper }} data-screen-label="MapExplore">
      <div ref={mapDivRef} style={{ position: 'absolute', inset: 0 }} />

      <div onClick={backFromMapExplore} data-testid="map-back" style={{ ...photoPill({}), top: 16, left: 16, padding: '8px 12px' }}>
        ← {T('Đóng', 'Close')}
      </div>

      <div
        onClick={recenterOnUser}
        data-testid="map-compass"
        style={{ ...photoPill({}), top: 16, right: 16, width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18, opacity: compassOpacity }}
      >
        🧭
      </div>

      {boundsChanged && (
        <div
          onClick={searchHere}
          data-testid="map-search-here"
          style={{ ...photoPill({}), top: 16, left: '50%', transform: 'translateX(-50%)', padding: '8px 16px', fontSize: 12, fontWeight: 600 }}
        >
          {T('Tìm ở đây', 'Search here')}
        </div>
      )}

      <div
        ref={sheetRef}
        style={{
          position: 'absolute', left: 0, right: 0, bottom: 0, top: `${sheetTopVh}vh`,
          background: paper, borderRadius: '20px 20px 0 0', boxShadow: '0 -6px 24px rgba(27,25,22,0.18)',
          display: 'flex', flexDirection: 'column', touchAction: 'none',
          transition: dragState.current ? 'none' : 'top 0.28s cubic-bezier(.22,.61,.36,1)',
        }}
      >
        <div
          onPointerDown={onHandlePointerDown}
          onPointerMove={onHandlePointerMove}
          onPointerUp={onHandlePointerUp}
          data-testid="map-sheet-handle"
          style={{ padding: '10px 0 6px', display: 'flex', justifyContent: 'center', cursor: 'grab' }}
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

        <div style={{ display: 'flex', gap: 8, padding: '0 16px 10px', overflowX: 'auto' }}>
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
              onClick={() => goEvent(ev.id)}
              data-testid={`map-list-item-${ev.id}`}
              style={{ display: 'flex', gap: 12, padding: '10px 0', borderBottom: `1px solid ${rule}`, cursor: 'pointer', alignItems: 'center' }}
            >
              {ev.img && <div style={{ width: 52, height: 52, borderRadius: 10, backgroundImage: `url(${ev.img})`, backgroundSize: 'cover', backgroundPosition: 'center', flexShrink: 0 }} />}
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 600, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ev.name}</div>
                <div style={{ fontSize: 11, color: ink, opacity: 0.6 }}>
                  {ev.area}
                  {sortByDistance && s.userCoords && haversineKm(s.userCoords, ev) != null ? ` ▪︎ ${haversineKm(s.userCoords, ev).toFixed(1)} km` : ''}
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
