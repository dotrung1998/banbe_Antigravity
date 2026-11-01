import { screenHeight } from '../lib/viewport.js';
import { loadMapStyle } from '../lib/mapStyle.js';
import { loadMapKit } from '../lib/mapkit.js';
import { createMapKitMap } from '../lib/mapkitAdapter.js';
import { SHEET_SNAPS, CARD_GAP, ATTRIB_RESERVE, computeMapLayout, snapAfterSelect, snapAfterUserPan, dockShown, snapAfterDrag, snapFractions, peekFraction } from '../lib/mapLayout.js';
import { Fragment, useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { useBanBe, resolveCoverUrl, photoUrlsByEvent } from '../state/BanBeContext.jsx';
import { cardPhotoList } from '../lib/eventPhotoUrls.js';
import { addRecentSearch, loadRecentSearches, saveRecentSearches } from '../lib/mapRecentSearches.js';
import { supabase } from '../lib/supabase.js';
import { withR2Columns, marketColumnList, detailsColumnList } from '../lib/mediaUrls.js';
import {
  reasonCommits, referenceRect, boundsForRect, mapResults, selectionAfter, boundsOfPoints, pointsNear, nearestPoint,
  fitCamera, distanceKm as geoKm, sameSpot, padBounds, cityFor, searchCities, cityGroups, activeFilterSummary, CITY_ZOOM,
} from '../lib/mapDiscovery.js';
import citiesData from '../data/cities.json';
import { cityOfNode } from '../lib/locationTree.js';
import { findEvent, isCosmeticCatalogMatch, haversineKm, mapsUrl } from '../data/events.js';
import { distanceLabel } from '../lib/eventDetailPresentation.js';
import { whenLabel } from '../lib/quickWins.js';
import { fillBadge, categorySheetKeys, applyDiscoveryFilters, normalizeFilters, activeFilterCount, DEFAULT_FILTERS } from '../lib/homeDiscovery.js';
import HomeFilterSheet, { DATE_LABELS } from './sheets/HomeFilterSheet.jsx';
import { secondCategory, categoryDefs, cardLine, profileFor } from '../lib/eventTypes.js';
import { CategoryGlyph, CATEGORY_DEFS, CategorySheet, categoryGlyphMarkup, DiscoveryCard } from '../components/home/HomeDiscoveryParts.jsx';
import { liveEventOverrides } from '../lib/countdown.js';
import { formatMoney, formatMoneyShort, rowCurrency, rowTimeZone, cardDateBadge } from '../lib/eventMarket.js';
import { densityHotspot } from '../lib/densityHotspot.js';
import { buildEventSearchDoc, matchesSearchQuery } from '../lib/search.js';
import { prefsIsEmpty } from '../lib/eventPrefs.js';
import { mapForYouSet, applyForYouFilter } from '../lib/forYou.js';
import { useForYouAlert } from '../lib/useForYouAlert.js';
import ForYouChip from './ForYouChip.jsx';
import { paper, ink, ink2, rule, alert, clay, clayBg, surface2, photoPill, inkButton, RADIUS } from '../theme.js';
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
// Map v5 (note 73): cities the Map can search, fly to and group by when zoomed out (src/data/cities.json, shared
// with iOS). Main cities are always offered in the area picker, with or without events.
const CITIES = citiesData.cities;
const CITY_BY_ID = new Map(CITIES.map(c => [c.id, c]));
const MAIN_CITY_IDS = ['vn-hcm', 'vn-hanoi', 'vn-danang'];
// Map v6 (note 74): the full-height list's layout ('large' photo cards, the default, or 'compact' rows), remembered
// for this session only (module scope: survives Event Detail round trips and reopening the Map, never stored, and
// separate from Home's own banbe_home_layout_v1).
let sessionListLayout = 'large';

async function fetchLiveEvents({ limit = MAP_EVENT_CAP, bounds = null } = {}) {
  const buildQuery = (withR2) => {
  let q = supabase
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
  // Bounded mode only (the public set is larger than the cap): the committed area, padded, with its own count.
  if (bounds) q = q.gte('lat', bounds.south).lte('lat', bounds.north).gte('lng', bounds.west).lte('lng', bounds.east);
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
  // Real seat fill (migration 186, the same RPC Home uses): `seats_remaining` is never decremented after insert
  // (note 50), so it can't say "sold out" or "few left". No fill row = no seat status, never a guess.
  // Map v6 (note 74): up to 6 public photos per event (one batched query) for the Large cards' pager.
  const [photosByEvent, fillById] = await Promise.all([photoUrlsByEvent(rows.map(r => r.id)), loadFill(rows.map(r => r.id))]);

  const shaped = rows.map(row => {
    const isCosmeticMatch = isCosmeticCatalogMatch(row.id);
    const cosmetic = isCosmeticMatch ? findEvent(row.id) : null;
    const cover = isCosmeticMatch ? cosmetic?.img : resolveCoverUrl(row.cover_image, photosByEvent[row.id]?.[0], row.cover_r2_ref);
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
      img: cover,
      // Cover first, then the other public photos, max 6 (this query is public events only).
      // Catalogue rows page through their live photos too (not the bundled stock gallery), like Home's cards.
      imgs: isCosmeticMatch ? (photosByEvent[row.id]?.length ? cardPhotoList(null, photosByEvent[row.id]) : [cover].filter(Boolean)) : cardPhotoList(cover, photosByEvent[row.id]),
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
  const { state: s, set, T, resolvedTheme, goEvent, backFromMapExplore, allowLocation, setMapExploreState, curArea, openArea, openEventPreferences, shareEvent, isSaved, toggleFav } = useBanBe();
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
  // The camera's zoom after each settle: clustering (display only) follows it; the results never do.
  const [cameraZoom, setCameraZoom] = useState(null);
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
  // Map v6 (note 74): search mode. True while the search input has focus; while it is also empty, the sheet shows
  // Recent / Cities / Quick filters instead of the list ("never a blank search"). `searchReturnRef` is the snap the
  // search was opened from, so Cancel puts the sheet back there.
  const [searchActive, setSearchActive] = useState(false);
  const searchReturnRef = useRef(null);
  const searchQueryRef = useRef('');
  searchQueryRef.current = searchQuery;
  const [recentSearches, setRecentSearches] = useState(() => loadRecentSearches());
  const rememberSearch = useCallback((q) => {
    if (!String(q || '').trim()) return;
    setRecentSearches(prev => {
      const next = addRecentSearch(prev, q);
      saveRecentSearches(next);
      return next;
    });
  }, []);
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
  // Map v5 (note 73) sticky filters: the search + chips fold into one summary line once the list is scrolled or an
  // event is selected; tapping the line opens them again (`headerOpen`) until the next scroll or selection.
  const [listScrolled, setListScrolled] = useState(false);
  const [headerOpen, setHeaderOpen] = useState(false);
  // The city the map was last flown to (search row, area picker or a city bubble): names the area chip while framed.
  const [cityDest, setCityDest] = useState(() => restored?.cityDest ?? null);
  // Owner, 2026-10-24 ("no events on the map until I pull down"): each load takes a number and only the newest one
  // may write the list, so a slow, stale answer can never overwrite a newer, good one. iOS twin: mapEventsGeneration.
  // A failed load keeps the last good rows and raises `loadError` (Retry), never an empty list.
  const loadSeq = useRef(0);
  const loadLatest = async (opts) => {
    const n = ++loadSeq.current;
    try {
      const res = await fetchLiveEvents(opts);
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
  // The top controls' real bottom edge is measured (ResizeObserver), never guessed.
  const backRef = useRef(null);
  const compassRef = useRef(null);
  const rootRef = useRef(null);
  const [topControlsBottom, setTopControlsBottom] = useState(56); // px from the TOP of this screen's own box
  const [containerH, setContainerH] = useState(() => screenHeight());
  const [dockClear, setDockClear] = useState(110); // px the floating dock occupies at the bottom
  // Map v6 (note 74): tall is FULL height (the sheet's top just under the Close / compass row, measured) and peek
  // fits the two-row strip. `mapStripFraction` follows the drag continuously: the sheet's `top` and the camera
  // padding read it.
  const fractions = snapFractions(containerH, topControlsBottom);
  const mapStripFraction = Math.min(0.95, Math.max(0.02, fractions[sheetSnap] + dragOffsetVh));
  // Map v6: Large photo cards / Compact rows at full height (see `sessionListLayout`).
  const [listLayout, setListLayoutState] = useState(() => restored?.listLayout ?? sessionListLayout);
  const setListLayout = useCallback((m) => { sessionListLayout = m; setListLayoutState(m); }, []);

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
      // Map v5: the dock slides away below tall; measuring it then would read its off-screen position.
      const dockHiddenNow = document.querySelector('[data-testid="dock-row"]')?.dataset.hidden === 'true';
      if (tab && !dockHiddenNow) {
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

  // ---- layout geometry (all px, relative to this screen's box) ----
  // Visible map = [topControlsBottom + gap, sheetTop - attribution strip]; the camera pads to match. Map v5: the
  // selected event is shown inside the sheet, so nothing floats over the map.
  const lay = computeMapLayout({ containerH, topControlsBottom, stripFraction: mapStripFraction });
  const { sheetTopPx } = lay;
  const layRef = useRef(lay);
  layRef.current = lay;
  const cameraPadding = () => layRef.current.cameraPadding;

  // Map v5 (note 73): the dock shows only at tall (owner, 2026-11-01: hide fully below it). The shell keeps it mounted
  // and slides it away; leaving the Map always gives it back.
  useEffect(() => { set({ mapDockHidden: !dockShown(sheetSnap) }); }, [sheetSnap]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => () => set({ mapDockHidden: false }), []); // eslint-disable-line react-hooks/exhaustive-deps

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
      bottomInset: size.height - (peekFraction(size.height) * size.height - ATTRIB_RESERVE),
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
    // Map v6: a search that led to an event is worth remembering; the keyboard goes down.
    if (searchQueryRef.current.trim()) rememberSearch(searchQueryRef.current);
    searchInputRef.current?.blur();
    setSelectedId(ev.id);
    // Map v5 (note 73): the selected event is the first item of the sheet's list, so the sheet goes to mid (room for
    // the map above and the row below) and the list scrolls back to its top, where the row is.
    setSheetSnap(snapAfterSelect());
    setHeaderOpen(false);
    listRef.current?.scrollTo?.({ top: 0 });
    const map = mapRef.current;
    if (!map) return;
    // Padding keeps the selected pin between the top controls and the MID sheet it is going to.
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
    const g = geomRef.current;
    const padding = computeMapLayout({ containerH: g.containerH, topControlsBottom: g.topControlsBottom, stripFraction: SHEET_SNAPS.mid }).cameraPadding;
    moveCamera('reveal', m => m.flyTo({ ...target, padding, duration: reduceMotion() ? 0 : 550 }));
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
        // MapKit JS never says whether a move is a gesture: a start with no fresh programmatic reason is the user's.
        const pending = cameraReasonRef.current;
        const userMove = !!e?.originalEvent || (map.__isMapKit && !(pending && Date.now() - pending.t < 1500));
        if (e?.originalEvent) cameraReasonRef.current = { reason: 'user', t: Date.now() };
        // Map v5 (note 73), Airbnb-style: the user's own pan/zoom drops the list from mid to peek, where the strip
        // keeps the count and the active filters. Selections, restores, clusters and destinations never do.
        if (userMove) setSheetSnap(snapAfterUserPan);
        clearTimeout(settleTimerRef.current);
      });
      // The live zoom drives clustering (display only); rounded so tiny settles don't redraw every marker.
      map.on('moveend', () => { setCameraZoom(Math.round(map.getZoom() * 4) / 4); onCameraSettled(); });
      // A tap on the map background (not a pin — those are separate marker
      // DOM elements, never reaches this) clears the selected-event card.
      // This is a genuine click, not `moveend`, so it can never be confused
      // with "Search here" (that's tied only to the explicit button).
      map.on('click', () => setSelectedId(null));
      mapRef.current = map;
      setMapReady(true);
      setCameraZoom(map.getZoom());
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
  // Bounded mode (phase 4): only when the whole public set is larger than MAP_EVENT_CAP. Each committed area then
  // loads its own events (padded ×1.5, exact count, newest request wins); the "Showing N of M" notice stays honest.
  // With the set complete (production today) this never runs and panning stays network-free.
  const boundedRef = useRef(false);
  const committedRef = useRef(committedBounds);
  committedRef.current = committedBounds;
  const boundedOpts = () => (boundedRef.current && committedRef.current ? { bounds: padBounds(committedRef.current, 1.5) } : undefined);
  useEffect(() => {
    if (dataMeta.complete && !boundedRef.current) return;
    if (!committedBounds) return;
    boundedRef.current = true;
    let live = true;
    (async () => {
      const rows = await loadLatest(boundedOpts());
      if (live && rows) setEvents(rows);
    })();
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [committedBounds]);
  const refresh = useCallback(async () => {
    setRefreshing(true);
    const fresh = await loadLatest(boundedOpts());
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

  // ---- Map v5 (note 73): cities ----
  // Each loaded event's city (its city / province column, else the smallest city box around it; no DB change).
  const cityIdById = useMemo(() => new Map(events.map(e => [e.id, cityFor(e, CITIES)])), [events]);
  // Events per city with every filter except the search text and the map area (the text may be the city's name).
  const cityCounts = useMemo(() => {
    const list = applyDiscoveryFilters(applyForYouFilter(events, forYouActive, forYouOrder).map(discoveryItem), filters, nowMinute * 60000);
    const out = {};
    for (const { ev } of list) {
      const id = cityIdById.get(ev.id);
      if (id) out[id] = (out[id] || 0) + 1;
    }
    return out;
  }, [events, forYouActive, forYouOrder, filters, nowMinute, cityIdById]);
  // Cities matching the search text, shown above the results ("Đà Lạt · 2 events" → Go).
  const cityMatches = useMemo(() => searchCities(searchQuery, CITIES, cityCounts), [searchQuery, cityCounts]);
  // The area picker's Cities section (AreaSheet reads it while the Map is open): cities with events, most first,
  // then the main cities so there is always somewhere to go.
  const pickerCities = useMemo(() => {
    const withEvents = CITIES.filter(c => cityCounts[c.id] > 0).sort((a, b) => cityCounts[b.id] - cityCounts[a.id]);
    const rest = MAIN_CITY_IDS.filter(id => !withEvents.some(c => c.id === id)).map(id => CITY_BY_ID.get(id));
    return [...withEvents, ...rest].map(c => ({ id: c.id, count: cityCounts[c.id] || 0 }));
  }, [cityCounts]);
  const pickerCitiesKey = JSON.stringify(pickerCities);
  useEffect(() => { set({ mapCities: pickerCities }); }, [pickerCitiesKey]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => () => set({ mapCities: null, mapCityRequest: null }), []); // eslint-disable-line react-hooks/exhaustive-deps
  // flyToCity is defined further down (it needs the camera helpers); markers drawn above reach it through this ref.
  const flyToCityRef = useRef(null);
  const cityName = (id) => { const c = CITY_BY_ID.get(id); return c ? (en ? c.en : c.vi) : ''; };


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
      // Markers are exactly the results (committed area + filters), grouped for display only (phase 4): every result
      // is in exactly one pin, cluster or stack, so the markers always add up to the count. Rows without coordinates
      // never get an invented position. A selected event is pulled out of its cluster so it stays visible; at the
      // same place it stays in its stack (the card steps through it).
      const located = visibleEvents.filter(e => e.hasLocation);
      const byId = new Map(located.map(e => [e.id, e]));
      const sel = byId.get(selectedId);
      const selStacked = !!sel && sameSpot(located, sel).length > 1;
      const groupable = sel && !selStacked ? located.filter(e => e.id !== sel.id) : located;
      const zoom = cameraZoom ?? map.getZoom();
      // Zoomed out, one bubble per city (Map v5); closer in, pins/clusters/stacks. MapKit's zoom is one level above
      // the 512 px basis the grouping uses (same world size).
      const zoom512 = map.__isMapKit ? zoom - 1 : zoom;
      const groups = cityGroups(groupable, zoom512, p => cityIdById.get(p.id), CITIES);
      if (sel && !selStacked) groups.push({ kind: 'pin', ids: [sel.id], lat: sel.lat, lng: sel.lng });
      for (const g of groups) {
        const ev = byId.get(g.ids[0]);
        const isSelected = g.ids.includes(selectedId);
        // MapLibre's Marker owns the OUTER element's transform (it rewrites it on every update), so all our styling,
        // scale and animation live on an inner child; the outer shell stays a plain positioning box (not
        // position:relative, which would shift every marker by half the map width).
        const el = document.createElement('div');
        const pinEl = document.createElement('div');
        const key = `${g.kind}:${g.ids.join(',')}`;
        newKeys.add(key);
        if (g.kind === 'city') {
          // City bubble (zoomed out): "TP.HCM  5"; tap = fly to that city.
          const c = CITY_BY_ID.get(g.cityId);
          const n = g.ids.length;
          pinEl.style.cssText = `height:34px;padding:0 6px 0 12px;box-sizing:border-box;border-radius:17px;background:${paper};color:${ink};border:1.5px solid ${ink};display:flex;align-items:center;gap:8px;font:700 13px/1 'Be Vietnam Pro',sans-serif;white-space:nowrap;cursor:pointer;box-shadow:0 2px 8px rgba(27,25,22,0.32);`;
          pinEl.setAttribute('data-testid', `map-city-${g.cityId}`);
          pinEl.setAttribute('data-count', String(n));
          pinEl.setAttribute('aria-label', T(`${c.vi}, ${n} sự kiện, phóng tới`, `${c.en}, ${n} event${n === 1 ? '' : 's'}, go there`));
          pinEl.textContent = en ? c.short.en : c.short.vi;
          const badge = document.createElement('span');
          badge.style.cssText = `min-width:22px;height:22px;padding:0 7px;box-sizing:border-box;border-radius:11px;background:${ink};color:${paper};display:inline-flex;align-items:center;justify-content:center;font:700 12px/1 'Be Vietnam Pro',sans-serif;`;
          badge.textContent = String(n);
          pinEl.appendChild(badge);
          const activate = () => flyToCityRef.current?.(g.cityId);
          pinEl.addEventListener('click', (e) => { e.stopPropagation(); activate(); });
          pinEl.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); activate(); } });
        } else if (g.kind === 'pin') {
          // Pin = the category's line icon + the price per ticket in its own currency ("Free" when 0), Map v5: the
          // same icons as the category row, so the row reads as the key. Selected = ink fill.
          const label = ev.priceVnd > 0 ? formatMoneyShort(ev.priceVnd, ev.currency) : T('Miễn phí', 'Free');
          const cat = CATEGORY_DEFS.find(c => c.key === ev.catKey);
          pinEl.style.cssText = `height:30px;min-width:30px;padding:0 10px 0 8px;gap:5px;box-sizing:border-box;border-radius:15px;background:${isSelected ? ink : paper};color:${isSelected ? paper : ink};border:1.5px solid ${ink};position:relative;display:flex;align-items:center;justify-content:center;font:600 12.5px/1 'Be Vietnam Pro',sans-serif;white-space:nowrap;cursor:pointer;box-shadow:0 2px 6px rgba(27,25,22,0.3);transform:scale(${isSelected ? 1.12 : 1});`;
          pinEl.setAttribute('data-testid', `map-pin-${ev.id}`);
          pinEl.setAttribute('data-cat', ev.catKey || 'all');
          pinEl.setAttribute('aria-label', [ev.name || '', cat ? T(cat.vi, cat.en) : null, label].filter(Boolean).join(', '));
          pinEl.innerHTML = categoryGlyphMarkup(ev.catKey, 14, 2);
          const priceSpan = document.createElement('span');
          priceSpan.textContent = label;
          pinEl.appendChild(priceSpan);
          // Close in (street level) or selected: the event's name under the pin, Corner-style. Absolute, so the
          // marker's own anchor never moves.
          if (zoom512 >= 15 || isSelected) {
            const name = document.createElement('span');
            name.setAttribute('data-testid', `map-pinname-${ev.id}`);
            name.style.cssText = `position:absolute;top:calc(100% + 4px);left:50%;transform:translateX(-50%);max-width:140px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font:600 11.5px/1.2 'Be Vietnam Pro',sans-serif;color:${ink};text-shadow:0 0 3px ${paper},0 0 3px ${paper},0 0 2px ${paper};pointer-events:none;`;
            name.textContent = ev.name || '';
            pinEl.appendChild(name);
          }
          if (ev.urgent) {
            const dot = document.createElement('span');
            dot.style.cssText = `position:absolute;top:-3px;right:-3px;width:9px;height:9px;border-radius:50%;background:#9A3E2D;border:1.5px solid ${paper};`;
            pinEl.appendChild(dot);
          }
          const activate = () => selectEvent(ev);
          pinEl.addEventListener('click', (e) => { e.stopPropagation(); activate(); });
          pinEl.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); activate(); } });
        } else {
          // Cluster (zoom in) or stack (same place: select the first; the card steps through the rest).
          const n = g.ids.length;
          const stack = g.kind === 'stack';
          pinEl.style.cssText = `height:${stack ? 30 : 36}px;min-width:${stack ? 30 : 36}px;padding:0 ${stack ? 10 : 6}px;box-sizing:border-box;border-radius:18px;background:${isSelected ? ink : paper};color:${isSelected ? paper : ink};border:${stack ? 1.5 : 2}px solid ${ink};display:flex;align-items:center;justify-content:center;gap:4px;font:700 13px/1 'Be Vietnam Pro',sans-serif;cursor:pointer;box-shadow:0 2px 8px rgba(27,25,22,0.32);`;
          pinEl.setAttribute('data-testid', `map-${g.kind}-${g.ids[0]}`);
          pinEl.setAttribute('data-count', String(n));
          pinEl.setAttribute('aria-label', stack
            ? T(`${n} sự kiện cùng địa điểm`, `${n} events at this place`)
            : T(`${n} sự kiện ở đây, phóng to`, `${n} events here, zoom in`));
          pinEl.textContent = stack ? `${n} ≡` : String(n);
          const activate = () => (stack ? selectEvent(byId.get(g.ids[0])) : zoomToCluster(g));
          pinEl.addEventListener('click', (e) => { e.stopPropagation(); activate(); });
          pinEl.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); activate(); } });
        }
        // Keyboard + screen reader: every marker is a button (the list is the full alternative).
        pinEl.setAttribute('role', 'button');
        pinEl.setAttribute('tabindex', '0');
        if (isSelected) pinEl.setAttribute('aria-pressed', 'true');
        pinEl.style.zIndex = isSelected ? '1' : '0';
        if (isSelected && lastAnimatedPinIdRef.current !== selectedId) {
          if (!reduceMotion()) pinEl.style.animation = 'banbePinPop 0.32s cubic-bezier(.22,.61,.36,1) both';
          lastAnimatedPinIdRef.current = selectedId;
        } else if (prevKeys.size && !prevKeys.has(key) && !reduceMotion()) {
          pinEl.style.animation = 'banbePinIn 0.3s cubic-bezier(.22,.61,.36,1) both';
        }
        el.appendChild(pinEl);
        const marker = new MarkerCtor({ element: el }).setLngLat([g.lng, g.lat]).addTo(map);
        marker.__key = key; marker.__el = el;
        markersRef.current.push(marker);
      }
      prevMarkerKeysRef.current = newKeys;
      finishOld();
    })();
    return () => { cancelled = true; };
    // The `cancelled` guard above keeps an in-flight redraw from a STALE run (rapid filter changes or zooming) from
    // painting markers after a newer run has started.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visibleEvents, selectedId, selectEvent, mapReady, cameraZoom, cityIdById]);

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
  // Large cards' photos load in the background while the list is still small, so opening to full never shows them
  // half-loaded (iOS parity, CardPhotoPrefetch). The browser cache then serves the cards' own <img>s.
  const preloadKey = visibleEvents.slice(0, 8).map(e => e.id).join(',');
  useEffect(() => {
    for (const ev of visibleEvents.slice(0, 8)) for (const src of (ev.imgs?.length ? ev.imgs : [ev.img]).slice(0, 2)) {
      if (src) { const im = new Image(); im.decoding = 'async'; im.src = src; }
    }
  }, [preloadKey]); // eslint-disable-line react-hooks/exhaustive-deps
  // iOS parity (owner 2026-11-01): no pull-to-refresh on the Map list (the set reloads every 60 s). At the list's
  // TOP a pull down, and at its END (mid) a push up, move the SHEET with the finger instead of over-scrolling the
  // list; release snaps like a handle drag. Touch listeners are non-passive so the list can be held still.
  const edgeRef = useRef({});
  edgeRef.current = { sheetSnap, containerH, fractions };
  useEffect(() => {
    const el = listRef.current;
    if (!el) return undefined;
    let g = null;
    const start = (e) => {
      const y = e.touches[0].clientY;
      g = { y0: y, lastY: y, lastT: e.timeStamp, v: 0, active: null, snap: edgeRef.current.sheetSnap,
        atTop: el.scrollTop <= 0, atEnd: el.scrollTop >= el.scrollHeight - el.clientHeight - 1 };
    };
    const move = (e) => {
      if (!g) return;
      const y = e.touches[0].clientY, dy = y - g.y0;
      if (g.active === null) {
        if ((g.atTop && dy > 4 && g.snap !== 'peek') || (g.atEnd && dy < -4 && g.snap === 'mid')) g.active = true;
        else if (Math.abs(dy) > 4) g.active = false;
      }
      if (!g.active) return;
      e.preventDefault();
      const dt = e.timeStamp - g.lastT;
      if (dt > 0) g.v = 0.6 * ((y - g.lastY) / dt) + 0.4 * g.v;
      g.lastY = y; g.lastT = e.timeStamp;
      setDragOffsetVh(dy / (edgeRef.current.containerH || 1));
    };
    const end = (e) => {
      if (g?.active) {
        const { containerH: H, fractions: f } = edgeRef.current;
        const v = e.timeStamp - g.lastT > 120 ? 0 : g.v;
        setSheetSnap(snapAfterDrag(g.snap, g.lastY - g.y0, H, v, f));
        setDragOffsetVh(0);
      }
      g = null;
    };
    el.addEventListener('touchstart', start, { passive: true });
    el.addEventListener('touchmove', move, { passive: false });
    el.addEventListener('touchend', end);
    el.addEventListener('touchcancel', end);
    return () => { el.removeEventListener('touchstart', start); el.removeEventListener('touchmove', move); el.removeEventListener('touchend', end); el.removeEventListener('touchcancel', end); };
  }, []);

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
    if (!map || !selectedEvent) return;
    // If the selection flight is still running, retarget it (padding-only easeTo would cancel it
    // mid-air and leave the pin off-centre); otherwise only the padding changes, never the user's camera.
    // Layout-only: a 'reveal', so following the sheet never redefines the search area.
    moveCamera('reveal', m => m.easeTo({ ...(flightTargetRef.current || {}), padding: cameraPadding(), duration: reduceMotion() ? 0 : 300 }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sheetSnap, containerH, topControlsBottom]);

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
      committedBounds, areaContext, cityDest,
      events,
      // Map v6: the full-height layout (Large / Compact).
      listLayout,
    });
  }, [sheetSnap, filters, catFilter, openNowOnly, forYouOn, searchQuery, selectedId, committedBounds, areaContext, cityDest, events, listLayout, setMapExploreState]);

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
    setCityDest(null);
    const map = mapRef.current;
    const el = mapDivRef.current;
    if (!map || !el || curArea.key === 'all') { setAreaContext('map'); return; }
    const box = boundsOfPoints(events.filter(e => e.hasLocation && curArea.match(e)));
    if (!box) {
      // Map v6 (note 74): a city node with no mapped events still has somewhere to go: the city's own box.
      const city = cityOfNode(curArea.key);
      if (city && CITY_BY_ID.has(city.id)) { flyToCityRef.current?.(city.id); return; }
      setAreaContext('map');
      return;
    }
    const size = { width: el.clientWidth || 390, height: el.clientHeight || containerH };
    const cam = fitCamera(box, size, {
      top: topControlsBottom + CARD_GAP + 16, bottom: size.height * (1 - SHEET_SNAPS.mid) + ATTRIB_RESERVE + 16, left: 40, right: 40,
    }, { tileSize: map.__isMapKit ? 256 : 512, maxZoom: 14 });
    moveCamera('destination', m => m.flyTo({ center: [cam.center.lng, cam.center.lat], zoom: cam.zoom, duration: reduceMotion() ? 0 : 800 }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [curArea.key]);
  // Tap a cluster: zoom in to fit its events (at least one level), an explicit move that commits its area once.
  const zoomToCluster = useCallback((g) => {
    const map = mapRef.current;
    const el = mapDivRef.current;
    if (!map || !el || !g.bounds) return;
    const size = { width: el.clientWidth || 390, height: el.clientHeight || containerH };
    const cam = fitCamera(g.bounds, size, {
      top: topControlsBottom + CARD_GAP + 16, bottom: size.height * (1 - SHEET_SNAPS.mid) + ATTRIB_RESERVE + 16, left: 48, right: 48,
    }, { tileSize: map.__isMapKit ? 256 : 512, maxZoom: 18 });
    const zoom = Math.max(cam.zoom, map.getZoom() + 1);
    moveCamera('cluster', m => m.flyTo({ center: [cam.center.lng, cam.center.lat], zoom, duration: reduceMotion() ? 0 : 600 }));
  }, [containerH, topControlsBottom, moveCamera]);
  // Map v5 (note 73): fly to a city (search row, area picker, city bubble). A destination: commits its area once, keeps
  // every filter, works with no events there (the city's own box, never guessed from events), sheet to mid.
  const flyToCity = useCallback((id) => {
    const map = mapRef.current;
    const el = mapDivRef.current;
    const c = CITY_BY_ID.get(id);
    if (!map || !el || !c) return;
    const size = { width: el.clientWidth || 390, height: el.clientHeight || containerH };
    const cam = fitCamera(c.bounds, size, {
      top: topControlsBottom + CARD_GAP + 16, bottom: size.height * (1 - SHEET_SNAPS.mid) + ATTRIB_RESERVE + 16, left: 24, right: 24,
    }, { tileSize: map.__isMapKit ? 256 : 512, maxZoom: 13 });
    // A big city box (HCMC with Cần Giờ) fits below CITY_ZOOM, which would just show the same city bubble again:
    // land at least half a level past it, centred on the city itself.
    const minZoom = CITY_ZOOM + 0.5 + (map.__isMapKit ? 1 : 0);
    if (cam.zoom < minZoom) { cam.zoom = minZoom; cam.center = c.center; }
    setCityDest(id);
    setSelectedId(null);
    setSheetSnap('mid');
    moveCamera('destination', m => m.flyTo({ center: [cam.center.lng, cam.center.lat], zoom: cam.zoom, duration: reduceMotion() ? 0 : 800 }));
  }, [containerH, topControlsBottom, moveCamera]);
  flyToCityRef.current = flyToCity;
  // A city picked in the area sheet (AreaSheet.jsx) arrives as a one-shot request.
  useEffect(() => {
    const req = s.mapCityRequest;
    if (!req || !mapReady) return;
    set({ mapCityRequest: null });
    flyToCity(req.id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [s.mapCityRequest?.t, mapReady]);
  const goCity = useCallback((id) => {
    if (searchQueryRef.current.trim()) rememberSearch(searchQueryRef.current);
    searchInputRef.current?.blur();
    setSearchQuery('');
    flyToCity(id);
  }, [flyToCity, rememberSearch]);

  // Events at the selected event's place (the card's ‹ 1/3 › switcher); itself only when it stands alone.
  const selectedStack = useMemo(() => (selectedEvent ? sameSpot(visibleEvents, selectedEvent) : []), [selectedEvent, visibleEvents]);
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
  // (see `closingProgress` below), just without a
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
    // Map v6: the release speed matters too (a flick up from peek goes to full), so the last moves are tracked.
    dragState.current = { startY: e.clientY, startSnap: sheetSnap, lastY: e.clientY, lastT: e.timeStamp || performance.now(), v: 0 };
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
    const d = dragState.current;
    const t = e.timeStamp || performance.now();
    const dt = t - d.lastT;
    // px per ms, lightly smoothed so one jittery frame can't fake a flick.
    if (dt > 0) d.v = 0.6 * ((e.clientY - d.lastY) / dt) + 0.4 * d.v;
    d.lastY = e.clientY; d.lastT = t;
    setDragOffsetVh((e.clientY - d.startY) / containerH);
  };
  const onHandlePointerUp = (e) => {
    const d = dragState.current;
    if (!d) return;
    const y = e?.clientY ?? d.lastY;
    // A pause before letting go is not a flick.
    const v = (e?.timeStamp || performance.now()) - d.lastT > 120 ? 0 : d.v;
    setSheetSnap(snapAfterDrag(d.startSnap, y - d.startY, containerH, v, fractions));
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
  // Amount + an outlined ticket icon (iOS parity: "/ ticket" kept getting cut off); the label keeps "/ ticket".
  const priceTicket = (ev) => (ev.priceVnd > 0 ? (<>
    {formatMoney(ev.priceVnd, ev.currency)}
    <svg aria-hidden="true" width={17} height={17} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.7} strokeLinejoin="round"><path d="M3 7.5A1.5 1.5 0 0 1 4.5 6h15A1.5 1.5 0 0 1 21 7.5V10a2 2 0 0 0 0 4v2.5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 16.5V14a2 2 0 0 0 0-4z" /><path d="M14.5 6v2M14.5 11v2M14.5 16v2" /></svg>
  </>) : T('Miễn phí', 'Free'));
  const nearDistance = (ev) => (s.located === true && s.userCoords && ev.hasLocation ? distanceLabel(haversineKm(s.userCoords, ev), en) : null);
  // Solid chip (content sits on an opaque sheet; glass is kept for map controls). 36pt tall inside a 44pt row.
  const sectionLabel = { padding: '12px 0 4px', fontSize: 11.5, fontWeight: 600, letterSpacing: '0.04em', textTransform: 'uppercase', color: ink2 };
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
  // ---- Map v5 (note 73): the active filter summary (peek strip + compact sticky header), one source ----
  // The picked category leads the folded line (owner 2026-11-01): "Supper club, Seats left" + a count of 2.
  const summary = (() => {
    const base = activeFilterSummary(filters, { forYou: forYouActive, query: searchQuery });
    if (catFilter === 'all' || base.tokens.some(t => t.kind === 'cat' && t.key === catFilter)) return base;
    return { tokens: [{ kind: 'cat', key: catFilter }, ...base.tokens], count: base.count + 1 };
  })();
  // The city the map is centred on (smallest cities.json box holding the centre): map pill + full-height list line.
  const mapCity = (() => {
    const b = committedBounds;
    if (!b) return null;
    const lat = (b.north + b.south) / 2, lng = (b.east + b.west) / 2;
    let best = null;
    for (const c of citiesData.cities || []) {
      const x = c.bounds;
      if (!x || lat > x.north || lat < x.south || lng > x.east || lng < x.west) continue;
      if (!best || (x.north - x.south) * (x.east - x.west) < (best.bounds.north - best.bounds.south) * (best.bounds.east - best.bounds.west)) best = c;
    }
    return best ? T(best.vi, best.en) : null;
  })();
  const tokenLabel = (t) => {
    switch (t.kind) {
      case 'query': return `“${t.text}”`;
      case 'cat': { const c = CATEGORY_DEFS.find(d => d.key === t.key); return c ? T(c.vi, c.en) : t.key; }
      case 'forYou': return T('Dành cho bạn', 'For You');
      case 'date': return DATE_LABELS[t.key] ? T(...DATE_LABELS[t.key]) : t.key;
      case 'free': return T('Miễn phí', 'Free');
      case 'price': {
        const m = (v) => formatMoneyShort(v, t.currency);
        if (t.min != null && t.max != null) return `${m(t.min)}–${m(t.max)}`;
        return t.min != null ? `≥ ${m(t.min)}` : `≤ ${m(t.max)}`;
      }
      case 'seatsLeft': return T('Còn chỗ', 'Seats left');
      case 'almostFull': return T('Sắp hết chỗ', 'Almost full');
      case 'types': return T(`+${t.n} bộ lọc`, `+${t.n} filter${t.n === 1 ? '' : 's'}`);
      default: return '';
    }
  };
  const summaryText = summary.tokens.map(tokenLabel).filter(Boolean).join(', ');
  // Fold the search + chips into one line once the list is scrolled or an event is selected (more room for the row).
  const compactHeader = sheetSnap !== 'peek' && !headerOpen && !searchActive && (listScrolled || !!selectedEvent);
  // ---- Map v6 (note 74): search from the peek strip, and what the search shows before you type ----
  // The input is collapsed (but mounted and focusable) at peek and behind the folded summary line.
  const searchCollapsed = !searchActive && (sheetSnap === 'peek' || compactHeader);
  // Map v6 (note 74): Large photo cards (default) or Compact rows — Home's two-icon switch; session-only on the Map.
  const layoutSwitch = (
            <div role="radiogroup" aria-label={T('Kiểu hiển thị', 'Layout')} data-testid="map-layout-switch"
              style={{ display: 'flex', gap: 2, padding: 2, borderRadius: 999, background: 'rgba(var(--bb-fg-rgb),0.06)', flex: 'none' }}>
              {[['large', T('Ảnh lớn', 'Large photos'), 'M4 4h16v7H4zM4 13h16v7H4z'], ['compact', T('Danh sách gọn', 'Compact list'), 'M4 6h16M4 12h16M4 18h16']].map(([m, lbl, d]) => (
                <button key={m} type="button" role="radio" aria-checked={listLayout === m} aria-label={lbl} onClick={() => setListLayout(m)} data-testid={`map-layout-${m}`}
                  style={{ width: 34, height: 30, borderRadius: 999, border: 'none', cursor: 'pointer', color: ink, display: 'flex', alignItems: 'center', justifyContent: 'center',
                    background: listLayout === m ? 'var(--bb-bg)' : 'transparent', boxShadow: listLayout === m ? '0 1px 3px rgba(27,25,22,0.18)' : 'none' }}>
                  <svg aria-hidden="true" width={15} height={15} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d={d} /></svg>
                </button>
              ))}
            </div>
  );
  // 0 at mid (or lower) → 1 at full height, following the sheet while it is dragged. Drives the Airbnb-style hand-off
  // (owner 2026-11-01; iOS twin `fullProgress`): the map's back / compass shrink away as the sheet's own back / Show
  // map pop in beside a narrower search field. The springy curve gives the little "bubble" overshoot.
  const fullP = Math.min(1, Math.max(0, (fractions.mid - ((fractions[sheetSnap] ?? fractions.mid) + dragOffsetVh)) / Math.max(0.01, fractions.mid - fractions.tall)));
  const sideP = searchActive ? 0 : fullP;
  const bubble = 'cubic-bezier(0.34, 1.56, 0.64, 1)';
  const sideBtn = { flex: 'none', width: 40 * sideP, height: 40, margin: `0 ${2 * sideP}px`, borderRadius: 20, border: 'none', background: surface2, color: ink, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', padding: 0, overflow: 'hidden',
    transform: `scale(${sideP})`, opacity: sideP, pointerEvents: sideP > 0.5 ? 'auto' : 'none', transition: dragOffsetVh ? 'none' : `width 0.32s ${bubble}, margin 0.32s ${bubble}, transform 0.32s ${bubble}, opacity 0.2s ease` };
  const mapCtlFade = { opacity: 1 - fullP, transform: `scale(${1 - 0.35 * fullP})`, transformOrigin: 'top center', pointerEvents: fullP > 0.5 ? 'none' : undefined,
    transition: dragOffsetVh ? 'none' : `transform 0.32s ${bubble}, opacity 0.2s ease` };
  // Focused and empty: Recent · Cities · Quick filters instead of the list ("never a blank search").
  const suggestOpen = searchActive && !searchQuery.trim();
  const openSearch = () => {
    searchReturnRef.current = sheetSnap;
    // Synchronously, inside this tap (the input is already mounted): iOS Safari only raises the keyboard for a
    // focus() in the user gesture — see the long comment at setSearchInputRef.
    searchInputRef.current?.focus({ preventScroll: true });
    setSearchActive(true);
    setHeaderOpen(true);
    // Full height, not mid: the keyboard covers the lower half, so mid would hide the results.
    setSheetSnap('tall');
  };
  const onSearchFocus = () => {
    if (searchReturnRef.current == null) searchReturnRef.current = sheetSnap;
    setSearchActive(true);
  };
  const onSearchBlur = () => {
    setSearchActive(false);
    searchReturnRef.current = null;
  };
  const cancelSearch = () => {
    const back = searchReturnRef.current;
    searchInputRef.current?.blur();
    setSearchActive(false);
    searchReturnRef.current = null;
    if (back && back !== sheetSnap) setSheetSnap(back);
  };
  // Quick filters (peek strip + the search's "Quick filters"): a tap applies the filter and opens the list to mid,
  // like tapping the strip (filter changes already lift to mid; For You is not in `filters`, so it is explicit).
  const quickTap = (fn) => () => {
    fn();
    searchInputRef.current?.blur();
    setSheetSnap('mid');
  };
  // The busiest categories in this map area (what tapping each would show), plus the selected one.
  const topCats = CATEGORY_DEFS
    .filter(c => c.key !== 'all' && ((categoryCountMap[c.key] ?? 0) > 0 || catFilter === c.key))
    .sort((a, b) => (categoryCountMap[b.key] ?? 0) - (categoryCountMap[a.key] ?? 0))
    .slice(0, 3);
  const quickChips = (prefix, withCats) => (
    <>
      {hasPrefs && (
        <button type="button" aria-pressed={forYouActive} onClick={quickTap(toggleForYou)} data-testid={`${prefix}-foryou`} style={catChip(forYouActive, false)}>
          <span aria-hidden="true" style={{ color: forYouActive ? paper : 'var(--bb-honey)' }}>★</span>{T('Dành cho bạn', 'For You')}
        </button>
      )}
      {[['tonight', 'Tối nay', 'Tonight'], ['weekend', 'Cuối tuần', 'Weekend']].map(([opt, vi, en2]) => (
        <button key={opt} type="button" aria-pressed={filters.date === opt} onClick={quickTap(() => toggleDate(opt))}
          data-testid={`${prefix}-${opt}`} style={catChip(filters.date === opt, false)}>
          {T(vi, en2)}
        </button>
      ))}
      {withCats ? topCats.map(c => {
        const active = catFilter === c.key;
        const n = categoryCountMap[c.key] ?? 0;
        return (
          <button key={c.key} type="button" aria-pressed={active} onClick={quickTap(() => setCatFilter(active ? 'all' : c.key))}
            aria-label={T(`${c.vi}, ${n} sự kiện`, `${c.en}, ${n} event${n === 1 ? '' : 's'}`)}
            data-testid={`${prefix}-cat-${c.key}`} style={catChip(active, false)}>
            <CategoryGlyph cat={c.key} size={15} strokeWidth={1.8} />
            <span>{T(c.vi, c.en)}</span>
            <span style={{ fontVariantNumeric: 'tabular-nums', opacity: active ? 0.85 : 0.6 }}>{n}</span>
          </button>
        );
      }) : (anyFillKnown || openNowOnly) && (
        <button type="button" aria-pressed={openNowOnly} onClick={quickTap(() => setOpenNowOnly(v => !v))} data-testid={`${prefix}-open-now`} style={catChip(openNowOnly, false)}>
          {T('Còn chỗ', 'Seats left')}
        </button>
      )}
      <button type="button" onClick={() => { searchInputRef.current?.blur(); setFilterSheetOpen(true); }} data-testid={withCats ? 'map-peek-all-filters' : 'map-search-all-filters'} aria-haspopup="dialog"
        style={{ ...catChip(sheetFilterCount > 0, false), background: sheetFilterCount > 0 ? ink : 'transparent', border: `1px solid ${sheetFilterCount > 0 ? ink : rule}` }}>
        <svg aria-hidden="true" width={15} height={15} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round"><path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0" /><circle cx="16" cy="6" r="2" /><circle cx="10" cy="12" r="2" /><circle cx="18" cy="18" r="2" /></svg>
        {T('Tất cả bộ lọc', 'All filters')}{sheetFilterCount > 0 ? ` · ${sheetFilterCount}` : ''}
      </button>
    </>
  );
  // A Map event in Home's DiscoveryCard shape (Large layout at full height): the photos page sideways, the name and
  // numbers stay off the photo, venue time · area underneath, the category as the type line.
  const largeCard = (ev) => {
    const f = seatFacts(ev);
    const cat = CATEGORY_DEFS.find(c => c.key === ev.catKey && c.key !== 'all');
    const free = !(ev.priceVnd > 0);
    return {
      // Home's card (iOS parity, owner 2026-11-01): the date chip on the photo, area · category underneath, and the
      // event type line ("Table for 3 · Vegetarian-friendly · 18+") when the type has one.
      key: ev.id, name: ev.name, img: ev.img, imgs: ev.imgs, dateBadge: ev.startsAt ? cardDateBadge(Date.parse(ev.startsAt), ev.tz, T) : null,
      priceLabel: free ? T('Miễn phí', 'Free') : formatMoney(ev.priceVnd, ev.currency), isFree: free,
      metaLine: [ev.area, nearDistance(ev), cat ? T(cat.vi, cat.en) : null].filter(Boolean).join(' · '),
      typeLine: cardLine(profileFor(ev.catKey), { capacity: ev.capacity, details: ev.details || {} }, en ? 'en' : 'vi') || null,
      fill: f ? { soldOut: f.soldOut, almostFull: f.almostFull, left: f.left } : null,
      saved: isSaved(ev.id),
    };
  };
  // What the search shows while it is focused and empty: Recent (this device only), Cities (with counts, tap = go
  // there) and the quick filters. mousedown never blurs the input, so a tap here lands before the keyboard closes.
  const suggestRow = { display: 'flex', gap: 8, overflowX: 'auto', scrollbarWidth: 'none', paddingBottom: 4 };
  const searchPanel = (
    <div data-testid="map-search-suggest" onMouseDown={(e) => { if (e.target.closest('button')) e.preventDefault(); }}>
      {recentSearches.length > 0 && (
        <div data-testid="map-search-recent">
          <div style={sectionLabel}>{T('Gần đây', 'Recent')}</div>
          <div data-hscroll="true" className="bb-noscroll" style={suggestRow}>
            {recentSearches.map((q, i) => (
              <button key={q} type="button" onClick={() => setSearchQuery(q)} data-testid={`map-search-recent-${i}`} style={catChip(false, false)}>
                <svg aria-hidden="true" width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" style={{ opacity: 0.6 }}><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></svg>
                {q}
              </button>
            ))}
          </div>
        </div>
      )}
      {pickerCities.length > 0 && (
        <div data-testid="map-search-cities">
          <div style={sectionLabel}>{T('Thành phố', 'Cities')}</div>
          <div data-hscroll="true" className="bb-noscroll" style={suggestRow}>
            {pickerCities.map(({ id, count }) => (
              <button key={id} type="button" onClick={() => goCity(id)} data-testid={`map-search-city-${id}`} style={catChip(false, false)}
                aria-label={count ? T(`${cityName(id)}, ${count} sự kiện`, `${cityName(id)}, ${count} event${count === 1 ? '' : 's'}`) : cityName(id)}>
                <svg aria-hidden="true" width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinejoin="round" style={{ color: clay }}><path d="M12 21s7-6.2 7-11.5A7 7 0 0 0 5 9.5C5 14.8 12 21 12 21Z" /><circle cx="12" cy="9.5" r="2.5" /></svg>
                {cityName(id)}
                {count > 0 && <span style={{ fontVariantNumeric: 'tabular-nums', opacity: 0.6 }}>{count}</span>}
              </button>
            ))}
          </div>
        </div>
      )}
      <div data-testid="map-search-quick">
        <div style={sectionLabel}>{T('Lọc nhanh', 'Quick filters')}</div>
        <div data-hscroll="true" className="bb-noscroll" style={{ ...suggestRow, flexWrap: 'wrap' }}>
          {quickChips('map-search-chip', false)}
        </div>
      </div>
    </div>
  );
  const expandHeader = () => {
    setHeaderOpen(true);
    setListScrolled(false);
    listRef.current?.scrollTo?.({ top: 0 });
  };
  // Owner 2026-11-01: any scroll down folds the filters into one line, any scroll up (or the top) opens them again,
  // whatever is filtered. A short pause after each change so the list's own resize is not read as a scroll.
  const lastListY = useRef(0);
  // An active chip moves to the front (CSS order); scroll its row back there so it is never left out of view.
  const catRowRef = useRef(null);
  const chipRowRef = useRef(null);
  const activeChipKey = `${filters.date}|${openNowOnly}|${sheetFilterCount}`;
  useEffect(() => { catRowRef.current?.scrollTo?.({ left: 0, behavior: 'smooth' }); }, [catFilter]);
  useEffect(() => { chipRowRef.current?.scrollTo?.({ left: 0, behavior: 'smooth' }); }, [activeChipKey]);
  const foldSettle = useRef(0);
  const onListScroll = (e) => {
    const y = e.currentTarget.scrollTop;
    const dy = y - lastListY.current;
    lastListY.current = y;
    if (Date.now() < foldSettle.current) return;
    let fold = null;
    if (y <= 4) fold = false;
    else if (dy > 12) fold = true;
    else if (dy < -12) fold = false;
    if (fold === null || fold === (listScrolled && !headerOpen)) return;
    foldSettle.current = Date.now() + 350;
    setListScrolled(fold);
    if (fold) setHeaderOpen(false);
  };
  const clearChip = (testId) => (
    <button type="button" onClick={(e) => { e.stopPropagation(); clearFilters(); }} data-testid={testId}
      style={{ flex: 'none', minHeight: 44, padding: '0 10px', border: 'none', background: 'none', color: clay, fontSize: 13.5, fontWeight: 600, cursor: 'pointer', fontFamily: 'inherit' }}>
      {T('Xoá', 'Clear')}
    </button>
  );
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
        [data-screen-label="MapExplore"] .maplibregl-ctrl-bottom-right { display: ${sheetSnap === 'tall' ? 'none' : 'block'}; bottom: ${Math.max(0, Math.round(containerH - sheetTopPx))}px; z-index: 3; max-width: calc(100% - 12px); }
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
      <div ref={backRef} onClick={closeMap} data-testid="map-back" role="button" aria-label={T('Đóng bản đồ', 'Close map')}
        style={{ ...photoPill({ ...capsuleGlass, borderRadius: '50%' }), top: topInset + 8, left: 16, width: 38, height: 38, display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 3, ...mapCtlFade }}>
        {/* Arrow only (owner 2026-11-01); the label still says what it does. */}
        <svg aria-hidden="true" width={17} height={17} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round"><path d="M19 12H5M11 6l-6 6 6 6" /></svg>
      </div>

      <div
        ref={compassRef}
        onClick={recenterOnUser}
        data-testid="map-compass"
        style={{ ...photoPill({ borderRadius: '50%' }), top: topInset + 8, right: 16, width: 38, height: 38, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 17, zIndex: 3, ...mapCtlFade, opacity: compassOpacity * (1 - fullP) }}
      >
        🧭
      </div>
      {/* The city the map is on, centred between back and compass; fades away with them at full height. */}
      {mapCity && (
        <div data-testid="map-city" aria-label={T(`Bản đồ đang ở ${mapCity}`, `Map showing ${mapCity}`)}
          style={{ ...photoPill(capsuleGlass), top: topInset + 10, left: '50%', transform: `translateX(-50%) scale(${1 - 0.35 * fullP})`, transformOrigin: 'top center', opacity: 1 - fullP,
            maxWidth: 'calc(100% - 140px)', height: 34, padding: '0 12px', display: 'flex', alignItems: 'center', gap: 5, fontSize: 13, fontWeight: 600, whiteSpace: 'nowrap', pointerEvents: 'none', zIndex: 3,
            transition: dragOffsetVh ? 'none' : `transform 0.32s ${bubble}, opacity 0.2s ease` }}>
          <svg aria-hidden="true" width={13} height={13} viewBox="0 0 24 24" fill="none" stroke={clay} strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" style={{ flex: 'none' }}><path d="M12 21s-6-5.3-6-10a6 6 0 0 1 12 0c0 4.7-6 10-6 10z" /><circle cx="12" cy="11" r="2" /></svg>
          <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{mapCity}</span>
        </div>
      )}
      {/* Full height: a floating "Map" pill above the dock brings the map back (owner 2026-11-01, Airbnb-like). */}
      {sheetSnap === 'tall' && !searchActive && !dragOffsetVh && (
        <button type="button" onClick={() => setSheetSnap('mid')} data-testid="map-sheet-map-button" aria-label={T('Xem bản đồ', 'Show map')} className="bb-pop-in"
          style={{ position: 'absolute', left: '50%', bottom: 'calc(env(safe-area-inset-bottom, 0px) + 92px)', transform: 'translateX(-50%)', zIndex: 6, height: 48, padding: '0 20px', borderRadius: 999, border: 'none',
            background: ink, color: paper, display: 'flex', alignItems: 'center', gap: 8, fontSize: 15, fontWeight: 600, fontFamily: 'inherit', cursor: 'pointer', boxShadow: '0 4px 14px rgba(27,25,22,0.28)' }}>
          {T('Bản đồ', 'Map')}
          <svg aria-hidden="true" width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2zM9 4v14M15 6v14" /></svg>
        </button>
      )}

      {/* No "Tìm ở đây / Search here": the whole public set is loaded, so the results follow the map by
          themselves once it settles. Only an incomplete set (past MAP_EVENT_CAP) says so, below. */}

      <div
        ref={sheetRef}
        data-testid="map-sheet"
        style={{
          position: 'absolute', left: 0, right: 0, bottom: 0, top: sheetTopPx, zIndex: 4,
          background: paper, borderRadius: sheetSnap === 'tall' ? 0 : '20px 20px 0 0', boxShadow: '0 -6px 24px rgba(27,25,22,0.18)',
          display: 'flex', flexDirection: 'column',
          // Full height reaches the top of the screen: keep the grabber and search row below the status bar.
          paddingTop: sheetSnap === 'tall' ? 'env(safe-area-inset-top, 0px)' : 0,
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
            (full height only, Map v6) the Large / Compact switch · bigger-list button. Only the middle drags. */}
        <div style={{ display: sheetSnap === 'tall' ? 'none' : 'flex', alignItems: 'center', padding: '4px 8px 2px' }}>
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
            onPointerCancel={onHandlePointerUp}
            data-testid="map-sheet-handle"
            style={{ flex: 1, minWidth: 0, minHeight: 44, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 6, cursor: 'grab', touchAction: 'none' }}
          >
            {sheetSnap !== 'tall' && <div style={{ width: 36, height: 4, borderRadius: 2, background: rule }} />}
            {/* The settled result count for THIS map area — the same list the pins come from. Announced politely
                (it changes only when the camera settles or a filter changes, never every frame). */}
            <span data-testid="map-result-count" aria-live="polite" style={{ fontSize: 13, fontWeight: 600, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '100%' }}>
              {committedBounds && !(loading && !events.length)
                ? T(`${visibleEvents.length} sự kiện trong vùng bản đồ`, `${visibleEvents.length} event${visibleEvents.length === 1 ? '' : 's'} in this map area`)
                : T('Đang tải sự kiện…', 'Loading events…')}
            </span>
          </div>
          {/* Map v6 (note 74): at full height, Large photo cards (default) or Compact rows — the same two-icon switch
              and look as Home's cards / list toggle; remembered for this session on the Map only. */}
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

        {/* Map v5 (note 73): at peek the strip keeps the count (above) + what is filtered; tap = back to mid.
            Map v6 (note 74): plus one row that earns its space — search, the quick filters and All filters. */}
        {sheetSnap === 'peek' && (
          <>
            <div data-testid="map-peek-summary" role="button" tabIndex={0} onClick={() => setSheetSnap('mid')}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setSheetSnap('mid'); } }}
              aria-label={T('Mở danh sách', 'Open the list')}
              style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '0 6px 0 16px', minHeight: 36, cursor: 'pointer' }}>
              <span data-testid="map-peek-summary-text" style={{ flex: 1, minWidth: 0, fontSize: 13.5, fontWeight: summary.count ? 600 : 400, color: summary.count ? ink : ink2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {summary.count ? summaryText : T('Chưa lọc gì · vuốt lên để xem danh sách', 'No filters · swipe up for the list')}
              </span>
              {outsideCount > 0 && visibleEvents.length > 0 && !summary.count && (
                <span data-testid="map-outside-count" style={{ flex: 'none', fontSize: 12, color: ink2, paddingInlineEnd: 10 }}>
                  {T(`+${outsideCount} ngoài vùng`, `+${outsideCount} outside`)}
                </span>
              )}
              {summary.count > 0 && clearChip('map-peek-clear')}
            </div>
            <div data-hscroll="true" data-testid="map-peek-strip" className="bb-noscroll"
              style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '0 16px 8px', minHeight: 44, overflowX: 'auto', scrollbarWidth: 'none', flex: 'none' }}>
              {/* Search: lifts the sheet to full height (the keyboard covers the lower half) and focuses the box in
                  this same tap, so iOS Safari raises the keyboard (see setSearchInputRef). */}
              <button type="button" onClick={openSearch} data-testid="map-peek-search" aria-label={T('Tìm kiếm', 'Search')}
                style={{ flex: 'none', width: 40, height: 40, borderRadius: 20, border: 'none', background: ink, color: paper, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
                <svg aria-hidden="true" width={17} height={17} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></svg>
              </button>
              {quickChips('map-peek-chip', true)}
            </div>
          </>
        )}
        {/* Sticky, compact: one line that still says exactly what is filtered (tap = open the search + chips). */}
        {compactHeader && (
          <div style={{ padding: '4px 16px 8px' }}>
            <div data-testid="map-filter-summary" role="button" tabIndex={0} onClick={expandHeader}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); expandHeader(); } }}
              aria-label={T('Mở tìm kiếm và bộ lọc', 'Open search and filters')}
              style={{ background: surface2, borderRadius: 12, display: 'flex', alignItems: 'center', gap: 8, padding: '0 4px 0 12px', minHeight: 44, cursor: 'pointer' }}>
              <svg aria-hidden="true" width={15} height={15} viewBox="0 0 24 24" fill="none" stroke={ink} strokeWidth={2} strokeLinecap="round" style={{ opacity: 0.6, flex: 'none' }}>
                {summary.count ? <path d="M4 6h16M7 12h10M10 18h4" /> : <><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.35-4.35" /></>}
              </svg>
              <span data-testid="map-filter-summary-text" style={{ flex: 1, minWidth: 0, fontSize: 14, fontWeight: summary.count ? 600 : 400, color: summary.count ? ink : ink2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {summary.count ? summaryText : T('Tìm tên, loại, khu vực, thành phố…', 'Search name, type, area, city…')}
              </span>
              {summary.count > 0 && (
                <span data-testid="map-filter-summary-count" aria-label={T(`${summary.count} bộ lọc`, `${summary.count} filters`)}
                  style={{ flex: 'none', minWidth: 22, height: 22, padding: '0 7px', boxSizing: 'border-box', borderRadius: 11, background: ink, color: paper, fontSize: 12, fontWeight: 700, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontVariantNumeric: 'tabular-nums' }}>
                  {summary.count}
                </span>
              )}
              {summary.count > 0 && clearChip('map-filter-summary-clear')}
            </div>
          </div>
        )}
        {/* Home quick event search (2026-09-27) — a plain text filter,
            ANDed with the category/open-now/nearby controls below;
            reuses this screen's own existing list/filter/event-detail
            routing rather than a second search surface. Autofocused on
            arrival from Home's search button (see the mount effect
            above). */}
        {/* Map v6 (note 74): the input stays MOUNTED at every snap (collapsed to an invisible 1px box at peek and
            behind the folded summary, never display:none / visibility:hidden), so the peek search button can focus
            it synchronously inside its own tap — iOS Safari only raises the keyboard for a focus() in the gesture. */}
        {/* No safe-area-top padding here: this is a bottom sheet (it added ~47px on a real iPhone). */}
        <div data-testid="map-search-box" data-collapsed={searchCollapsed ? 'true' : undefined}
          style={searchCollapsed
            ? { position: 'absolute', top: 0, left: 0, width: 1, height: 1, overflow: 'hidden', opacity: 0, pointerEvents: 'none' }
            : { padding: '4px 16px 8px', display: 'flex', alignItems: 'center', gap: 4 }}>
          {/* Full height covers the map, so its controls sit either side of a narrower field: back (left) and
              "Show map" (right, drops the sheet to mid), which also says this list sits over a map. */}
          {!searchActive && (
            <button type="button" onClick={closeMap} tabIndex={sideP > 0.5 ? 0 : -1} aria-hidden={sideP > 0.5 ? undefined : true} data-testid="map-sheet-back" aria-label={T('Đóng bản đồ', 'Close map')} style={sideBtn}>
              <svg aria-hidden="true" width={17} height={17} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round"><path d="M19 12H5M11 6l-6 6 6 6" /></svg>
            </button>
          )}
          <div className="bb-focus-ring" style={{ flex: 1, minWidth: 0, background: surface2, borderRadius: 12, display: 'flex', alignItems: 'center', gap: 8, padding: '0 12px', minHeight: 44 }}>
            <svg width={15} height={15} viewBox="0 0 24 24" fill="none" stroke={ink} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.55, flex: 'none' }}>
              <circle cx="11" cy="11" r="7" />
              <path d="M21 21l-4.35-4.35" />
            </svg>
            <input
              ref={setSearchInputRef}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              onFocus={onSearchFocus}
              onBlur={onSearchBlur}
              onKeyDown={(e) => { if (e.key === 'Enter' && searchQuery.trim()) { rememberSearch(searchQuery); e.currentTarget.blur(); } }}
              tabIndex={searchCollapsed ? -1 : 0}
              enterKeyHint="search"
              // The matcher covers name, category, area, host and description (src/lib/search.js), not just names.
              placeholder={T('Tìm tên, loại, khu vực, thành phố…', 'Search name, type, area, city…')}
              aria-label={T('Tìm sự kiện trên bản đồ', 'Search events on the map')}
              data-testid="map-search-input" data-bare
              style={{ flex: 1, minWidth: 0, border: 'none', outline: 'none', background: 'transparent', fontSize: 15, color: ink, fontFamily: "'Be Vietnam Pro', sans-serif" }}
            />
            {searchQuery && (
              <button type="button" onMouseDown={(e) => e.preventDefault()} onClick={() => setSearchQuery('')} data-testid="map-search-clear" aria-label={T('Xoá tìm kiếm', 'Clear search')}
                style={{ width: 44, height: 44, marginInlineEnd: -12, border: 'none', background: 'none', cursor: 'pointer', color: ink2, fontSize: 18, lineHeight: 1, flex: 'none' }}>×</button>
            )}
          </div>
          {/* Cancel = keyboard down + the sheet back where the search was opened from. mousedown is kept from
              blurring the input first (which would unmount this button before its click). */}
          {searchActive && (
            <button type="button" onMouseDown={(e) => e.preventDefault()} onClick={cancelSearch} data-testid="map-search-cancel"
              style={{ flex: 'none', minHeight: 44, padding: '0 6px 0 10px', border: 'none', background: 'none', color: clay, fontSize: 14.5, fontWeight: 600, cursor: 'pointer', fontFamily: 'inherit' }}>
              {T('Huỷ', 'Cancel')}
            </button>
          )}
          {!searchActive && (
            // Same control as the compass over the map (owner 2026-11-01): centre on me, with the map shown.
            <button type="button" onClick={() => { setSheetSnap('mid'); recenterOnUser(); }} tabIndex={sideP > 0.5 ? 0 : -1} aria-hidden={sideP > 0.5 ? undefined : true} data-testid="map-sheet-locate" aria-label={T('Vị trí của tôi', 'My location')} style={{ ...sideBtn, fontSize: 17, opacity: sideP * compassOpacity }}>
              🧭
            </button>
          )}
        </div>
        {!searchCollapsed && !suggestOpen && (<>
        {/* Categories: Home's own definitions (src/data/eventTypeProfiles.json) and line icons, in a fixed order
            so the row never reshuffles as results change. Each count is what tapping it would show with every
            other filter kept; a selected category stays even at 0. "All categories" opens Home's A–Z sheet. */}
        <div ref={catRowRef} data-hscroll="true" data-testid="map-category-row" role="tablist" aria-label={T('Danh mục', 'Categories')} className="bb-noscroll"
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
                // "All" first, then the picked category, then the rest (owner 2026-11-01).
                style={{ ...catChip(active, n === 0 && !active), order: c.key === 'all' ? -2 : active ? -1 : 0 }}
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
        <div ref={chipRowRef} data-hscroll="true" data-testid="map-filter-extra-scroller" className="bb-noscroll" style={{ flex: '1 1 0', minWidth: 0, display: 'flex', gap: 8, paddingInlineEnd: 16, overflowX: 'auto', scrollbarWidth: 'none' }}>
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
            {areaContext === 'area' && cityDest ? cityName(cityDest) : areaContext === 'area' && curArea.key !== 'all' ? curArea.label : T('Vùng bản đồ', 'Map area')} ▾
          </button>
          {/* Time quick chips apply at once, judged in each event's own venue time zone (homeDiscovery). */}
          {[['tonight', 'Tối nay', 'Tonight'], ['weekend', 'Cuối tuần', 'Weekend']].map(([opt, vi, en]) => (
            <button key={opt} type="button" aria-pressed={filters.date === opt} onClick={() => toggleDate(opt)}
              data-testid={`map-chip-${opt}`} style={{ ...catChip(filters.date === opt, false), order: filters.date === opt ? -1 : 0 }}>
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
              style={{ ...catChip(openNowOnly, false), order: openNowOnly ? -1 : 0 }}
            >
              {T('Còn chỗ', 'Seats left')}
            </button>
          )}
          {/* Everything else (any date, price per ticket, almost full, type chips) in Home's sheet, as a draft. */}
          <button type="button" onClick={() => setFilterSheetOpen(true)} data-testid="map-chip-filters" aria-haspopup="dialog"
            style={{ ...catChip(sheetFilterCount > 0, false), order: sheetFilterCount > 0 ? -1 : 0 }}>
            <svg aria-hidden="true" width={15} height={15} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round"><path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0" /><circle cx="16" cy="6" r="2" /><circle cx="10" cy="12" r="2" /><circle cx="18" cy="18" r="2" /></svg>
            {T('Bộ lọc', 'Filters')}{sheetFilterCount > 0 ? ` · ${sheetFilterCount}` : ''}
          </button>
        </div>
        </div>
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
        </>)}
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

        {/* Status notices (only when there is something to say): updating, a failed refresh, an incomplete set. */}
        {sheetSnap !== 'peek' && !suggestOpen && ((refreshing && events.length > 0) || (loadError && events.length > 0) || !dataMeta.complete || (outsideCount > 0 && visibleEvents.length > 0)) && (
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

        {/* Full height (iOS parity): the city the map is on, then the count + Large / Compact, under the filters. */}
        {sheetSnap === 'tall' && !suggestOpen && (
          <div data-testid="map-full-count" style={{ padding: '2px 16px 6px', flex: 'none' }}>
            {mapCity && (
              <div data-testid="map-sheet-city" style={{ fontSize: 11.5, fontWeight: 700, letterSpacing: 0.8, textTransform: 'uppercase', color: clay, display: 'flex', alignItems: 'center', gap: 4, paddingTop: 4 }}>
                <svg aria-hidden="true" width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round"><path d="M12 21s-6-5.3-6-10a6 6 0 0 1 12 0c0 4.7-6 10-6 10z" /><circle cx="12" cy="11" r="2" /></svg>
                {mapCity}
              </div>
            )}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, paddingTop: 6 }}>
              <span aria-live="polite" style={{ flex: 1, minWidth: 0, fontSize: 17, fontWeight: 600, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {committedBounds && !(loading && !events.length)
                  ? T(`${visibleEvents.length} sự kiện trong vùng bản đồ`, `${visibleEvents.length} event${visibleEvents.length === 1 ? '' : 's'} in this map area`)
                  : T('Đang tải sự kiện…', 'Loading events…')}
              </span>
              {layoutSwitch}
            </div>
          </div>
        )}
        <div
          ref={listRef}
          data-testid="map-list-scroll"
          // The dock is only there at tall (Map v5); below it the list just keeps a small bottom margin.
          // At rest at peek only the strip shows (no half-cut row under it); dragging up reveals the list again.
          aria-hidden={sheetSnap === 'peek' && dragOffsetVh === 0 ? true : undefined}
          style={{ flex: 1, overflowY: 'auto', padding: `0 16px calc(${dockShown(sheetSnap) ? dockClear + 16 + (sheetSnap === 'tall' ? 72 : 0) : 24}px + env(safe-area-inset-bottom, 0px))`, position: 'relative', touchAction: 'pan-y', overscrollBehavior: 'contain', opacity: sheetSnap === 'peek' && dragOffsetVh === 0 ? 0 : 1, transition: 'opacity 0.2s ease' }}
          onScroll={onListScroll}
        >
          {/* Map v6 (note 74): the search is focused and empty — offer something instead of a blank list. */}
          {suggestOpen ? searchPanel : (<>
          {/* Map v5 (note 73): the selected event is the first item of the list (no floating card over the map):
              photo, venue time, price + seats, then Directions · View details · Share. ‹ 1/3 › steps through a
              same-place stack; × clears the selection. */}
          {selectedEvent && (
            <div data-testid="map-selected-row" style={{ margin: '8px 0 4px', padding: 12, borderRadius: 16, background: surface2, border: `1.5px solid ${ink}`, display: 'flex', flexDirection: 'column', gap: 12 }}>
              <div onClick={() => selectEvent(selectedEvent)} data-testid="map-card-recenter" style={{ display: 'flex', gap: 12, cursor: 'pointer' }}>
                {selectedEvent.img && (
                  <div data-testid="map-card-photo" style={{ backgroundImage: `url(${selectedEvent.img})`, backgroundSize: 'cover', backgroundPosition: 'center', width: 80, height: 80, borderRadius: 12, flexShrink: 0 }} />
                )}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 }}>
                    <div data-testid="map-card-title" style={{ fontSize: 16, fontWeight: 700, color: ink, lineHeight: 1.25, flex: 1, minWidth: 0, overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>{selectedEvent.name}</div>
                    {/* Several events at this same place: step through them here (zooming can never split a stack). */}
                    {selectedStack.length > 1 && (() => {
                      const i = selectedStack.findIndex(e => e.id === selectedEvent.id);
                      const go = (d) => (e) => { e.stopPropagation(); setSelectedId(selectedStack[(i + d + selectedStack.length) % selectedStack.length].id); };
                      const arrow = { width: 44, height: 44, margin: '-12px 0', border: 'none', background: 'none', color: ink, fontSize: 18, cursor: 'pointer', fontFamily: 'inherit' };
                      return (
                        <span data-testid="map-card-stack" style={{ display: 'inline-flex', alignItems: 'center', flex: 'none', fontSize: 12.5, color: ink2 }}>
                          <button type="button" onClick={go(-1)} aria-label={T('Sự kiện trước ở đây', 'Previous event here')} data-testid="map-card-stack-prev" style={arrow}>‹</button>
                          <span aria-live="polite">{i + 1}/{selectedStack.length}</span>
                          <button type="button" onClick={go(1)} aria-label={T('Sự kiện tiếp theo ở đây', 'Next event here')} data-testid="map-card-stack-next" style={arrow}>›</button>
                        </span>
                      );
                    })()}
                    <button
                      type="button"
                      onClick={(e) => { e.stopPropagation(); clearSelection(); }}
                      data-testid="map-card-close"
                      aria-label={T('Bỏ chọn', 'Clear selection')}
                      style={{ width: 44, height: 44, margin: '-12px -12px -12px 0', border: 'none', background: 'none', cursor: 'pointer', color: ink2, fontSize: 20, lineHeight: 1, flex: 'none' }}
                    >×</button>
                  </div>
                  <div data-testid="map-card-when" style={{ fontSize: 13, color: ink2, marginTop: 4, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {[eventWhen(selectedEvent), selectedEvent.area].filter(Boolean).join(' · ')}
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 6, flexWrap: 'wrap' }}>
                    <span data-testid="map-card-price" style={{ fontSize: 14, color: ink, fontWeight: 600 }}>{priceLine(selectedEvent)}</span>
                    <SeatPill ev={selectedEvent} testId="map-card-seats" />
                  </div>
                </div>
              </div>
              <div style={{ display: 'flex', gap: 8 }}>
                {/* Directions: the same public venue link Event Detail shows (mapsUrl); only with a map location. */}
                {mapsUrl(selectedEvent) && (
                  <a
                    href={mapsUrl(selectedEvent)}
                    target="_blank"
                    rel="noopener noreferrer"
                    data-testid="map-card-directions"
                    style={{ flex: '0 0 auto', minHeight: 44, padding: '0 14px', borderRadius: 999, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6, background: clayBg, color: clay, fontSize: 13.5, fontWeight: 600, textDecoration: 'none' }}
                  >
                    <svg aria-hidden="true" width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d="M3 11l18-8-8 18-2-8-8-2z" /></svg>
                    {T('Chỉ đường', 'Directions')}
                  </a>
                )}
                <button
                  type="button"
                  onClick={() => openEventDetail(selectedEvent.id)}
                  data-testid="map-card-cta"
                  style={{ ...inkButton({ borderRadius: 999 }), flex: 1, minHeight: 44, padding: '0 12px', fontSize: 13.5, border: 'none', fontFamily: 'inherit', cursor: 'pointer' }}
                >
                  {T('Xem chi tiết', 'View details')}
                </button>
                {/* Share: the same link and preview Event Detail shares (BanBeContext shareEvent). */}
                <button
                  type="button"
                  onClick={() => shareEvent({ key: selectedEvent.id, name: selectedEvent.name, where: selectedEvent.area || '' })}
                  data-testid="map-card-share"
                  aria-label={T('Chia sẻ sự kiện', 'Share event')}
                  style={{ flex: 'none', width: 44, height: 44, borderRadius: 999, border: 'none', background: paper, color: ink, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}
                >
                  <svg aria-hidden="true" width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d="M12 3v12M7 8l5-5 5 5M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6" /></svg>
                </button>
              </div>
            </div>
          )}
          {selectedEvent && visibleEvents.some(e => e.id !== selectedEvent.id) && (
            <div data-testid="map-selected-more" style={{ padding: '8px 0 0', fontSize: 12.5, fontWeight: 600, color: ink2 }}>
              {(() => {
                const n = visibleEvents.filter(e => e.id !== selectedEvent.id).length;
                return T(`${n} sự kiện khác trong vùng bản đồ này`, `${n} more in this map area`);
              })()}
            </div>
          )}
          {/* Map v5 (note 73): cities matching the search, first ("Đà Lạt · 2 events" → Go), even with no events. */}
          {cityMatches.length > 0 && (
            <div data-testid="map-city-results">
              <div style={sectionLabel}>{T('Thành phố', 'Cities')}</div>
              {cityMatches.map(({ id, count }) => (
                <button key={id} type="button" onClick={() => goCity(id)} data-testid={`map-city-row-${id}`}
                  style={{ display: 'flex', width: '100%', alignItems: 'center', gap: 12, padding: '10px 0', minHeight: 56, border: 'none', borderBottom: `1px solid ${rule}`, background: 'none', color: ink, textAlign: 'left', cursor: 'pointer', fontFamily: 'inherit' }}>
                  <span aria-hidden="true" style={{ width: 36, height: 36, borderRadius: 18, background: clayBg, color: clay, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>
                    <svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinejoin="round"><path d="M12 21s7-6.2 7-11.5A7 7 0 0 0 5 9.5C5 14.8 12 21 12 21Z" /><circle cx="12" cy="9.5" r="2.5" /></svg>
                  </span>
                  <span style={{ flex: 1, minWidth: 0 }}>
                    <span style={{ display: 'block', fontSize: 15, fontWeight: 600 }}>{cityName(id)}</span>
                    <span style={{ display: 'block', fontSize: 13, color: ink2 }}>
                      {count ? T(`${count} sự kiện`, `${count} event${count === 1 ? '' : 's'}`) : T('Chưa có sự kiện · vẫn có thể đến', 'No events yet · you can still go')}
                    </span>
                  </span>
                  <span style={{ flex: 'none', color: clay, fontSize: 14, fontWeight: 600 }}>{T('Đến', 'Go')}</span>
                </button>
              ))}
              {visibleEvents.length > 0 && <div style={sectionLabel}>{T('Sự kiện', 'Events')}</div>}
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
            cityMatches.length > 0 ? null : anyInArea && filtersActive ? (
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
                {/* Filters on and nothing here: offer to clear them (owner 2026-11-01), never a dead end. */}
                {(filtersActive || catFilter !== 'all') && (
                  <button type="button" onClick={clearFilters} data-testid="map-clear-filters-empty" style={emptyAction}>
                    {T(`Xoá ${summary.count} bộ lọc`, summary.count === 1 ? 'Clear 1 filter' : `Clear ${summary.count} filters`)}
                  </button>
                )}
              </div>
            )
          )}
          {/* The results, then (apart, never counted as "in this area") matching events with no map location. */}
          {/* The selected event is shown once, at the top; the list continues with the others. */}
          {(() => {
            const notSel = (e) => e.id !== selectedEvent?.id;
            const main = visibleEvents.filter(notSel);
            // Map v6 (note 74): at full height, Large = Home's photo card with the photo pager (tap = select).
            const large = sheetSnap === 'tall' && listLayout === 'large';
            return [...main, ...noLocationMatches.filter(notSel)].map((ev, i) => (
            <Fragment key={ev.id}>
            {i === main.length && (
              <div data-testid="map-no-location-heading" style={{ padding: '16px 0 4px', fontSize: 13, fontWeight: 600, color: ink2 }}>
                {T(`Chưa có vị trí trên bản đồ (${noLocationMatches.length})`, `No map location yet (${noLocationMatches.length})`)}
              </div>
            )}
            {large ? (
              <div style={{ paddingTop: i === 0 ? 8 : 0 }}>
                <DiscoveryCard ev={largeCard(ev)} onOpen={() => selectEvent(ev)} onToggleSave={() => toggleFav(ev.id)} T={T}
                  testId={`map-list-item-${ev.id}`} role="button" gutter={0} current={ev.id === selectedId} />
              </div>
            ) : (
            <div
              onClick={() => selectEvent(ev)}
              data-testid={`map-list-item-${ev.id}`}
              role="button"
              tabIndex={0}
              aria-current={ev.id === selectedId ? 'true' : undefined}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); selectEvent(ev); } }}
              // Mid = cards (photo + three lines); tall = a denser list (small photo, two lines).
              style={{ display: 'flex', gap: 12, padding: '7px 0', cursor: 'pointer', alignItems: dense ? 'center' : 'flex-start', animation: 'banbeRowIn 0.3s cubic-bezier(.22,.61,.36,1) backwards', background: ev.id === selectedId ? 'rgba(var(--bb-fg-rgb),0.05)' : 'transparent' }}
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
                <div data-testid={`map-list-item-price-${ev.id}`} aria-label={priceLine(ev)} style={{ fontSize: 14, fontWeight: 600, color: ink, whiteSpace: 'nowrap', display: 'inline-flex', alignItems: 'center', gap: 4 }}>{priceTicket(ev)}</div>
                <SeatPill ev={ev} testId={`map-list-item-seats-${ev.id}`} />
              </div>
            </div>
            )}
            </Fragment>
            ));
          })()}
          </>)}
        </div>
      </div>
    </div>
  );
}

function boundsToBox(bounds) {
  return { north: bounds.getNorth(), south: bounds.getSouth(), east: bounds.getEast(), west: bounds.getWest() };
}
