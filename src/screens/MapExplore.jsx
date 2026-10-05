import { screenHeight } from '../lib/viewport.js';
import { useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { useGoc, resolveCoverUrl, firstPhotoUrlByEvent } from '../state/GocContext.jsx';
import { supabase } from '../lib/supabase.js';
import { findEvent, isCosmeticCatalogMatch, haversineKm, distanceLabel } from '../data/events.js';
import { liveEventOverrides } from '../lib/countdown.js';
import { formatVnd } from '../lib/paymentDocument.js';
import { densityHotspot } from '../lib/densityHotspot.js';
import { buildEventSearchDoc, matchesSearchQuery } from '../lib/search.js';
import { FILTER_DEFS } from './Home.jsx';
import { paper, ink, rule, alert, photoPill, fieldGlass, cardGlass, inkButton } from '../theme.js';
import RootRefreshIndicator from './RootRefreshIndicator.jsx';
import 'maplibre-gl/dist/maplibre-gl.css';

// Category glyph per FILTER_DEFS key — no icon set exists anywhere else in
// this app (see .claude/notes/11-realtime-map.md), so these are plain
// minimal glyphs rather than an invented illustrated icon language.
const CAT_GLYPH = { all: '▪︎', supper: '🍽️', fashion: '👗', gallery: '🖼️', music: '🎵' };

// Map filters pass (2026-09-27) — "each event's own existing palette
// color, not the same color for every event": this app has no prior
// per-category color anywhere (grepped both platforms before adding
// this) — three of these four ARE an existing app palette, reused
// verbatim: Home.jsx's own Pulse-ring gradient (`bb-pulse-ring`, the same
// dusty-rose/sand/sage trio already shown on the Pulse entry). FILTER_DEFS
// has one more non-"all" category (music) than that trio has colors, so
// one additional muted tone was added in the same dusty/desaturated
// family (never a saturated/rainbow color, matching this app's whole
// palette) rather than reusing one of the three for two different
// categories, which would defeat "not the same color for every event."
// Keyed by the SAME FILTER_DEFS category keys the filter chips already
// use, so a dot's color always matches its own event's real category.
const CAT_DOT_COLOR = {
  all: ink, supper: '#E7C9C2', fashion: '#E3CFA6', gallery: '#C8CBB2', music: '#B7A6C7',
};

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
    // Keyword-search fix (migration 108) — re-enabled 2026-09-29, see
    // REAL_EVENT_ROW_COLUMNS's own doc comment (GocContext.jsx) for why it
    // was briefly reverted and how its return was verified.
    // Search-matcher fix (Issue 2) — `cat_label`, `description`, `intro`
    // and the event's own organizer name are now selected too, so the
    // search document built below (`buildEventSearchDoc`) can include
    // category/organizer/description text regardless of whether
    // `keywords` happens to be populated for a given row.
    .select('id, key, name, cat_key, cat_label, area, city, lat, lng, starts_at, event_date, event_time, price_vnd, seats_remaining, status, cover_image, keywords, description, intro, country_code, state_province, neighborhood, organizers(name)')
    .eq('status', 'live')
    // Strict invite-only events (2026-10-25): unlike loadWeekendEvents/
    // loadDiscoveryEvents (GocContext.jsx), this query never filtered
    // visibility at all — a real invite-only event would have shown up
    // on the Map for anyone. RLS (migration 113) is the actual backstop
    // now, but this list should stay honest client-side too: an invitee
    // sees their own invite-only event on the Map through EventDetail/
    // deep link, never through discovery search.
    .eq('visibility', 'public')
    .order('starts_at', { ascending: true })
    .range(offset, offset + limit - 1);
  if (bounds) {
    // Stage 3 (2026-09-27 nav/discovery pass) — a real bounds query is
    // inherently geographic (a lat/lng-less event has no position to test
    // against a box), so this naturally still excludes those rows —
    // unlike the UNBOUNDED initial load below, which no longer requires
    // coordinates at all: an event missing them still belongs in the
    // list (just with no pin, see the marker-render loop and
    // `hasLocation` below), never silently dropped from discovery
    // entirely just because Map couldn't plot it.
    q = q.gte('lat', bounds.south).lte('lat', bounds.north).gte('lng', bounds.west).lte('lng', bounds.east);
  }
  const { data, error } = await q;
  if (error) { console.warn('Failed to load map events:', error); return []; }
  const rows = data || [];

  // Real-cover-photo fix (2026-10-19): `findEvent(row.id)` ALWAYS returns
  // something — it falls back to `EVENTS[0]` (`EVENTS.find(...) ||
  // EVENTS[0]`, src/data/events.js) when `row.id` isn't one of the static
  // demo catalogue's own hardcoded keys. Every organizer-created real event
  // has a freshly generated id (create_event_draft, migration 085) that can
  // never match a demo key, so `cosmetic` used to silently resolve to the
  // FIRST demo catalogue event for every real event — and `img:
  // cosmetic?.img` below then painted that one demo event's cover photo
  // onto every real event's map card/pin, regardless of which event was
  // actually selected. Root-cause fix: only treat `cosmetic` as real
  // cosmetic data when it's a genuine match, and resolve the map card's own
  // image the SAME way Home/EventDetail already do for a real row —
  // `resolveCoverUrl(row.cover_image, firstPhotoUrl)` (GocContext.jsx,
  // migration 087's `cover_image` falling back to the first `event_photos`
  // row by sort_order) — never the static catalogue for a row that isn't
  // actually in it.
  const realIds = rows.filter(row => !isCosmeticCatalogMatch(row.id)).map(row => row.id);
  const fallbackPhotoByEvent = await firstPhotoUrlByEvent(realIds);

  return rows.map(row => {
    const isCosmeticMatch = isCosmeticCatalogMatch(row.id);
    const cosmetic = isCosmeticMatch ? findEvent(row.id) : null;
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
      // Search-matcher fix (Issue 2) — previously never attached to this
      // screen's event objects at all (only `cat_key` was), so the search
      // document below had no category DISPLAY text to match against
      // ("Supper Club") independent of `keywords`.
      catLabel: row.cat_label || cosmetic?.catLabel,
      name: row.name || cosmetic?.name,
      area: row.area || cosmetic?.meta,
      city: row.city,
      // Location hierarchy (migration 112) — the raw fields the shared
      // area/location filter (curArea.match, src/lib/locationTree.js)
      // reads. `locationLabel` is the RAW district (never `cosmetic.meta`,
      // which is a "district ▪︎ km ▪︎ date" display string).
      locationLabel: row.area || cosmetic?.locationLabel || '',
      countryCode: row.country_code || cosmetic?.countryCode || '',
      stateProvince: row.state_province || '',
      neighborhood: row.neighborhood || '',
      organizerName: row.organizers?.name,
      description: row.description,
      intro: row.intro,
      // Keyword-search fix — real events' own `keywords` (migration 108,
      // populated at create/resubmit time, defaulting to the event's
      // category labels when the host leaves the field blank) plus the
      // demo catalogue's own derived `keywords` for a cosmetic-match row,
      // so a search term can match on more than just the literal name/area.
      keywords: row.keywords?.length ? row.keywords : (cosmetic?.keywords || []),
      lat: row.lat,
      lng: row.lng,
      // Stage 3 — a pin requires real coordinates; an event without them
      // still belongs in the list, just with an honest "no map location"
      // state instead of an invented point.
      hasLocation: row.lat != null && row.lng != null,
      seatsRemaining: row.seats_remaining,
      startsAt: row.starts_at,
      // Map price bug fix (2026-09-29) — root cause: this was ALWAYS
      // `cosmetic?.price` (the static demo catalogue's own hand-written
      // price string), never the real row's own `price_vnd` (already
      // fetched in the SELECT above, but never used before this fix) —
      // for any real, non-cosmetic-matching event this rendered the FIRST
      // demo catalogue event's own price ("900.000₫", `EVENTS[0]` =
      // "bepnho"), the exact bug reported: a real event created at 0 VND
      // showed "900.000đ" on Map while correctly showing "Miễn phí"/Free
      // on Event Detail (which reads the real row through a completely
      // different, already-correct path, GocContext.jsx's
      // `shapeRealEventAsCurEvent`). `price_vnd` itself is a real, valid
      // 0 for a genuinely free event — NOT "missing" — so this checks
      // `> 0`, never a bare truthiness/`||` check that would treat 0 the
      // same as null/undefined. Same convention Home.jsx's own
      // `discoveryShaped` mapping already uses for a real event's price.
      price: row.price_vnd > 0 ? formatVnd(row.price_vnd) : 'Miễn phí',
      img: isCosmeticMatch ? cosmetic?.img : resolveCoverUrl(row.cover_image, fallbackPhotoByEvent[row.id]),
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
  const { state: s, T, goEvent, backFromMapExplore, allowLocation, setMapExploreState, curArea, openArea } = useGoc();
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
  // Home quick event search (2026-09-27) — a by-name/area text filter,
  // ANDed with the existing category/open-now/nearby filters above (never
  // a separate search index — same `events` this screen already loads).
  const [searchQuery, setSearchQuery] = useState('');
  const searchInputRef = useRef(null);
  // Home quick event search — real-device follow-up (2026-09-28): focusing
  // via a plain `useEffect` (further down, on mount) fires the `.focus()`
  // call from a DEFERRED passive-effect flush, scheduled to run after the
  // browser has already painted — a separate task from the click that
  // opened this screen. On a real iOS Safari, `.focus()` only pops the
  // on-screen keyboard when it runs synchronously within the same
  // user-gesture call stack as the tap that triggered it; called later
  // (useEffect, setTimeout, a Promise microtask, ...) it silently moves
  // `document.activeElement` with NO keyboard — exactly the "first tap
  // does nothing, second (direct, on-the-input) tap brings up the
  // keyboard" symptom reported. A callback ref fires synchronously during
  // React's commit phase — still inside the same synchronous flush the
  // originating click triggered — so focusing there (the instant the
  // input DOM node itself exists, never a fixed delay/sleep) keeps the
  // real device's user-gesture trust intact. Guarded by a ref (not state)
  // so it fires exactly once per mount, never re-focusing on an unrelated
  // re-render.
  const searchAutofocusAppliedRef = useRef(false);
  const setSearchInputRef = useCallback((el) => {
    searchInputRef.current = el;
    if (el && restoredRef.current?.focusSearch && !searchAutofocusAppliedRef.current) {
      searchAutofocusAppliedRef.current = true;
      el.focus();
    }
  }, []);
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
  const [viewportHeight, setViewportHeight] = useState(() => screenHeight());
  const CARD_TOP_GAP = 12;

  useEffect(() => {
    const onResize = () => setViewportHeight(screenHeight());
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
    // Stage 3 — an event with no coordinates (see hasLocation) has
    // nowhere on the map to fly to; still selects it (the compact card
    // still shows its real info), just skips the camera move.
    if (!ev.hasLocation) return;
    const sheetPx = screenHeight() * (1 - mapStripFraction);
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
    // Home quick event search — the actual autofocus itself now happens in
    // `setSearchInputRef` above (a ref callback, fired synchronously the
    // instant the input mounts, not from this deferred effect) — see that
    // callback's own comment for why.
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

  // Moved above the marker-draw effect below (it references `visibleIdSet`
  // in its own dependency array, which is evaluated at render time — a
  // real "Cannot access before initialization" TDZ error surfaced this,
  // not a guess) — see each memo's own doc comment for what/why.
  // Search-matcher fix (Issue 2) — one normalized search document per
  // event, recomputed only when the fetched `events` list itself changes
  // (a new poll/bounds fetch), never on every keystroke. This is what
  // guarantees "Supp" surfaces every event the "Supper club" category
  // chip does: the document always includes the category label/key +
  // bilingual aliases (`CATEGORY_SEARCH_ALIASES`), independent of whether
  // that event's own `keywords` column happens to be populated.
  const eventSearchDocs = useMemo(() => {
    const docs = new Map();
    for (const e of events) docs.set(e.id, buildEventSearchDoc(e));
    return docs;
  }, [events]);

  const visibleEvents = useMemo(() => {
    let list = events;
    // Location hierarchy (2026-09-30) — the SAME selected location node
    // Home's feed uses (curArea.match, src/lib/locationTree.js). Map used
    // to ignore the area pick entirely. Pure data filter: never touches
    // locPermission/allowLocation, so picking any node (incl. the empty US
    // root) can't trigger a location-permission prompt.
    if (curArea.key !== 'all') list = list.filter(e => curArea.match(e));
    if (catFilter !== 'all') list = list.filter(e => e.catKey === catFilter);
    if (openNowOnly) list = list.filter(e => e.seatsRemaining > 0);
    // Home quick event search — matched against the canonical search
    // document (name/category/area/city/organizer/description/keywords),
    // ANDed with the filters above, never a replacement for them.
    // Normalized (case + Vietnamese-accent-insensitive, đ/d folded),
    // multi-token AND, substring/prefix — see src/lib/search.js.
    if (searchQuery.trim()) {
      list = list.filter(e => matchesSearchQuery(eventSearchDocs.get(e.id) || '', searchQuery));
    }
    if (sortByDistance && s.userCoords) {
      // Stage 3 — a no-location event has no real distance to sort by;
      // sorts after every plottable one rather than a NaN-driven,
      // effectively-random position.
      list = [...list].sort((a, b) => {
        if (a.hasLocation !== b.hasLocation) return a.hasLocation ? -1 : 1;
        if (!a.hasLocation) return 0;
        return haversineKm(s.userCoords, a) - haversineKm(s.userCoords, b);
      });
    }
    return list;
  }, [events, curArea, catFilter, openNowOnly, searchQuery, sortByDistance, s.userCoords, eventSearchDocs]);

  // B1 — the ONE filtered event-id set the list below and the map's own
  // markers (the draw effect right after this) both key off, so they can
  // never disagree about which events currently match. Never drops an
  // event from `events` itself (Stage 3's own no-coordinates rule is
  // untouched) — this is purely "does THIS id currently match the active
  // filters."
  const visibleIdSet = useMemo(() => new Set(visibleEvents.map(e => e.id)), [visibleEvents]);

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
        // Stage 3 — the unbounded list load no longer requires
        // coordinates (see fetchLiveEvents's own comment); a row without
        // them just never gets a marker, never an invented position.
        if (!ev.hasLocation) continue;
        const isSelected = ev.id === selectedId;

        // B1 — a geolocated event that doesn't match the CURRENT filters
        // gets a small, passive, non-clickable dot in its own category's
        // color instead of the normal clickable pin — visibly different
        // (no glyph, no shadow, no cursor, roughly a third the size), so
        // it never reads as "another selectable matching pin." Selection
        // itself (`selectedId`) is untouched by this — Bug 1/2's own
        // "selection stays independent of the list filter" behavior,
        // documented at length below, is unaffected either way.
        if (!visibleIdSet.has(ev.id)) {
          const dotEl = document.createElement('div');
          dotEl.setAttribute('data-testid', `map-dot-${ev.id}`);
          dotEl.style.cssText = `width:9px;height:9px;border-radius:50%;background:${CAT_DOT_COLOR[ev.catKey] || CAT_DOT_COLOR.all};border:1px solid ${paper};opacity:0.85;pointer-events:none;`;
          const dotMarker = new maplibregl.Marker({ element: dotEl }).setLngLat([ev.lng, ev.lat]).addTo(map);
          markersRef.current.push(dotMarker);
          continue;
        }
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
    // B3 — `visibleIdSet` (derived from `catFilter`/`openNowOnly`/
    // `sortByDistance`/`s.userCoords` via `visibleEvents`) is now a real
    // dependency: a filter change alone (no new `events` from the network)
    // must still redraw which ids are pins vs. dots. The existing
    // `cancelled` guard above already prevents an in-flight redraw from a
    // STALE effect run (e.g. a rapid filter change firing this twice in a
    // row) from painting markers after a newer run has already started —
    // satisfies "rapid filter changes cannot render stale icons."
  }, [events, selectedId, selectEvent, visibleIdSet]);

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

  // Stage 2 (2026-09-27 nav/discovery pass) — pull-to-refresh, LOCAL to
  // this list (not Shell's/App.jsx's generic one): MapExplore renders as
  // a `position: fixed` full-viewport overlay, so Shell's own scroll
  // container's scrollTop never moves here and is always 0 — treating
  // that as "at the top" would hijack the map's OWN vertical gestures
  // (the bottom sheet's drag-to-resize handle, this very list's native
  // scroll). This list (`listRef`) has a real, independent scrollTop, so
  // it gets its own tiny pointer-gesture pair instead, calling this
  // screen's OWN real refetch (searchHere — current bounds, no camera/
  // selection reset).
  const [mapPullDist, setMapPullDist] = useState(0);
  const [mapRefreshing, setMapRefreshing] = useState(false);
  const [mapRefreshError, setMapRefreshError] = useState('');
  const mapPullRef = useRef({ active: false, startY: 0, pointerId: null });
  const MAP_PULL_TRIGGER = 64;
  const MAP_PULL_MAX = 100;
  const onListPointerDown = (e) => {
    if (listRef.current && listRef.current.scrollTop > 0) return;
    mapPullRef.current = { active: true, startY: e.clientY, pointerId: e.pointerId };
  };
  const onListPointerMove = (e) => {
    const g = mapPullRef.current;
    if (!g.active || e.pointerId !== g.pointerId) return;
    const dy = e.clientY - g.startY;
    if (dy <= 0) { setMapPullDist(0); return; }
    setMapPullDist(Math.min(MAP_PULL_MAX, dy * 0.5));
  };
  const endListPull = async () => {
    const g = mapPullRef.current;
    if (!g.active) return;
    g.active = false;
    if (mapPullDist >= MAP_PULL_TRIGGER) {
      setMapRefreshing(true);
      setMapRefreshError('');
      setMapPullDist(MAP_PULL_TRIGGER * 0.72);
      try {
        await searchHere();
      } catch (err) {
        console.warn('Map pull-to-refresh failed:', err);
        setMapRefreshError(T('Không thể làm mới. Vui lòng thử lại.', 'Could not refresh. Please try again.'));
        setTimeout(() => setMapRefreshError(''), 3000);
      } finally {
        setMapRefreshing(false);
        setMapPullDist(0);
      }
    } else {
      setMapPullDist(0);
    }
  };
  const cancelListPull = () => { mapPullRef.current.active = false; if (!mapRefreshing) setMapPullDist(0); };

  const loadMore = useCallback(async () => {
    const next = page + 1;
    const bounds = lastQueriedBounds.current ? boundsToBox(lastQueriedBounds.current) : null;
    const more = await fetchLiveEvents({ bounds, offset: next * 60 });
    if (more.length) { setEvents(prev => [...prev, ...more]); setPage(next); }
  }, [page]);

  // B2 — snaps the sheet to MID exactly when the user actually CHANGES a
  // filter (category or "Còn chỗ"), never on mount, a map pan (`boundsChanged`
  // has nothing to do with these two), a list scroll, or the 5s freshness
  // poll (none of those touch `catFilter`/`openNowOnly`). `sortByDistance`
  // ("Gần bạn") is deliberately excluded — it re-orders the list, it never
  // excludes an event, so it isn't a "filter" in this ticket's sense.
  // Mirrors the existing `catFilterMountedRef` pattern immediately below
  // (same reasoning: `useEffect` has no built-in "skip the mount" the way
  // iOS's `.onChange` does).
  const filterChangeMountedRef = useRef(false);
  useEffect(() => {
    if (!filterChangeMountedRef.current) { filterChangeMountedRef.current = true; return; }
    setSheetSnap('mid');
  }, [catFilter, openNowOnly]);

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
    const sheetPx = screenHeight() * (1 - mapStripFraction);
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
    const deltaVh = ((e.clientY - dragState.current.startY) / screenHeight());
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

        {/* Home quick event search (2026-09-27) — a plain text filter,
            ANDed with the category/open-now/nearby controls below;
            reuses this screen's own existing list/filter/event-detail
            routing rather than a second search surface. Autofocused on
            arrival from Home's search button (see the mount effect
            above). */}
        <div style={{ padding: 'max(6px, env(safe-area-inset-top, 0px)) 16px 10px' }}>
          <div style={{ ...fieldGlass({}), display: 'flex', alignItems: 'center', gap: 8, padding: '9px 12px' }}>
            <svg width={15} height={15} viewBox="0 0 24 24" fill="none" stroke={ink} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.55, flex: 'none' }}>
              <circle cx="11" cy="11" r="7" />
              <path d="M21 21l-4.35-4.35" />
            </svg>
            <input
              ref={setSearchInputRef}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={T('Tìm sự kiện theo tên…', 'Search events by name…')}
              data-testid="map-search-input"
              style={{ flex: 1, minWidth: 0, border: 'none', outline: 'none', background: 'transparent', fontSize: 13.5, color: ink, fontFamily: "'Be Vietnam Pro', sans-serif" }}
            />
            {searchQuery && (
              <span onClick={() => setSearchQuery('')} data-testid="map-search-clear" style={{ cursor: 'pointer', color: ink, opacity: 0.5, fontSize: 16, lineHeight: 1, flex: 'none' }}>×</span>
            )}
          </div>
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

        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, padding: '0 16px 10px' }}>
          {/* Location hierarchy — opens the same shared area sheet Home
              uses (AreaSheet.jsx); shows the current short label. */}
          <div
            onClick={openArea}
            data-testid="map-chip-area"
            style={{ ...fieldGlass({}), padding: '5px 10px', fontSize: 11, cursor: 'pointer', color: ink, fontWeight: curArea.key !== 'all' ? 700 : 400, border: curArea.key !== 'all' ? `1px solid ${ink}` : 'none' }}
          >
            {curArea.key === 'all' ? T('Tất cả khu vực', 'All areas') : curArea.label} ▾
          </div>
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
          style={{ flex: 1, overflowY: 'auto', padding: '0 16px 24px', position: 'relative', touchAction: 'pan-y' }}
          onScroll={(e) => {
            const el = e.currentTarget;
            if (el.scrollHeight - el.scrollTop - el.clientHeight < 120) loadMore();
          }}
          onPointerDown={onListPointerDown}
          onPointerMove={onListPointerMove}
          onPointerUp={endListPull}
          onPointerCancel={cancelListPull}
        >
          {(mapPullDist > 0 || mapRefreshing || mapRefreshError) && (
            <div
              data-testid="map-pull-to-refresh-indicator"
              style={{ position: 'absolute', top: 4, left: 0, right: 0, display: 'flex', justifyContent: 'center', transform: `translateY(${Math.max(0, mapPullDist - 24)}px)`, pointerEvents: 'none' }}
            >
              {mapRefreshError ? (
                <span style={{ fontSize: 11, fontWeight: 600, color: ink, background: paper, borderRadius: 999, padding: '6px 12px', boxShadow: '0 4px 14px rgba(27,25,22,0.16)' }}>{mapRefreshError}</span>
              ) : (
                <RootRefreshIndicator
                  screen="mapExplore"
                  progress={mapPullDist / MAP_PULL_TRIGGER}
                  refreshing={mapRefreshing}
                  label={T('Đang làm mới', 'Refreshing')}
                />
              )}
            </div>
          )}
          {loading && visibleEvents.length === 0 && <div style={{ padding: 20, color: ink, opacity: 0.6, fontSize: 13 }}>{T('Đang tải…', 'Loading…')}</div>}
          {!loading && visibleEvents.length === 0 && (
            <div style={{ padding: 20, color: ink, opacity: 0.6, fontSize: 13 }} data-testid="map-search-no-results">
              {searchQuery.trim()
                ? T(`Không tìm thấy sự kiện nào khớp với "${searchQuery.trim()}".`, `No events match "${searchQuery.trim()}".`)
                : T('Không có sự kiện nào ở khu vực này.', 'No events in this area.')}
            </div>
          )}
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
                {/* Stage 3 — an honest "no map location" state for an
                    event with no (or not-yet-confirmed) coordinates,
                    never a silently-omitted row or an invented pin. */}
                {!ev.hasLocation && (
                  <div data-testid={`map-list-item-no-location-${ev.id}`} style={{ fontSize: 10.5, color: ink, opacity: 0.55, marginTop: 2 }}>
                    {T('Chưa có vị trí trên bản đồ', 'No map location yet')}
                  </div>
                )}
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
