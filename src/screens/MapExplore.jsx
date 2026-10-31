import { screenHeight } from '../lib/viewport.js';
import { loadMapStyle } from '../lib/mapStyle.js';
import { loadMapKit } from '../lib/mapkit.js';
import { createMapKitMap } from '../lib/mapkitAdapter.js';
import { SHEET_SNAPS, CARD_GAP, ATTRIB_RESERVE, computeMapLayout, snapForSelection } from '../lib/mapLayout.js';
import { Fragment, useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { useBanBe, resolveCoverUrl, firstPhotoUrlByEvent } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { withR2Columns, marketColumnList, detailsColumnList } from '../lib/mediaUrls.js';
import {
  reasonCommits, referenceRect, boundsForRect, mapResults, selectionAfter, boundsOfPoints, pointsNear, nearestPoint,
  fitCamera, distanceKm as geoKm,
} from '../lib/mapDiscovery.js';
import { findEvent, isCosmeticCatalogMatch, haversineKm, mapsUrl } from '../data/events.js';
import { distanceLabel } from '../lib/eventDetailPresentation.js';
import { whenLabel } from '../lib/quickWins.js';
import { fillBadge, categorySheetKeys, applyDiscoveryFilters, normalizeFilters, activeFilterCount, DEFAULT_FILTERS } from '../lib/homeDiscovery.js';
import HomeFilterSheet from './sheets/HomeFilterSheet.jsx';
import { secondCategory, categoryDefs } from '../lib/eventTypes.js';
import { CategoryGlyph, CATEGORY_DEFS, CategorySheet } from '../components/home/HomeDiscoveryParts.jsx';
import { liveEventOverrides } from '../lib/countdown.js';
import { formatMoney, rowCurrency, rowTimeZone } from '../lib/eventMarket.js';
import { densityHotspot } from '../lib/densityHotspot.js';
import { buildEventSearchDoc, matchesSearchQuery } from '../lib/search.js';
import { prefsIsEmpty } from '../lib/eventPrefs.js';
import { mapForYouSet, applyForYouFilter } from '../lib/forYou.js';
import { useForYouAlert } from '../lib/useForYouAlert.js';
import ForYouChip from './ForYouChip.jsx';
import { paper, ink, ink2, rule, alert, clay, clayBg, surface2, photoPill, inkButton, RADIUS } from '../theme.js';
import RootRefreshIndicator from './RootRefreshIndicator.jsx';
import 'maplibre-gl/dist/maplibre-gl.css';

// Category glyph per FILTER_DEFS key — no icon set exists anywhere else in
// this app (see .claude/notes/11-realtime-map.md), so these are plain
// minimal glyphs rather than an invented illustrated icon language.
const CAT_GLYPH = { all: '▪︎', supper: '🍽️', fashion: '👗', gallery: '🖼️', music: '🎵', popup: '🛍️' };

// Same disabled-button opacity this app already uses everywhere else
// (apps/ios/BanbeApp/Views/Components.swift:151, Login.jsx's loginBtnStyle)
// — reused verbatim for the compass button while location is denied.
const DISABLED_OPACITY = 0.16;

// Map redesign phase 2: the whole public set every 60 s (plus on return to the tab and on pull-to-refresh). It was
// 5 s, which re-downloaded every row and description a dozen times a minute (Supabase egress, note 40).
const POLL_MS = 60000;


// Map redesign phase 2: the Map loads the WHOLE public live set (up to MAP_EVENT_CAP) with an exact count, then
// filters by the committed map area locally — panning never needs the network. `complete` is false only when the
// set is larger than the cap; the screen then says so honestly instead of presenting a truncated page as complete.
export const MAP_EVENT_CAP = 500;

async function fetchLiveEvents({ limit = MAP_EVENT_CAP } = {}) {
  const buildQuery = (withR2) => {
  const q = supabase
    .from('events')
    // Keyword-search fix (migration 108) — re-enabled 2026-09-29, see
    // REAL_EVENT_ROW_COLUMNS's own doc comment (BanBeContext.jsx) for why it
    // was briefly reverted and how its return was verified.
    // Search-matcher fix (Issue 2) — `cat_label`, `description`, `intro`
    // and the event's own organizer name are now selected too, so the
    // search document built below (`buildEventSearchDoc`) can include
    // category/organizer/description text regardless of whether
    // `keywords` happens to be populated for a given row.
    .select('id, key, name, cat_key, cat_label, area, city, lat, lng, starts_at, event_date, event_time, price_vnd, seats_remaining, status, cover_image, ' + detailsColumnList().map(c => c + ', ').join('') + (withR2 ? 'cover_r2_ref, ' : '') + 'keywords, description, intro, country_code, state_province, neighborhood, ' + marketColumnList().map(c => c + ', ').join('') + 'organizers(name)', { count: 'exact' })
    .eq('status', 'live')
    // Strict invite-only events (2026-10-25): unlike loadWeekendEvents/
    // loadDiscoveryEvents (BanBeContext.jsx), this query never filtered
    // visibility at all — a real invite-only event would have shown up
    // on the Map for anyone. RLS (migration 113) is the actual backstop
    // now, but this list should stay honest client-side too: an invitee
    // sees their own invite-only event on the Map through EventDetail/
    // deep link, never through discovery search.
    .eq('visibility', 'public')
    .order('starts_at', { ascending: true })
    .range(0, limit - 1);
  return q;
  };
  const { data, error, count } = await withR2Columns(buildQuery);
  // A failure throws: the caller keeps the last good results and shows a retry, never an empty "no events".
  if (error) throw new Error(error.message || 'Failed to load map events');
  const rows = data || [];
  const total = typeof count === 'number' ? count : rows.length;

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
  // `resolveCoverUrl(row.cover_image, firstPhotoUrl)` (BanBeContext.jsx,
  // migration 087's `cover_image` falling back to the first `event_photos`
  // row by sort_order) — never the static catalogue for a row that isn't
  // actually in it.
  const realIds = rows.filter(row => !isCosmeticCatalogMatch(row.id)).map(row => row.id);
  // Real seat fill (migration 186, the same RPC Home uses): `seats_remaining` is never decremented after insert
  // (note 50), so it can't say "sold out" or "few left". No fill row = no seat status, never a guess.
  const [fallbackPhotoByEvent, fillById] = await Promise.all([firstPhotoUrlByEvent(realIds), loadFill(rows.map(r => r.id))]);

  const shaped = rows.map(row => {
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
      // Primary + second category (details.cat2, note 69), the same pair Home filters on.
      catKeys: [row.cat_key || cosmetic?.catKey, secondCategory(row.details, row.cat_key)].filter(Boolean),
      details: row.details || {},
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
      // Raw fields the shared For You candidate builder (src/lib/forYou.js) reads —
      // the same ones Home's events carry, so Home and Map can never score differently.
      // Minor units of `currency` (migration 195): dong, or cents for USD. `tz` is the venue's zone.
      priceVnd: row.price_vnd || 0,
      currency: rowCurrency(row),
      tz: rowTimeZone(row),
      status: row.status,
      // Map price bug fix (2026-09-29) — root cause: this was ALWAYS
      // `cosmetic?.price` (the static demo catalogue's own hand-written
      // price string), never the real row's own `price_vnd` (already
      // fetched in the SELECT above, but never used before this fix) —
      // for any real, non-cosmetic-matching event this rendered the FIRST
      // demo catalogue event's own price ("900.000₫", `EVENTS[0]` =
      // "bepnho"), the exact bug reported: a real event created at 0 VND
      // showed "900.000đ" on Map while correctly showing "Miễn phí"/Free
      // on Event Detail (which reads the real row through a completely
      // different, already-correct path, BanBeContext.jsx's
      // `shapeRealEventAsCurEvent`). `price_vnd` itself is a real, valid
      // 0 for a genuinely free event — NOT "missing" — so this checks
      // `> 0`, never a bare truthiness/`||` check that would treat 0 the
      // same as null/undefined. Same convention Home.jsx's own
      // `discoveryShaped` mapping already uses for a real event's price.
      price: row.price_vnd > 0 ? formatMoney(row.price_vnd, rowCurrency(row)) : 'Miễn phí',
      img: isCosmeticMatch ? cosmetic?.img : resolveCoverUrl(row.cover_image, fallbackPhotoByEvent[row.id], row.cover_r2_ref),
      when: dateOverrides?.when || cosmetic?.when,
      booked: fillById[row.id]?.booked ?? null,
      capacity: fillById[row.id]?.capacity ?? null,
      fillKnown: !!fillById[row.id],
      urgent: !!fillById[row.id] && fillBadge(fillById[row.id].booked, fillById[row.id].capacity).almostFull,
      isNew: (dateOverrides?.until ?? cosmetic?.until) != null && (dateOverrides?.until ?? cosmetic?.until) <= 1,
      // Live seats_remaining is this screen's own established "real-time-ish"
      // signal (already used for `urgent` above) — reused for sold-out too,
      // falling back to the static catalogue's flag only when a row has no
      // seats_remaining of its own to check.
      soldOut: fillById[row.id] ? fillBadge(fillById[row.id].booked, fillById[row.id].capacity).soldOut : !!cosmetic?.soldOut,
    };
  });
  return { rows: shaped, total, complete: shaped.length >= total };
}

const reduceMotion = () => typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

// A Map event in Home's discovery-item shape (src/lib/homeDiscovery.js), so both run the same filter predicate.
function discoveryItem(ev) {
  const startsAt = ev.startsAt ? Date.parse(ev.startsAt) : null;
  return {
    key: ev.id, startsAt: Number.isFinite(startsAt) ? startsAt : null, priceVnd: ev.priceVnd ?? null, currency: ev.currency,
    catKeys: ev.catKeys?.length ? ev.catKeys : [ev.catKey].filter(Boolean), booked: ev.booked, capacity: ev.capacity,
    soldOut: !!ev.soldOut, details: ev.details || {}, tz: ev.tz, ev,
  };
}

// Booked/capacity per event from get_public_event_fill (migration 186). Best-effort: an error gives {}.
async function loadFill(ids) {
  if (!ids.length) return {};
  const { data, error } = await supabase.rpc('get_public_event_fill', { p_event_ids: ids.slice(0, 300) });
  if (error || !Array.isArray(data)) return {};
  return Object.fromEntries(data.map(r => [r.event_id, { booked: r.booked, capacity: r.capacity }]));
}

// Seat facts for a row/card: { left, soldOut, almostFull } or null when banbe has no fill for the event.
function seatFacts(ev) {
  if (!ev.fillKnown) return ev.soldOut ? { left: 0, soldOut: true, almostFull: false } : null;
  return fillBadge(ev.booked, ev.capacity);
}

export default function MapExplore() {
  const { state: s, set, T, resolvedTheme, goEvent, backFromMapExplore, allowLocation, setMapExploreState, curArea, openArea, openEventPreferences } = useBanBe();
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
  const prevMarkerKeysRef = useRef(new Set());
  // Marker class of whichever map is live (MapKit adapter's, or MapLibre's once it is loaded).
  const markerCtorRef = useRef(null);
  // The map is created asynchronously AFTER the first load has already set `events`, so the pin effect's first run
  // found no map and drew nothing until the 5 s poll replaced `events` (device report: no pins on open). This flips
  // once the map exists and re-runs the pin effect.
  const [mapReady, setMapReady] = useState(false);
  const listRef = useRef(null);
  const listScrollRestoredRef = useRef(false);
  // A return from Event Detail starts from the cached rows, so the list never flashes "Loading".
  const [events, setEvents] = useState(() => restored?.events ?? []);
  const [loading, setLoading] = useState(() => !restored?.events);
  // Completeness of the loaded set (false only past MAP_EVENT_CAP) and the last load error (results are kept).
  const [dataMeta, setDataMeta] = useState(() => ({ total: restored?.events?.length ?? 0, complete: true }));
  const [loadError, setLoadError] = useState(false);
  // The committed search area: changes only when the camera settles after geographic navigation (see
  // src/lib/mapDiscovery.js). Never follows the sheet, a selection reveal or a refresh.
  const [committedBounds, setCommittedBounds] = useState(() => restored?.committedBounds ?? null);
  const cameraReasonRef = useRef(null); // reason of the camera move in progress (null + movestart = user)
  // 'area' while the map is framed on the selected area (destination), else 'map' ("Vùng bản đồ / Map area").
  const [areaContext, setAreaContext] = useState(() => restored?.areaContext ?? 'map');
  const framedByAreaRef = useRef(false);
  const settleTimerRef = useRef(null);
  // Map redesign phase 3: ONE filter object in Home's shape (src/lib/homeDiscovery.js: date, cats, seatsLeft, price,
  // free, almostFull, typeFilters), judged by the same applyDiscoveryFilters Home uses — each event in its own venue
  // time zone. Seeded from a return snapshot, else from Home's hand-off (goMapExplore(ctx)), else nothing.
  // Moving the map never changes it.
  const entryRef = useRef(restored ? null : s.mapExploreEntry || null);
  const entry = entryRef.current;
  const [filters, setFilters] = useState(() => normalizeFilters(
    restored?.filters
    ?? (restored ? { cats: restored.catFilter && restored.catFilter !== 'all' ? [restored.catFilter] : [], seatsLeft: !!restored.openNowOnly } : null)
    ?? entry?.filters
    ?? DEFAULT_FILTERS,
  ));
  // The category row is single-choice (Home's sheet hides categories in Simple Shell; the Map sheet does too).
  const catFilter = filters.cats[0] ?? 'all';
  const setCatFilter = useCallback((k) => setFilters(f => normalizeFilters({ ...f, cats: k === 'all' ? [] : [k], typeFilters: [] })), []);
  const openNowOnly = filters.seatsLeft;
  const setOpenNowOnly = useCallback((v) => setFilters(f => normalizeFilters({ ...f, seatsLeft: typeof v === 'function' ? v(f.seatsLeft) : v })), []);
  const toggleDate = useCallback((opt) => setFilters(f => normalizeFilters({ ...f, date: f.date === opt ? 'any' : opt })), []);
  const [filterSheetOpen, setFilterSheetOpen] = useState(false);
  // Home quick event search (2026-09-27) — a by-name/area text filter,
  // ANDed with the existing category/open-now/nearby filters above (never
  // a separate search index — same `events` this screen already loads).
  const [searchQuery, setSearchQuery] = useState(() => restored?.searchQuery ?? entry?.query ?? '');
  // For You (34/35 notes): local to Map (never touches Home's own `filterForYou`),
  // matching comes from the shared forYouRankEvents so both surfaces score alike.
  const [forYouOn, setForYouOn] = useState(() => restored?.forYou ?? !!entry?.forYou);
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
  // (BanBeContext.jsx's openEventOnMap) never sets `sheetSnap` (only
  // camera/selectedId), so a genuine MapExplore-to-MapExplore restore
  // (which DOES carry a real `sheetSnap`) is untouched; only the "arrives
  // with a card already selected, no restored sheet position of its own"
  // case defaults to 'mid' instead of 'tall', same reasoning as
  // `selectEvent`'s own snap-down below.
  // Layout A (map first, card peek): every fresh open starts at mid, so the map keeps more than half the screen.
  const [sheetSnap, setSheetSnap] = useState(() => restored?.sheetSnap ?? 'mid');
  const [categorySheetOpen, setCategorySheetOpen] = useState(false);
  // Owner, 2026-10-24 ("no events on the map until I pull down"): each load takes a number and only the newest one
  // may write the list, so a slow, stale answer can never overwrite a newer, good one. iOS twin: mapEventsGeneration.
  // A failed load keeps the last good rows and raises `loadError` (Retry), never an empty list.
  const loadSeq = useRef(0);
  const loadLatest = async () => {
    const n = ++loadSeq.current;
    try {
      const res = await fetchLiveEvents();
      if (n !== loadSeq.current) return null;
      setDataMeta({ total: res.total, complete: res.complete });
      setLoadError(false);
      return res.rows;
    } catch (err) {
      if (n === loadSeq.current) { console.warn('Map events load failed:', err); setLoadError(true); }
      return null;
    }
  };
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
  const cardRef = useRef(null);
  const rootRef = useRef(null);
  const [topControlsBottom, setTopControlsBottom] = useState(56); // px from the TOP of this screen's own box
  const [cardHeight, setCardHeight] = useState(150);
  const [containerH, setContainerH] = useState(() => screenHeight());
  const [dockClear, setDockClear] = useState(110); // px the floating dock occupies at the bottom

  // This screen's OWN box (a fixed layer, which on desktop is the phone frame), not the
  // window: sheet, card and camera padding all derive from it, so Safari toolbar changes,
  // rotation and the desktop frame all stay consistent. Also dock clearance for the list.
  useEffect(() => {
    const root = rootRef.current;
    if (!root) return undefined;
    const measure = () => {
      const r = root.getBoundingClientRect();
      if (r.height > 0) setContainerH(r.height);
      // The dock itself (Simple Shell has no Map tab to measure from).
      const tab = document.querySelector('[data-testid="bottom-tab-bar"]') || document.querySelector('[data-testid="tab-map"]');
      if (tab) {
        const tr = tab.getBoundingClientRect();
        if (tr.height > 0) setDockClear(Math.max(0, Math.round(r.bottom - tr.top)));
      }
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(root);
    window.addEventListener('resize', measure);
    window.addEventListener('orientationchange', measure);
    return () => { ro.disconnect(); window.removeEventListener('resize', measure); window.removeEventListener('orientationchange', measure); };
  }, []);

  // Re-measures whenever the box resizes. ("Tìm ở đây" is gone: results follow the map on their own.)
  useEffect(() => {
    const els = [backRef.current, compassRef.current].filter(Boolean);
    if (!els.length || !rootRef.current) return undefined;
    const measure = () => {
      const top = rootRef.current.getBoundingClientRect().top;
      setTopControlsBottom(Math.max(...els.map(el => el.getBoundingClientRect().bottom)) - top);
    };
    measure();
    const ro = new ResizeObserver(measure);
    els.forEach(el => ro.observe(el));
    return () => ro.disconnect();
  }, [containerH]);

  useEffect(() => {
    if (!cardRef.current) return undefined;
    const measure = () => setCardHeight(cardRef.current.getBoundingClientRect().height);
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(cardRef.current);
    return () => ro.disconnect();
  }, [selectedId]);

  // ---- layout geometry (all px, relative to this screen's box) ----
  // Visible map = [topControlsBottom + gap, sheetTop - attribution strip]. The selected-event card
  // sits at the bottom of that region (directly above the sheet), the camera pads to match, and
  // when the region is too short for the card (sheet dragged up) the card hides instead of
  // overlapping controls or the sheet.
  const lay = computeMapLayout({ containerH, topControlsBottom, cardHeight, stripFraction: mapStripFraction });
  const { sheetTopPx, cardFits, cardBottomPx } = lay;
  const dims = { containerH, topControlsBottom, cardHeight };
  const layRef = useRef(lay);
  layRef.current = lay;
  const cameraPadding = () => layRef.current.cameraPadding;

  // Basemap follows the app theme (derived Liberty light/dark, src/lib/mapStyle.js); camera,
  // markers and selection survive a style swap.
  const themeRef = useRef(resolvedTheme);
  useEffect(() => {
    const mode = resolvedTheme;
    if (themeRef.current === mode) return undefined;
    themeRef.current = mode;
    let cancelled = false;
    if (mapRef.current?.__isMapKit) { mapRef.current.setColorScheme(mode); return undefined; }
    loadMapStyle(mode).then(style => { if (!cancelled && mapRef.current) mapRef.current.setStyle(style); });
    return () => { cancelled = true; };
  }, [resolvedTheme]);

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

  // ---- camera moves carry a reason (src/lib/mapDiscovery.js) ----
  // Every programmatic move goes through here; a gesture start without one is the user. Only geographic
  // navigation commits a new search area after the camera settles; 'reveal'/'restore' never do.
  const moveCamera = useCallback((reason, apply) => {
    const map = mapRef.current;
    if (!map) return;
    cameraReasonRef.current = { reason, t: Date.now() };
    apply(map);
  }, []);
  // Geometry the commit needs, read at settle time (the map's own box, the top controls).
  const geomRef = useRef({ topControlsBottom, containerH });
  geomRef.current = { topControlsBottom, containerH };
  const commitArea = useCallback((reason = 'initial') => {
    const map = mapRef.current;
    const el = mapDivRef.current;
    if (!map || !el) return;
    const size = { width: el.clientWidth || 390, height: el.clientHeight || geomRef.current.containerH };
    // The reference rect: below the top controls, above the PEEK sheet — the same at every detent, so moving the
    // sheet never changes the area, its results or the count.
    const rect = referenceRect({
      ...size,
      topInset: geomRef.current.topControlsBottom + CARD_GAP,
      bottomInset: size.height - (SHEET_SNAPS.peek * size.height - ATTRIB_RESERVE),
    });
    const next = boundsForRect(boundsToBox(map.getBounds()), size, rect);
    setCommittedBounds(next);
    // The chip names the picked area only while the map is still framed on it; any other navigation makes the
    // context "Map area" (Home's selected area itself is never changed by panning).
    setAreaContext(reason === 'destination' || (reason === 'initial' && framedByAreaRef.current) ? 'area' : 'map');
    // Test-only hook (like __mapExploreMapForTests): how many times an area was committed, and the last one.
    if (typeof window !== 'undefined') {
      window.__mapExploreCommits = (window.__mapExploreCommits || 0) + 1;
      window.__mapExploreArea = next;
    }
  }, []);
  const onCameraSettled = useCallback(() => {
    const pending = cameraReasonRef.current;
    const fresh = pending && Date.now() - pending.t < (reasonCommits(pending.reason) ? 4000 : 1500);
    const reason = fresh ? pending.reason : 'user';
    clearTimeout(settleTimerRef.current);
    // A layout-only reason ('reveal'/'restore') stays in force for its short window: a reveal flight interrupted
    // by the sheet-padding ease ends in TWO moveends, and the second must not read as the user's. A real gesture
    // replaces it at movestart. A navigation reason is used once; extra moveends just re-arm the single commit.
    if (!fresh || reasonCommits(reason)) cameraReasonRef.current = null;
    if (!reasonCommits(reason)) return;
    // Coalesce: wheel zoom and flings end in several quick `moveend`s; commit once when they stop.
    settleTimerRef.current = setTimeout(() => commitArea(reason), 250);
  }, [commitArea]);
  useEffect(() => () => clearTimeout(settleTimerRef.current), []);

  const recenterOnUser = useCallback(() => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLocPermission('granted');
        allowLocation();
        // Explicit geographic navigation: one new search area once it settles.
        moveCamera('recenter', map => map.flyTo({ center: [pos.coords.longitude, pos.coords.latitude], zoom: 14 }));
      },
      () => setLocPermission('denied'),
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }, [allowLocation, moveCamera]);

  const flightTargetRef = useRef(null); // {center, zoom} of an in-progress selection flight
  const flightTimerRef = useRef(null);
  useEffect(() => () => clearTimeout(flightTimerRef.current), []);
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
    // mirrors the exact same math the sheet's own `top: sheetTopPx`
    // style uses, so this stays correct across List lớn/List nhỏ/mid-drag.
    // Stage 3 — an event with no coordinates (see hasLocation) has
    // nowhere on the map to fly to; still selects it (the compact card
    // still shows its real info), just skips the camera move.
    if (!ev.hasLocation) return;
    // A REVEAL: bring the pin into the free area above the card at the CURRENT zoom. It never zooms in and never
    // redefines the search area (the list and count stay what the user was browsing).
    const target = { center: [ev.lng, ev.lat], zoom: map.getZoom() };
    flightTargetRef.current = target;
    clearTimeout(flightTimerRef.current);
    flightTimerRef.current = setTimeout(() => { flightTargetRef.current = null; }, 1000); // flight 550ms + one retarget ease
    moveCamera('reveal', m => m.flyTo({ ...target, padding: cameraPadding(), duration: reduceMotion() ? 0 : 550 }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const clearSelection = useCallback(() => setSelectedId(null), []);

  // Once a restored snapshot has been read into `restoredRef` (above), clear
  // context's own copy — it's served its purpose for this mount, and
  // leaving it sitting in context risks a second, unrelated mount
  // mistakenly reusing the exact same snapshot later.
  useEffect(() => {
    if (restored) setMapExploreState(null);
    // The Home hand-off is read once (entryRef); a later open from the dock starts clean.
    if (s.mapExploreEntry) set({ mapExploreEntry: null });
    // Home quick event search — the actual autofocus itself now happens in
    // `setSearchInputRef` above (a ref callback, fired synchronously the
    // instant the input mounts, not from this deferred effect) — see that
    // callback's own comment for why.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ---- first open: load, frame the relevant results above the mid sheet, then draw the map ----
  useEffect(() => {
    let active = true;
    (async () => {
      const loaded = await loadLatest();
      if (!active) return;
      const initial = loaded || restored?.events || [];
      if (loaded) setEvents(loaded);
      setLoading(false);

      // Apple MapKit JS when enabled + authorised (src/lib/mapkit.js); otherwise the OpenStreetMap map below.
      const mapkit = await loadMapKit();
      if (!active || !mapDivRef.current || mapRef.current) return;

      // A restored camera (return from Event Detail / Edit preferences / "Open in Map") is kept exactly. A fresh
      // open frames what is relevant into the free area above the MID sheet, in this order: the selected area's
      // events → events within 50 km of a located viewer → the densest city of events. Never the viewer's GPS on
      // its own, never the whole inventory. No events at all: Ho Chi Minh City, and the empty state says so.
      let center = restored?.cameraCenter || null;
      let zoom = restored?.cameraZoom ?? null;
      if (!center) {
        const el = mapDivRef.current;
        const size = { width: el.clientWidth || 390, height: el.clientHeight || containerH };
        const pts = initial.filter(e => e.hasLocation);
        const areaPts = curArea.key !== 'all' ? pts.filter(e => curArea.match(e)) : [];
        const me = s.located === true && s.userCoords ? s.userCoords : null;
        const nearMe = me ? pointsNear(pts, me, 50) : [];
        framedByAreaRef.current = areaPts.length > 0;
        const frame = areaPts.length ? areaPts
          : nearMe.length ? nearMe
          : pointsNear(pts, densityHotspot(pts.map(e => ({ lat: e.lat, lng: e.lng }))), 25);
        const box = boundsOfPoints(frame);
        if (box) {
          const cam = fitCamera(box, size, {
            top: topControlsBottom + CARD_GAP + 16,
            bottom: size.height * (1 - SHEET_SNAPS.mid) + ATTRIB_RESERVE + 16,
            left: 40, right: 40,
          }, { tileSize: mapkit ? 256 : 512, maxZoom: 14 });
          center = cam.center;
          zoom = cam.zoom;
        } else {
          center = { lat: 10.7769, lng: 106.7009 };
          zoom = 12;
        }
      }
      if (!active || !mapDivRef.current || mapRef.current) return;
      let map;
      if (mapkit) {
        map = createMapKitMap(mapkit, { container: mapDivRef.current, center, zoom, theme: themeRef.current });
        markerCtorRef.current = map.Marker;
      } else {
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

        map = new maplibregl.Map({
          container: mapDivRef.current,
          style: await loadMapStyle(themeRef.current),
          attributionControl: false,
          center: [center.lng, center.lat],
          zoom,
        });
        map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
        // Required OpenFreeMap/OSM credit stays fully visible (not collapsed behind the "i" button);
        // the CSS below lifts it above the bottom sheet.
        map.addControl(new maplibregl.AttributionControl({ compact: false, customAttribution: undefined }), 'bottom-right');
        // The map container is `inset: 0` of this screen's box; keep the canvas in sync with any
        // container change (sheet/viewport/Safari toolbar), not just window resizes.
        if (typeof ResizeObserver !== 'undefined' && mapDivRef.current) {
          const mro = new ResizeObserver(() => map.resize());
          mro.observe(mapDivRef.current);
          map.__bbResizeObserver = mro;
        }
        markerCtorRef.current = maplibregl.Marker;
      }
      // Move → settle → commit (src/lib/mapDiscovery.js). A gesture (MapLibre passes `originalEvent`) is always
      // the user's, even if a programmatic move was still pending.
      map.on('movestart', (e) => {
        if (e?.originalEvent) cameraReasonRef.current = { reason: 'user', t: Date.now() };
        clearTimeout(settleTimerRef.current);
      });
      map.on('moveend', onCameraSettled);
      // A tap on the map background (not a pin — those are separate marker
      // DOM elements, never reaches this) clears the selected-event card.
      // This is a genuine click, not `moveend`, so it can never be confused
      // with "Search here" (that's tied only to the explicit button).
      map.on('click', () => setSelectedId(null));
      mapRef.current = map;
      setMapReady(true);
      // First open commits its area once, straight away (the camera is already where it was framed). A restore
      // keeps its saved area, so the list it returns to is exactly the one the user left. "Open in Map" carries a
      // camera but no area: it commits the area around that camera.
      if (!restored?.committedBounds) commitArea();
      // After a restore the camera may legitimately differ from the area (a selection reveal panned it): the first
      // settle (e.g. the canvas' own initial resize) is a 'restore' and must not replace the saved area.
      else cameraReasonRef.current = { reason: 'restore', t: Date.now() };
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
      mapRef.current?.__bbResizeObserver?.disconnect();
      mapRef.current?.remove();
      mapRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ---- freshness: the whole public set again, never a box; camera, area, filters, selection and scroll untouched ----
  const [refreshing, setRefreshing] = useState(false);
  const refresh = useCallback(async () => {
    setRefreshing(true);
    const fresh = await loadLatest();
    if (fresh) setEvents(fresh);
    setRefreshing(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => {
    const interval = setInterval(refresh, POLL_MS);
    const onVisible = () => { if (document.visibilityState === 'visible') refresh(); };
    document.addEventListener('visibilitychange', onVisible);
    return () => { clearInterval(interval); document.removeEventListener('visibilitychange', onVisible); };
  }, [refresh]);

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

  // For You = the shared ranker over the loaded events (Home's own semantics and signed-out rule); the Map then keeps
  // only the matches inside the committed area like every other filter. The area picker is a destination for the map
  // now (phase 3), not an extra filter, so it no longer narrows the For You set. Toggling never refetches/recenters.
  const hasPrefs = !!s.eventPrefs && !prefsIsEmpty(s.eventPrefs);
  // A stale `forYouOn` (signed out / account switch / prefs cleared) must never filter anything.
  const forYouActive = forYouOn && hasPrefs;
  const { ranked: forYouRanked, order: forYouOrder } = useMemo(
    () => mapForYouSet(events, null, s.eventPrefs, hasPrefs, Date.now()),
  // eslint-disable-next-line react-hooks/exhaustive-deps
  [events, s.eventPrefs, s.eventPrefsVersion, hasPrefs]);
  // Read-only view of Home's persisted "new matches" state (Home owns observation).
  const forYouAlert = useForYouAlert({ userId: s.user?.id, passive: true });
  const prefsLoading = !!s.user && !s.eventPrefsLoaded;

  // The minute the time filters are judged at (re-evaluated each minute, like Home), never per frame.
  const nowMinute = Math.floor(Date.now() / 60000);
  // Search + For You (the two filters that are not in Home's filter object), before geography and the category.
  const searchedEvents = useMemo(() => {
    // For You — the SAME match set drives pins and this list.
    let list = applyForYouFilter(events, forYouActive, forYouOrder);
    // Matched against the canonical search document (name/category/area/city/organizer/description/keywords),
    // normalized and multi-token AND — see src/lib/search.js.
    if (searchQuery.trim()) {
      list = list.filter(e => matchesSearchQuery(eventSearchDocs.get(e.id) || '', searchQuery));
    }
    return list;
  }, [events, forYouActive, forYouOrder, searchQuery, eventSearchDocs]);
  // Every filter except the category (so the category chips can say what tapping each one would show): Home's own
  // predicate — date (venue zone), seats (real fill), price per ticket in one currency, type chips.
  const baseEvents = useMemo(
    () => applyDiscoveryFilters(searchedEvents.map(discoveryItem), { ...filters, cats: [] }, nowMinute * 60000).map(it => it.ev),
    [searchedEvents, filters, nowMinute],
  );

  // Primary or second category, like Home's catKeys.
  const inCategory = (e, key) => key === 'all' || (e.catKeys?.length ? e.catKeys : [e.catKey]).includes(key);
  // Inside the committed map area, every filter except the category (src/lib/mapDiscovery.js mapResults).
  const areaBase = useMemo(() => mapResults(baseEvents, committedBounds), [baseEvents, committedBounds]);
  // THE results: pins, list and count all come from this one list.
  const visibleEvents = useMemo(() => areaBase.filter(e => inCategory(e, catFilter)),
  // eslint-disable-next-line react-hooks/exhaustive-deps
    [areaBase, catFilter]);
  // What tapping each category would show in this map area, with every other active filter applied.
  const categoryCountMap = useMemo(() => Object.fromEntries(CATEGORY_DEFS.map(c => [c.key, areaBase.filter(e => inCategory(e, c.key)).length])),
  // eslint-disable-next-line react-hooks/exhaustive-deps
    [areaBase]);
  // Matching events that have no map location yet: listed apart, never counted as "in this area".
  const noLocationMatches = useMemo(() => baseEvents.filter(e => !e.hasLocation && inCategory(e, catFilter)),
  // eslint-disable-next-line react-hooks/exhaustive-deps
    [baseEvents, catFilter]);
  // Matching events anywhere (for "Show nearest" when this area has none).
  const matchingAnywhere = useMemo(() => baseEvents.filter(e => e.hasLocation && inCategory(e, catFilter)),
  // eslint-disable-next-line react-hooks/exhaustive-deps
    [baseEvents, catFilter]);
  // The filter sheet's market: events IN THE MAP AREA after search + For You, before Home's filters — so its
  // per-pill counts and "Show N" are exactly what the list will show after Apply.
  const sheetItems = useMemo(() => mapResults(searchedEvents, committedBounds).map(discoveryItem), [searchedEvents, committedBounds]);
  // Badge: filters set in the sheet or the time chips (the category row and Seats left show their own state).
  const sheetFilterCount = activeFilterCount({ ...filters, cats: [], seatsLeft: false });
  // Matching events outside this area — explains why the Map can show fewer than Home ("+2 outside this area").
  const outsideCount = matchingAnywhere.length - visibleEvents.filter(e => e.hasLocation).length;
  // Why the list is empty: no events in this area at all, or filters exclude the ones that are here.
  const anyInArea = useMemo(() => mapResults(events, committedBounds).length > 0, [events, committedBounds]);
  // "Seats left" only means something once banbe has real fill for at least one event.
  const anyFillKnown = useMemo(() => events.some(e => e.fillKnown), [events]);


  // ---- draw/refresh pins whenever the event list or selection changes ----
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    // Markers from the previous run stay until the new ones exist: the ones that are still wanted are swapped out
    // at once, the ones that no longer are (filtered away) shrink/fade first. Newly appearing ones grow/fade in.
    const oldMarkers = markersRef.current;
    markersRef.current = [];
    const prevKeys = prevMarkerKeysRef.current;
    const newKeys = new Set();
    const finishOld = () => {
      oldMarkers.forEach((m) => {
        if (newKeys.has(m.__key) || !m.__el) { m.remove(); return; }
        const inner = m.__el.firstElementChild || m.__el;
        inner.style.transition = 'opacity 0.24s ease, transform 0.24s ease';
        inner.style.opacity = '0';
        if (inner !== m.__el) inner.style.transform = 'scale(0.4)';
        setTimeout(() => m.remove(), 250);
      });
    };
    let cancelled = false;
    (async () => {
      const MarkerCtor = markerCtorRef.current;
      if (cancelled || !MarkerCtor) { oldMarkers.forEach(m => m.remove()); return; }
      // Pins are exactly the results (committed area + filters): the same list and count the sheet shows. Rows
      // without coordinates never get an invented position.
      for (const ev of visibleEvents) {
        if (!ev.hasLocation) continue;
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
        // `banbePinPop` animation (deliberately not replayed — see below) to
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
        // NOT `position:relative`: that overrides maplibre's own `.maplibregl-marker{position:absolute}`,
        // turning the shell into a full-width in-flow block, so Marker's translate(-50%,-50%) shifted every
        // pin by half the map width (selected pin landed at the left edge, not the camera centre).
        // The badge dot anchors to `pinEl` (position:relative below) instead.
        const pinEl = document.createElement('div');
        pinEl.style.cssText = `width:30px;height:30px;border-radius:50%;background:${paper};border:1.5px solid ${ink};position:relative;display:flex;align-items:center;justify-content:center;font-size:14px;cursor:pointer;box-shadow:${isSelected ? `0 0 0 3px ${ink}, ` : ''}0 2px 6px rgba(27,25,22,0.3);transform:scale(${isSelected ? 1.15 : 1});z-index:${isSelected ? 1 : 0};`;
        pinEl.setAttribute('data-testid', `map-pin-${ev.id}`);
        // Keyboard + screen reader: a pin is a button named after its event (the list is the full alternative).
        pinEl.setAttribute('role', 'button');
        pinEl.setAttribute('tabindex', '0');
        pinEl.setAttribute('aria-label', ev.name || '');
        if (isSelected) pinEl.setAttribute('aria-pressed', 'true');
        pinEl.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); selectEvent(ev); } });
        pinEl.textContent = CAT_GLYPH[ev.catKey] || CAT_GLYPH.all;
        if (ev.urgent || ev.isNew) {
          const dot = document.createElement('span');
          dot.style.cssText = `position:absolute;top:-2px;right:-2px;width:9px;height:9px;border-radius:50%;background:${ev.urgent ? '#9A3E2D' : '#48582F'};border:1.5px solid ${paper};`;
          pinEl.appendChild(dot);
        }
        const pinKey = `${ev.id}:p`;
        newKeys.add(pinKey);
        if (isSelected && lastAnimatedPinIdRef.current !== ev.id) {
          pinEl.style.animation = 'banbePinPop 0.32s cubic-bezier(.22,.61,.36,1) both';
          lastAnimatedPinIdRef.current = ev.id;
        } else if (prevKeys.size && !prevKeys.has(pinKey)) {
          pinEl.style.animation = 'banbePinIn 0.3s cubic-bezier(.22,.61,.36,1) both';
        }
        pinEl.addEventListener('click', (e) => { e.stopPropagation(); selectEvent(ev); });
        el.appendChild(pinEl);
        const marker = new MarkerCtor({ element: el }).setLngLat([ev.lng, ev.lat]).addTo(map);
        marker.__key = pinKey; marker.__el = el;
        markersRef.current.push(marker);
      }
      prevMarkerKeysRef.current = newKeys;
      finishOld();
    })();
    return () => { cancelled = true; };
    // The `cancelled` guard above keeps an in-flight redraw from a STALE run (rapid filter changes) from painting
    // markers after a newer run has started.
  }, [visibleEvents, selectedId, selectEvent, mapReady]);

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
        // The same whole-set refresh as the timer: camera, area, filters and selection stay put.
        const fresh = await loadLatest();
        if (fresh) setEvents(fresh);
        else throw new Error('refresh failed');
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
  }, [filters]);

  // Map redesign phase 2 (reverses the earlier "selection survives filters" rule, by the owner's spec): the
  // selection lives only while its event is one of the results — the committed area + filters, plus the listed
  // no-location matches. A pan that leaves it outside the area, or a filter that excludes it, clears it; another
  // event is never opened in its place. Filter changes no longer move the camera either (the old category →
  // density-hotspot flight is gone): the area changes only through the map.
  const selectableIds = useMemo(() => [...visibleEvents, ...noLocationMatches].map(e => e.id), [visibleEvents, noLocationMatches]);
  const selectedEvent = useMemo(
    () => (selectedId && selectableIds.includes(selectedId) ? events.find(e => e.id === selectedId) || null : null),
    [events, selectedId, selectableIds],
  );
  // Guarded until data and an area exist, so a restored selection is never cleared before its rows arrive.
  useEffect(() => {
    if (loading || !committedBounds) return;
    const next = selectionAfter(selectedId, selectableIds);
    if (next !== selectedId) setSelectedId(next);
  }, [loading, committedBounds, selectedId, selectableIds]);

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
    if (!map || !selectedEvent || !cardFits) return;
    // If the selection flight is still running, retarget it (padding-only easeTo would cancel it
    // mid-air and leave the pin off-centre); otherwise only the padding changes, never the user's camera.
    // Layout-only: a 'reveal', so following the sheet never redefines the search area.
    moveCamera('reveal', m => m.easeTo({ ...(flightTargetRef.current || {}), padding: cameraPadding(), duration: reduceMotion() ? 0 : 300 }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sheetSnap, containerH, cardHeight, topControlsBottom, cardFits]);

  // A selection must never leave the card without room: if the current sheet level leaves
  // too little map for the card, step the sheet down (tall -> mid -> peek). Runs on selection
  // and on viewport/card changes only — a manual drag afterwards is respected (the card just
  // hides while it does not fit).
  useEffect(() => {
    if (!selectedId) return;
    setSheetSnap(prev => snapForSelection(prev, dims));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedId, containerH, cardHeight, topControlsBottom]);

  // Bug 2: snapshot everything MapExplore itself owns right before handing
  // off to the full-screen Event Detail screen, so returning restores it
  // instead of re-initializing from scratch. Saved into BanBeContext (not
  // local state) because App.jsx's Shell unmounts this whole component the
  // instant `screen` changes away from 'mapExplore'.
  const saveSnapshot = useCallback(() => {
    const map = mapRef.current;
    const center = map?.getCenter();
    setMapExploreState({
      cameraCenter: center ? { lat: center.lat, lng: center.lng } : null,
      cameraZoom: map?.getZoom() ?? null,
      sheetSnap,
      filters, catFilter,
      openNowOnly,
      forYou: forYouOn,
      searchQuery,
      selectedId,
      listScrollTop: listRef.current?.scrollTop ?? 0,
      // Phase 2: the committed area and the rows themselves, so the return shows the same list at once.
      committedBounds, areaContext,
      events,
    });
  }, [sheetSnap, filters, catFilter, openNowOnly, forYouOn, searchQuery, selectedId, committedBounds, areaContext, events, setMapExploreState]);

  // "Show nearest": the closest matching events (same filters) anywhere, framed above the mid sheet — an explicit
  // geographic move that commits its area once. Never automatic, never presented as "here".
  const showNearest = useCallback(() => {
    const map = mapRef.current;
    const el = mapDivRef.current;
    if (!map || !el || !matchingAnywhere.length) return;
    const c = map.getCenter();
    const from = { lat: c.lat, lng: c.lng };
    const first = nearestPoint(matchingAnywhere, from);
    const box = boundsOfPoints(pointsNear(matchingAnywhere, first, 25));
    if (!box) return;
    const size = { width: el.clientWidth || 390, height: el.clientHeight || containerH };
    const cam = fitCamera(box, size, {
      top: topControlsBottom + CARD_GAP + 16, bottom: size.height * (1 - SHEET_SNAPS.mid) + ATTRIB_RESERVE + 16, left: 40, right: 40,
    }, { tileSize: map.__isMapKit ? 256 : 512, maxZoom: 14 });
    moveCamera('nearest', m => m.flyTo({ center: [cam.center.lng, cam.center.lat], zoom: cam.zoom, duration: reduceMotion() ? 0 : 800 }));
  }, [matchingAnywhere, containerH, topControlsBottom, moveCamera]);
  // Area picker = a DESTINATION (phase 3): picking an area on the Map flies to that area's events and commits it once;
  // every filter stays. "Everywhere" or an area with no mapped events leaves the camera where it is (no guessed
  // geometry, never the whole inventory) — the chip then reads "Map area".
  const areaMountedRef = useRef(false);
  useEffect(() => {
    if (!areaMountedRef.current) { areaMountedRef.current = true; return; }
    const map = mapRef.current;
    const el = mapDivRef.current;
    if (!map || !el || curArea.key === 'all') { setAreaContext('map'); return; }
    const box = boundsOfPoints(events.filter(e => e.hasLocation && curArea.match(e)));
    if (!box) { setAreaContext('map'); return; }
    const size = { width: el.clientWidth || 390, height: el.clientHeight || containerH };
    const cam = fitCamera(box, size, {
      top: topControlsBottom + CARD_GAP + 16, bottom: size.height * (1 - SHEET_SNAPS.mid) + ATTRIB_RESERVE + 16, left: 40, right: 40,
    }, { tileSize: map.__isMapKit ? 256 : 512, maxZoom: 14 });
    moveCamera('destination', m => m.flyTo({ center: [cam.center.lng, cam.center.lat], zoom: cam.zoom, duration: reduceMotion() ? 0 : 800 }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [curArea.key]);
  // Distance (km) from the area's centre to the nearest match, for an honest "Show nearest · 1.2 km" hint.
  const nearestKm = useMemo(() => {
    if (!committedBounds || !matchingAnywhere.length) return null;
    const c = { lat: (committedBounds.north + committedBounds.south) / 2, lng: (committedBounds.east + committedBounds.west) / 2 };
    const p = nearestPoint(matchingAnywhere, c);
    return p ? geoKm(c, p) : null;
  }, [committedBounds, matchingAnywhere]);
  // Clear filters: back to everything in THIS area; the map never moves.
  const clearFilters = useCallback(() => {
    setFilters(normalizeFilters(DEFAULT_FILTERS)); setSearchQuery(''); setForYouOn(false);
  }, []);
  const filtersActive = activeFilterCount(filters) > 0 || !!searchQuery.trim() || forYouActive;
  const openEventDetail = useCallback((id) => {
    saveSnapshot();
    goEvent(id);
  }, [saveSnapshot, goEvent]);
  // "Edit preferences": same snapshot/restore as Event Detail, so Back returns to the
  // same camera, sheet, list position and filters.
  const editPreferences = useCallback(() => {
    saveSnapshot();
    openEventPreferences('mapExplore');
  }, [saveSnapshot, openEventPreferences]);
  const toggleForYou = useCallback(() => {
    if (!forYouOn) forYouAlert.acknowledge(forYouRanked.map(m => m.key));
    setForYouOn(!forYouOn);
  }, [forYouOn, forYouRanked, forYouAlert.acknowledge]);

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
    const deltaVh = ((e.clientY - dragState.current.startY) / containerH);
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

  // Inside the desktop phone frame the frame's own 50pt status bar covers the
  // top of this fixed layer, so iOS's "safe area + 8" top controls start below it.
  const topInset = (typeof window !== 'undefined' && window.matchMedia && window.matchMedia('(min-width: 700px) and (min-height: 560px) and (hover: hover) and (pointer: fine)').matches) ? 50 : 0;
  const capsuleGlass = { borderRadius: 999 };

  // ---- row/card facts (all from real columns; nothing guessed) ----
  const en = s.lang === 'en';
  const dense = sheetSnap === 'tall';
  // "Th 4, 05.03 · 19:00" in the venue's own zone (events.tz, migration 195), never the viewer's clock.
  const eventWhen = (ev) => whenLabel(ev.startsAt, ev.tz, en);
  // Price per ticket in the event's own currency; 0 is genuinely free.
  const priceLine = (ev) => (ev.priceVnd > 0
    ? `${formatMoney(ev.priceVnd, ev.currency)} ${T('/ vé', '/ ticket')}`
    : T('Miễn phí', 'Free'));
  const nearDistance = (ev) => (s.located === true && s.userCoords && ev.hasLocation ? distanceLabel(haversineKm(s.userCoords, ev), en) : null);
  // Solid chip (content sits on an opaque sheet; glass is kept for map controls). 36pt tall inside a 44pt row.
  const catChip = (active, muted) => ({
    flex: 'none', display: 'inline-flex', alignItems: 'center', gap: 6, minHeight: 36, padding: '0 12px', borderRadius: RADIUS.pill,
    border: active ? `1px solid ${ink}` : '1px solid transparent', background: active ? ink : surface2, color: active ? paper : ink,
    fontSize: 13, fontWeight: active ? 600 : 500, whiteSpace: 'nowrap', cursor: 'pointer', fontFamily: 'inherit', opacity: muted ? 0.55 : 1,
  });
  // Truthful seat status: sold out / "N left" when few / nothing when banbe has no fill for the event.
  // Header snap buttons (bigger map / bigger list): 44px icon buttons, filled when that snap is on.
  const sizeBtn = (on) => ({ width: 44, height: 44, flex: 'none', border: 'none', borderRadius: 12, cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', background: on ? surface2 : 'transparent', color: ink });
  // Empty-state action: a real 44px button.
  const emptyAction = { display: 'inline-flex', alignItems: 'center', minHeight: 44, marginTop: 8, padding: '0 16px', borderRadius: RADIUS.pill, border: 'none', background: surface2, color: ink, fontSize: 14, fontWeight: 600, cursor: 'pointer', fontFamily: 'inherit' };
  const SeatPill = ({ ev, testId }) => {
    const f = seatFacts(ev);
    if (!f) return null;
    if (f.soldOut) return <span data-testid={testId} style={{ fontSize: 12, fontWeight: 600, color: alert }}>{T('Hết chỗ', 'Sold out')}</span>;
    if (f.almostFull && f.left != null) return <span data-testid={testId} style={{ fontSize: 12, fontWeight: 600, color: ink }}>{T(`Còn ${f.left} chỗ`, `${f.left} left`)}</span>;
    return null;
  };
  return (
    <div ref={rootRef} style={{ position: 'fixed', inset: 0, background: paper }} data-screen-label="MapExplore">
      {/* iOS has no map zoom controls (mapControls {}); the web +/- sits below the compass pill. */}
      <style>{`[data-screen-label="MapExplore"] .maplibregl-ctrl-top-right { top: ${topInset + 56}px; right: 6px; } [data-screen-label="MapExplore"] .bb-noscroll::-webkit-scrollbar { display: none; }
        /* Attribution (required) lives just above the sheet, in the visible map strip. */
        [data-screen-label="MapExplore"] .maplibregl-ctrl-bottom-right { bottom: ${Math.max(0, Math.round(containerH - sheetTopPx))}px; z-index: 3; max-width: calc(100% - 12px); }
        [data-screen-label="MapExplore"] .maplibregl-ctrl-attrib { font-size: 10px; line-height: 1.3; max-width: 100%; }
        [data-screen-label="MapExplore"] .maplibregl-ctrl-bottom-left { display: none; }
        [data-bb-theme="dark"] [data-screen-label="MapExplore"] .maplibregl-ctrl-group { background: var(--bb-field); box-shadow: 0 0 0 1px var(--bb-rule); }
        [data-bb-theme="dark"] [data-screen-label="MapExplore"] .maplibregl-ctrl-group button + button { border-top: 1px solid var(--bb-rule); }
        [data-bb-theme="dark"] [data-screen-label="MapExplore"] .maplibregl-ctrl button .maplibregl-ctrl-icon { filter: invert(1); }
        [data-bb-theme="dark"] [data-screen-label="MapExplore"] .maplibregl-ctrl-attrib { background: rgba(var(--bb-bg-rgb), 0.6); color: var(--bb-fg); }
        [data-bb-theme="dark"] [data-screen-label="MapExplore"] .maplibregl-ctrl-attrib a { color: var(--bb-fg); }`}</style>
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
      <div ref={backRef} onClick={closeMap} data-testid="map-back" style={{ ...photoPill(capsuleGlass), top: topInset + 8, left: 16, padding: '8px 14px', fontWeight: 600, zIndex: 3 }}>
        ← {T('Đóng', 'Close')}
      </div>

      <div
        ref={compassRef}
        onClick={recenterOnUser}
        data-testid="map-compass"
        style={{ ...photoPill({ borderRadius: '50%' }), top: topInset + 8, right: 16, width: 38, height: 38, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 17, opacity: compassOpacity, zIndex: 3 }}
      >
        🧭
      </div>

      {/* No "Tìm ở đây / Search here": the whole public set is loaded, so the results follow the map by
          themselves once it settles. Only an incomplete set (past MAP_EVENT_CAP) says so, below. */}

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
            // Content surface: opaque (readability over the map); glass stays on map controls only.
            background: paper, color: ink, borderRadius: 14, position: 'absolute',
            left: 'max(16px, env(safe-area-inset-left, 0px))', right: 'max(16px, env(safe-area-inset-right, 0px))', zIndex: 4,
            bottom: cardBottomPx,
            // Hidden (not overlapping) when the sheet leaves no room; the selection itself persists.
            opacity: cardFits ? 1 : 0, pointerEvents: cardFits ? 'auto' : 'none',
            transition: dragState.current ? 'opacity 0.15s' : 'bottom 0.28s cubic-bezier(.22,.61,.36,1), opacity 0.15s',
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
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); clearSelection(); }}
                  data-testid="map-card-close"
                  aria-label={T('Bỏ chọn', 'Clear selection')}
                  style={{ width: 44, height: 44, margin: '-12px -12px -12px 0', border: 'none', background: 'none', cursor: 'pointer', color: ink2, fontSize: 20, lineHeight: 1, flex: 'none' }}
                >×</button>
              </div>
              <div data-testid="map-card-when" style={{ fontSize: 12.5, color: ink2, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {[eventWhen(selectedEvent), selectedEvent.area].filter(Boolean).join(' · ')}
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, marginTop: 6 }}>
                <span data-testid="map-card-price" style={{ fontSize: 13.5, color: ink, fontWeight: 600 }}>{priceLine(selectedEvent)}</span>
                <SeatPill ev={selectedEvent} testId="map-card-seats" />
              </div>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            {/* Directions: the same public venue link Event Detail shows (mapsUrl); only when the event has a
                map location. Separate from "View details" so selecting never opens anything by itself. */}
            {mapsUrl(selectedEvent) && (
              <a
                href={mapsUrl(selectedEvent)}
                target="_blank"
                rel="noopener noreferrer"
                data-testid="map-card-directions"
                style={{ flex: '0 0 auto', minHeight: 44, padding: '0 16px', borderRadius: 10, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6, background: clayBg, color: clay, fontSize: 13, fontWeight: 600, textDecoration: 'none' }}
              >
                <svg aria-hidden="true" width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d="M3 11l18-8-8 18-2-8-8-2z" /></svg>
                {T('Chỉ đường', 'Directions')}
              </a>
            )}
            <button
              type="button"
              onClick={() => openEventDetail(selectedEvent.id)}
              data-testid="map-card-cta"
              style={{ ...inkButton({ borderRadius: 10 }), flex: 1, minHeight: 44, padding: '0 12px', fontSize: 13, border: 'none', fontFamily: 'inherit', cursor: 'pointer' }}
            >
              {T('Xem chi tiết', 'View details')}
            </button>
          </div>
        </div>
      )}

      <div
        ref={sheetRef}
        data-testid="map-sheet"
        style={{
          position: 'absolute', left: 0, right: 0, bottom: 0, top: sheetTopPx, zIndex: 4,
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
        {/* One 44px header row (it used to be a grabber row plus a separate "List lớn / List nhỏ" row, which pushed
            the first result under the dock at mid): bigger-map button · drag grabber + the settled result count ·
            bigger-list button. Only the middle drags the sheet. */}
        <div style={{ display: 'flex', alignItems: 'center', padding: '4px 8px 2px' }}>
          <button
            type="button"
            onClick={() => setSheetSnap('peek')}
            data-testid="map-sheet-list-small"
            aria-label={T('Bản đồ lớn', 'Bigger map')}
            aria-pressed={sheetSnap === 'peek'}
            style={sizeBtn(sheetSnap === 'peek')}
          >
            <svg aria-hidden="true" width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2z" /><path d="M9 4v14M15 6v14" /></svg>
          </button>
          <div
            onPointerDown={onHandlePointerDown}
            onPointerMove={onHandlePointerMove}
            onPointerUp={onHandlePointerUp}
            data-testid="map-sheet-handle"
            style={{ flex: 1, minWidth: 0, minHeight: 44, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 6, cursor: 'grab', touchAction: 'none' }}
          >
            <div style={{ width: 36, height: 4, borderRadius: 2, background: rule }} />
            {/* The settled result count for THIS map area — the same list the pins come from. Announced politely
                (it changes only when the camera settles or a filter changes, never every frame). */}
            <span data-testid="map-result-count" aria-live="polite" style={{ fontSize: 13, fontWeight: 600, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '100%' }}>
              {committedBounds && !(loading && !events.length)
                ? T(`${visibleEvents.length} sự kiện trong vùng bản đồ`, `${visibleEvents.length} event${visibleEvents.length === 1 ? '' : 's'} in this map area`)
                : T('Đang tải sự kiện…', 'Loading events…')}
            </span>
          </div>
          <button
            type="button"
            onClick={() => setSheetSnap('tall')}
            data-testid="map-sheet-list-large"
            aria-label={T('Danh sách lớn', 'Bigger list')}
            aria-pressed={sheetSnap === 'tall'}
            style={sizeBtn(sheetSnap === 'tall')}
          >
            <svg aria-hidden="true" width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round"><path d="M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01" /></svg>
          </button>
        </div>

        {/* Home quick event search (2026-09-27) — a plain text filter,
            ANDed with the category/open-now/nearby controls below;
            reuses this screen's own existing list/filter/event-detail
            routing rather than a second search surface. Autofocused on
            arrival from Home's search button (see the mount effect
            above). */}
        {/* No safe-area-top padding here: this is a bottom sheet (it added ~47px on a real iPhone). */}
        <div style={{ padding: '4px 16px 8px' }}>
          <div className="bb-focus-ring" style={{ background: surface2, borderRadius: 12, display: 'flex', alignItems: 'center', gap: 8, padding: '0 12px', minHeight: 44 }}>
            <svg width={15} height={15} viewBox="0 0 24 24" fill="none" stroke={ink} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.55, flex: 'none' }}>
              <circle cx="11" cy="11" r="7" />
              <path d="M21 21l-4.35-4.35" />
            </svg>
            <input
              ref={setSearchInputRef}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              // The matcher covers name, category, area, host and description (src/lib/search.js), not just names.
              placeholder={T('Tìm theo tên, loại, khu vực, người tổ chức…', 'Search name, type, area, host…')}
              aria-label={T('Tìm sự kiện trên bản đồ', 'Search events on the map')}
              data-testid="map-search-input" data-bare
              style={{ flex: 1, minWidth: 0, border: 'none', outline: 'none', background: 'transparent', fontSize: 15, color: ink, fontFamily: "'Be Vietnam Pro', sans-serif" }}
            />
            {searchQuery && (
              <button type="button" onClick={() => setSearchQuery('')} data-testid="map-search-clear" aria-label={T('Xoá tìm kiếm', 'Clear search')}
                style={{ width: 44, height: 44, marginInlineEnd: -12, border: 'none', background: 'none', cursor: 'pointer', color: ink2, fontSize: 18, lineHeight: 1, flex: 'none' }}>×</button>
            )}
          </div>
        </div>


        {/* Categories: Home's own definitions (src/data/eventTypeProfiles.json) and line icons, in a fixed order
            so the row never reshuffles as results change. Each count is what tapping it would show with every
            other filter kept; a selected category stays even at 0. "All categories" opens Home's A–Z sheet. */}
        <div data-hscroll="true" data-testid="map-category-row" role="tablist" aria-label={T('Danh mục', 'Categories')} className="bb-noscroll"
          style={{ display: 'flex', gap: 8, padding: '0 16px 10px', overflowX: 'auto', flex: 'none', scrollbarWidth: 'none' }}>
          {CATEGORY_DEFS.map(c => {
            const active = catFilter === c.key;
            const n = categoryCountMap[c.key] ?? 0;
            return (
              <button
                key={c.key}
                type="button"
                role="tab"
                aria-selected={active}
                aria-label={T(`${c.vi}, ${n} sự kiện`, `${c.en}, ${n} event${n === 1 ? '' : 's'}`)}
                onClick={() => { if (!active || c.key !== 'all') setCatFilter(active ? 'all' : c.key); }}
                data-testid={`map-cat-${c.key}`}
                style={catChip(active, n === 0 && !active)}
              >
                <CategoryGlyph cat={c.key} size={16} strokeWidth={1.8} />
                <span>{T(c.vi, c.en)}</span>
                <span data-testid={`map-cat-count-${c.key}`} style={{ fontVariantNumeric: 'tabular-nums', opacity: active ? 0.85 : 0.6 }}>{n}</span>
              </button>
            );
          })}
          <button type="button" onClick={() => setCategorySheetOpen(true)} data-testid="map-cat-show-all" aria-haspopup="dialog" style={catChip(false, false)}>
            {T('Tất cả danh mục', 'All categories')}
          </button>
        </div>
        {categorySheetOpen && (
          <CategorySheet
            keys={categorySheetKeys(categoryDefs(), s.lang === 'en' ? 'en' : 'vi')}
            counts={categoryCountMap}
            values={catFilter === 'all' ? [] : [catFilter]}
            T={T}
            onPick={(k) => { setCatFilter(catFilter === k ? 'all' : k); setCategorySheetOpen(false); }}
            onClose={() => setCategorySheetOpen(false)}
          />
        )}

        {/* For You is pinned at the leading edge (never scrolls away); only the other chips
            live in the horizontal scroller, which keeps data-hscroll so the root tab swipe
            ignores it. Hidden until the account has saved preferences. */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '0 0 10px', paddingInlineStart: 16, flex: 'none' }}>
        {hasPrefs && (
          <ForYouChip
            T={T}
            active={forYouActive}
            pending={forYouAlert.pending}
            animate={forYouAlert.animate}
            capsuleStyle={{ background: surface2, borderRadius: RADIUS.pill, display: 'inline-flex', alignItems: 'center', minHeight: 36, padding: '0 12px', fontSize: 13, cursor: 'pointer', color: ink, fontWeight: forYouActive ? 700 : 500, border: forYouActive ? `1px solid ${ink}` : '1px solid transparent', whiteSpace: 'nowrap' }}
            onClick={toggleForYou}
          />
        )}
        <div data-hscroll="true" data-testid="map-filter-extra-scroller" className="bb-noscroll" style={{ flex: '1 1 0', minWidth: 0, display: 'flex', gap: 8, paddingInlineEnd: 16, overflowX: 'auto', scrollbarWidth: 'none' }}>
          {/* Location hierarchy — opens the same shared area sheet Home
              uses (AreaSheet.jsx); shows the current short label. */}
          <button
            type="button"
            onClick={openArea}
            data-testid="map-chip-area"
            aria-haspopup="dialog"
            style={catChip(false, false)}
          >
            {/* The geographic context: the picked area while the map is framed on it, else "Map area". */}
            {areaContext === 'area' && curArea.key !== 'all' ? curArea.label : T('Vùng bản đồ', 'Map area')} ▾
          </button>
          {/* Time quick chips apply at once, judged in each event's own venue time zone (homeDiscovery). */}
          {[['tonight', 'Tối nay', 'Tonight'], ['weekend', 'Cuối tuần', 'Weekend']].map(([opt, vi, en]) => (
            <button key={opt} type="button" aria-pressed={filters.date === opt} onClick={() => toggleDate(opt)}
              data-testid={`map-chip-${opt}`} style={catChip(filters.date === opt, false)}>
              {T(vi, en)}
            </button>
          ))}
          {/* Seats left: real fill only (get_public_event_fill), so it is hidden until banbe has any. The old
              English label "Open now" read like opening hours; events have seats, not hours. */}
          {(anyFillKnown || openNowOnly) && (
            <button
              type="button"
              aria-pressed={openNowOnly}
              onClick={() => setOpenNowOnly(v => !v)}
              data-testid="map-chip-open-now"
              style={catChip(openNowOnly, false)}
            >
              {T('Còn chỗ', 'Seats left')}
            </button>
          )}
          {/* Everything else (any date, price per ticket, almost full, type chips) in Home's sheet, as a draft. */}
          <button type="button" onClick={() => setFilterSheetOpen(true)} data-testid="map-chip-filters" aria-haspopup="dialog"
            style={catChip(sheetFilterCount > 0, false)}>
            <svg aria-hidden="true" width={15} height={15} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round"><path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0" /><circle cx="16" cy="6" r="2" /><circle cx="10" cy="12" r="2" /><circle cx="18" cy="18" r="2" /></svg>
            {T('Bộ lọc', 'Filters')}{sheetFilterCount > 0 ? ` · ${sheetFilterCount}` : ''}
          </button>
        </div>
        </div>
        {filterSheetOpen && (
          <HomeFilterSheet
            mapMode
            simpleShell
            items={sheetItems}
            filters={filters}
            sort="soonest"
            now={nowMinute * 60000}
            T={T}
            canSortNearest={false}
            onApply={(draft) => { setFilters(normalizeFilters(draft)); setFilterSheetOpen(false); }}
            onClose={() => setFilterSheetOpen(false)}
          />
        )}
        {forYouActive && (
          <div style={{ padding: '0 16px 8px' }}>
            <span
              onClick={editPreferences}
              data-testid="map-foryou-edit-prefs"
              role="button"
              style={{ fontSize: 12.5, fontWeight: 600, textDecoration: 'underline', cursor: 'pointer', color: ink }}
            >
              {T('Chỉnh sở thích của bạn', 'Edit preferences')}
            </span>
          </div>
        )}

        {/* Status notices (only when there is something to say): updating, a failed refresh, an incomplete set. */}
        {((refreshing && events.length > 0) || (loadError && events.length > 0) || !dataMeta.complete || (outsideCount > 0 && visibleEvents.length > 0)) && (
        <div style={{ padding: '0 16px 6px', display: 'flex', alignItems: 'baseline', gap: 8, flexWrap: 'wrap' }}>
          {refreshing && events.length > 0 && <span style={{ fontSize: 12, color: ink2 }}>{T('Đang cập nhật…', 'Updating…')}</span>}
          {outsideCount > 0 && visibleEvents.length > 0 && (
            <span data-testid="map-outside-count" style={{ fontSize: 12, color: ink2 }}>
              {T(`+${outsideCount} sự kiện khớp nằm ngoài vùng này`, `+${outsideCount} matching event${outsideCount === 1 ? '' : 's'} outside this area`)}
            </span>
          )}
          {/* A failed refresh keeps the last good results and says so; Retry reloads the whole set. */}
          {loadError && events.length > 0 && (
            <span data-testid="map-refresh-error" role="status" style={{ fontSize: 12, color: ink2 }}>
              {T('Chưa cập nhật được.', 'Couldn’t update.')}{' '}
              <button type="button" onClick={refresh} data-testid="map-retry" style={{ border: 'none', background: 'none', padding: 0, minHeight: 32, color: ink, fontWeight: 600, textDecoration: 'underline', cursor: 'pointer', fontFamily: 'inherit', fontSize: 12 }}>
                {T('Thử lại', 'Retry')}
              </button>
            </span>
          )}
          {!dataMeta.complete && (
            <span data-testid="map-incomplete" style={{ fontSize: 12, color: ink2 }}>
              {T(`Đang hiện ${events.length}/${dataMeta.total} sự kiện · phóng to để xem kỹ hơn`, `Showing ${events.length} of ${dataMeta.total} events · zoom in for more`)}
            </span>
          )}
        </div>
        )}

        <div
          ref={listRef}
          data-testid="map-list-scroll"
          style={{ flex: 1, overflowY: 'auto', padding: `0 16px calc(${dockClear + 16}px + env(safe-area-inset-bottom, 0px))`, position: 'relative', touchAction: 'pan-y', overscrollBehavior: 'contain' }}
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
          {forYouActive && visibleEvents.length === 0 && (loading || prefsLoading) && (
            <div data-testid="map-foryou-loading" style={{ padding: 20, color: ink, opacity: 0.6, fontSize: 13 }}>{T('Đang tìm sự kiện hợp với bạn…', 'Finding events for you…')}</div>
          )}
          {forYouActive && visibleEvents.length === 0 && !loading && !prefsLoading && (
            <div data-testid="map-foryou-empty" style={{ padding: 20, color: ink, fontSize: 13 }}>
              <div style={{ opacity: 0.7 }}>
                {forYouRanked.length === 0
                  ? T('Chưa có sự kiện nào hợp với sở thích của bạn trong khu vực/vùng bản đồ này.', 'No events match your preferences in this area or map view yet.')
                  : T('Các sự kiện hợp với bạn không khớp bộ lọc hiện tại.', 'Your For You matches don\'t fit the current filters.')}
              </div>
              <span onClick={editPreferences} data-testid="map-foryou-empty-edit" role="button" style={{ display: 'inline-block', marginTop: 8, fontWeight: 600, textDecoration: 'underline', cursor: 'pointer' }}>
                {T('Chỉnh sở thích của bạn', 'Edit preferences')}
              </span>
            </div>
          )}
          {/* Empty states, each one honest about WHY (never silently widening the area or loosening filters):
              first load · failed first load · no events in this area · filters hide the events that are here. */}
          {loading && !forYouActive && visibleEvents.length === 0 && <div data-testid="map-loading" style={{ padding: 20, color: ink2, fontSize: 14 }}>{T('Đang tải…', 'Loading…')}</div>}
          {!loading && loadError && events.length === 0 && (
            <div data-testid="map-load-failed" style={{ padding: 20, color: ink, fontSize: 14 }}>
              <div style={{ color: ink2 }}>{T('Chưa tải được sự kiện. Kiểm tra kết nối mạng rồi thử lại.', 'Couldn’t load events. Check your connection and try again.')}</div>
              <button type="button" onClick={refresh} data-testid="map-load-retry" style={emptyAction}>{T('Thử lại', 'Try again')}</button>
            </div>
          )}
          {!loading && !forYouActive && visibleEvents.length === 0 && committedBounds && events.length > 0 && (
            anyInArea && filtersActive ? (
              <div data-testid="map-search-no-results" style={{ padding: 20, color: ink, fontSize: 14 }}>
                <div style={{ color: ink2 }}>
                  {searchQuery.trim()
                    ? T(`Không có sự kiện nào trong vùng này khớp với "${searchQuery.trim()}".`, `No events in this area match "${searchQuery.trim()}".`)
                    : T('Có sự kiện trong vùng này nhưng bộ lọc đang ẩn chúng.', 'There are events in this area, but your filters hide them.')}
                </div>
                <button type="button" onClick={clearFilters} data-testid="map-clear-filters" style={emptyAction}>{T('Xoá bộ lọc', 'Clear filters')}</button>
              </div>
            ) : (
              <div data-testid="map-area-empty" style={{ padding: 20, color: ink, fontSize: 14 }}>
                <div style={{ color: ink2 }}>{T('Không có sự kiện nào trong vùng bản đồ này.', 'No events in this part of the map.')}</div>
                {matchingAnywhere.length > 0 && (
                  <button type="button" onClick={showNearest} data-testid="map-show-nearest" style={emptyAction}>
                    {nearestKm != null && nearestKm >= 1
                      ? T(`Xem gần nhất · cách ${Math.round(nearestKm)} km`, `Show nearest · ${Math.round(nearestKm)} km away`)
                      : T('Xem sự kiện gần nhất', 'Show nearest events')}
                  </button>
                )}
              </div>
            )
          )}
          {/* The results, then (apart, never counted as "in this area") matching events with no map location. */}
          {[...visibleEvents, ...noLocationMatches].map((ev, i) => (
            <Fragment key={ev.id}>
            {i === visibleEvents.length && (
              <div data-testid="map-no-location-heading" style={{ padding: '16px 0 4px', fontSize: 13, fontWeight: 600, color: ink2 }}>
                {T(`Chưa có vị trí trên bản đồ (${noLocationMatches.length})`, `No map location yet (${noLocationMatches.length})`)}
              </div>
            )}
            <div
              onClick={() => selectEvent(ev)}
              data-testid={`map-list-item-${ev.id}`}
              role="button"
              tabIndex={0}
              aria-current={ev.id === selectedId ? 'true' : undefined}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); selectEvent(ev); } }}
              // Mid = cards (photo + three lines); tall = a denser list (small photo, two lines).
              style={{ display: 'flex', gap: 12, padding: dense ? '8px 0' : '12px 0', borderBottom: `1px solid ${rule}`, cursor: 'pointer', alignItems: dense ? 'center' : 'flex-start', animation: 'banbeRowIn 0.3s cubic-bezier(.22,.61,.36,1) backwards', background: ev.id === selectedId ? 'rgba(var(--bb-fg-rgb),0.05)' : 'transparent' }}
            >
              {ev.img && <div style={{ width: dense ? 44 : 64, height: dense ? 44 : 64, borderRadius: RADIUS.thumb, backgroundImage: `url(${ev.img})`, backgroundSize: 'cover', backgroundPosition: 'center', flexShrink: 0 }} />}
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 15, fontWeight: 600, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ev.name}</div>
                {/* Venue date · time (the event's own zone), then the area, plus a distance only when it helps
                    choose (≤ 50 km, Event Detail's rule; a viewer abroad saw "9662,0 km" on every row). */}
                <div data-testid={`map-list-item-when-${ev.id}`} style={{ fontSize: 13, color: ink2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  {[eventWhen(ev), dense ? ev.area : null].filter(Boolean).join(' · ')}
                </div>
                {!dense && (
                  <div data-testid={`map-list-item-area-${ev.id}`} style={{ fontSize: 13, color: ink2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {[ev.area, nearDistance(ev)].filter(Boolean).join(' · ')}
                  </div>
                )}
                {/* Stage 3 — an honest "no map location" state for an
                    event with no (or not-yet-confirmed) coordinates,
                    never a silently-omitted row or an invented pin. */}
                {!ev.hasLocation && (
                  <div data-testid={`map-list-item-no-location-${ev.id}`} style={{ fontSize: 10.5, color: ink, opacity: 0.55, marginTop: 2 }}>
                    {T('Chưa có vị trí trên bản đồ', 'No map location yet')}
                  </div>
                )}
              </div>
              <div style={{ flex: 'none', display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4 }}>
                <div data-testid={`map-list-item-price-${ev.id}`} style={{ fontSize: 14, fontWeight: 600, color: ink, whiteSpace: 'nowrap' }}>{priceLine(ev)}</div>
                <SeatPill ev={ev} testId={`map-list-item-seats-${ev.id}`} />
              </div>
            </div>
            </Fragment>
          ))}
        </div>
      </div>
    </div>
  );
}

function boundsToBox(bounds) {
  return { north: bounds.getNorth(), south: bounds.getSouth(), east: bounds.getEast(), west: bounds.getWest() };
}
