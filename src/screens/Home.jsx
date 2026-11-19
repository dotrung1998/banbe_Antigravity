import { glassCapsuleInactive } from '../lib/glassOpacity.js';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { EVENTS, bg, agoLabel, haversineKm, catalogStartMs, mapsUrl } from '../data/events.js';
import { formatCountdown, msUntil, pickSoonest, useTicking, liveEventOverrides, formatVnEventDate } from '../lib/countdown.js';
import { prefsIsEmpty, declaredGoals } from '../lib/eventPrefs.js';
import { intentTitle, isEventLocalDay } from '../lib/coreLoops.js';
import { flagOn } from '../lib/featureFlags.js';
import { profileFor, homeFilters as homeTypeFilters, cardLine, TYPE_KEYS, categoryDefs, secondCategory } from '../lib/eventTypes.js';
import { isBookingTicket } from '../lib/bookingTicket.js';
import { forYouRankEvents } from '../lib/forYou.js';
import { forYouEventVersion } from '../lib/forYouAlert.js';
import { useForYouAlert } from '../lib/useForYouAlert.js';
import ForYouChip from './ForYouChip.jsx';
import { reminderPhase, reminderRank } from '../lib/eventReminder.js';
import { compactCoins, shortcutLabels, capsuleStreak } from '../lib/rewards.js';
import { HEADER, hitSlop } from '../lib/homeHeaderLayout.js';
import DockHeaderTitle, { DOCK_HEADER } from '../components/ui/DockHeaderTitle.jsx';
import HomeModeSwitch from '../components/home/HomeModeSwitch.jsx';
import HostHome from '../components/home/HostHome.jsx';
import { effectiveHomeView } from '../lib/homeMode.js';
import { pickGoerHero } from '../lib/homeHero.js';
import { checklistVisible } from '../lib/activationChecklist.js';
import { tickerItems } from '../lib/pulseTicker.js';

// Header fit order (iOS note 45): wordmark steps down before the title goes; 96 matches every other screen.
const HEADER_FIT_STEPS = [
  { wordmark: 96, showTitle: true }, { wordmark: 80, showTitle: true }, { wordmark: 70, showTitle: true },
  { wordmark: 96, showTitle: false }, { wordmark: 80, showTitle: false }, { wordmark: 70, showTitle: false },
  { wordmark: 0, showTitle: false },
];
import { paper, ink, rule, display, fieldGlass, CHIP_COLORS, photoChip, lightChip, alert, cardGlass, barGlass } from '../theme.js';
import { BAR_HEIGHT, BAR_BOTTOM_OFFSET, DOCK_MARGIN } from './BottomTabBar.jsx';
import { buildActionCenterItems, sortActionCenterItems } from '../lib/actionCenter.js';
import { formatMoney, cardDateBadge } from '../lib/eventMarket.js';
import ActionCenter from './ActionCenter.jsx';
import ActivationChecklistCard from './ActivationChecklistCard.jsx';
import { GuestBrowseBanner } from './GuestPromptSheet.jsx';
import EmptyState from '../components/ui/EmptyState.jsx';
import { CategoryRow, CategorySheet, HomeSearchBar, DiscoveryCard, DiscoveryRow, NextUpBanner } from '../components/home/HomeDiscoveryParts.jsx';
import ShortlistV23, { TAB_LABEL } from '../components/home/ShortlistV23.jsx';
import Browse from './Browse.jsx';
import LiveLine from '../components/home/LiveLine.jsx';
import LiveNowSheet from './sheets/LiveNowSheet.jsx';
import { liveUpdates } from '../lib/liveLine.js';
import { useReducedMotion } from '../lib/useReducedMotion.js';
import { browseFilters as toBrowseFilters, typeCounts as browseTypeCounts } from '../lib/browse.js';
import HomeShellV5 from '../components/home/HomeShellV5.jsx';
import { UnifiedStateBar, UnifiedTypeGrid, UnifiedTypeSheet, UnifiedMapBanner } from '../components/home/UnifiedHomeParts.jsx';
import { DATE_FOR_TAB, tabForDate, ownedFilterCount } from '../lib/unifiedDiscovery.js';
import { buildEventSearchDoc, matchesSearchQuery } from '../lib/search.js';
import { searchBarStore } from '../lib/searchBarStore.js';
import QuickSheetV5 from '../components/home/QuickSheetV5.jsx';
// Map v6 (note 74): the card pager's photos (cover first, max 6).
import { cardPhotoList } from '../lib/eventPhotoUrls.js';
import HomeFilterSheet, { DATE_LABELS, RELAX_LABELS, SORT_LABELS } from './sheets/HomeFilterSheet.jsx';
import SortMenu from './sheets/SortMenu.jsx';
import PulseTicker from '../components/home/PulseTicker.jsx';
import { setBellOrigin } from '../lib/bellOrigin.js';
import { supabase } from '../lib/supabase.js';
import { savedComingUp, fillText, whenLabel } from '../lib/quickWins.js';
import { rowTimeZone, wallClockToMs } from '../lib/eventMarket.js';
import NextUpV23 from '../components/home/NextUpV23.jsx';
import { nextUpGroups, nextUpStatus, nextUpChip, peopleLine, dateBadge } from '../lib/nextUp.js';
import { endsNextDay, isEventOver } from '../lib/eventEnd.js';
import {
  applyDiscoveryFilters, sortEvents, fillBadge, activeFilterCount, optionCounts, relaxationHints, DEFAULT_FILTERS,
  categoryCounts, categoryRowKeys, categorySheetKeys,
} from '../lib/homeDiscovery.js';

// Quick chips (note 50): one-tap shortcuts into the same filters the filter sheet edits (src/lib/homeDiscovery.js).
// The old status chips (Saved / Attending / Not confirmed / Sold out) left Home: they filter YOUR events, which
// live in Schedule and Account > Saved/Going, not discovery. A chip that would return 0 events is hidden.
const QUICK_CHIPS = [
  { key: 'today', vi: 'Hôm nay', en: 'Today', apply: f => ({ ...f, date: f.date === 'today' ? 'any' : 'today' }), on: f => f.date === 'today', dim: 'date' },
  { key: 'weekend', vi: 'Cuối tuần này', en: 'This weekend', apply: f => ({ ...f, date: f.date === 'weekend' ? 'any' : 'weekend' }), on: f => f.date === 'weekend', dim: 'date' },
  { key: 'free', vi: 'Miễn phí', en: 'Free', apply: f => ({ ...f, free: !f.free, priceMin: null, priceMax: null }), on: f => f.free, dim: 'free' },
  { key: 'seatsLeft', vi: 'Còn chỗ', en: 'Seats left', apply: f => ({ ...f, seatsLeft: !f.seatsLeft }), on: f => f.seatsLeft, dim: 'seatsLeft' },
  { key: 'almostFull', vi: 'Sắp hết chỗ', en: 'Almost full', apply: f => ({ ...f, almostFull: !f.almostFull }), on: f => f.almostFull, dim: 'almostFull' },
];
const LAYOUT_KEY = 'banbe_home_layout_v1';
const readLayout = () => { try { return localStorage.getItem(LAYOUT_KEY) === 'list' ? 'list' : 'cards'; } catch { return 'cards'; } };
const ENDED_AFTER_MS = 12 * 3600000;

// iOS HomeView.homeGlassCapsule parity: translucent ink-tinted fill, 1px
// hairline, soft shadow, 999px radius, fixed 36px height.
// One heading size for every Home section ("Your events", "Help Shape…", "This weekend"), in the same display
// face as the screen titles ("Schedule", "Account"…), so the headings read as one family.
const SECTION_TITLE = 20;

// Plain-text quick controls beside the location pill (note 50): no capsule, icon + label, 44px-tall tap area.
const quickToggle = {
  display: 'inline-flex', alignItems: 'center', gap: 5, minHeight: 32, padding: 0, border: 'none', background: 'none',
  color: ink, fontFamily: 'inherit', fontSize: 13.5, fontWeight: 600, cursor: 'pointer', flex: 'none', whiteSpace: 'nowrap',
};

function homeCapsule(extra, active = false) {
  return {
    // minHeight, not height: with a larger browser text size the label grows and the capsule grows with it.
    display: 'inline-flex', alignItems: 'center', minHeight: 36, boxSizing: 'border-box', padding: '0 14px',
    borderRadius: 999, fontSize: 14, whiteSpace: 'nowrap', cursor: 'pointer', flex: 'none', userSelect: 'none',
    color: active ? 'var(--bb-bg)' : ink,
    ...(active
      ? { background: 'rgba(var(--bb-fg-rgb), 0.92)', border: '1px solid transparent', boxShadow: '0 2px 6px rgba(27,25,22,0.18)', backdropFilter: 'blur(14px) saturate(1.1)', WebkitBackdropFilter: 'blur(14px) saturate(1.1)' }
      : glassCapsuleInactive),
    ...extra,
  };
}

export const FILTER_DEFS = [
  { key: 'all', vi: 'Tất cả', en: 'All' },
  { key: 'supper', vi: 'Supper club', en: 'Supper club' },
  { key: 'fashion', vi: 'Thời trang', en: 'Fashion' },
  { key: 'gallery', vi: 'Phòng tranh', en: 'Gallery' },
  { key: 'music', vi: 'Nhạc', en: 'Music' },
];


const TYPE_DEF_BY_KEY = new Map(categoryDefs().map(d => [d.key, d]));

// v2.3 Browse by type / See all (note 81): its own screen ('browse', /browse and /see-all/<tab>), built by Home so the
// list reads the very same discovery items, tabs and filters as Home (no second filter path, note 50).
export function BrowseScreen() { return <Home browse />; }

export default function Home({ browse = false }) {
  const {
    state, set, T, trStatus, stripKm, curArea, pickArea, isSaved, isGoing, toggleFav,
    goEvent, pickFilter, clearFilters, toggleHomeFilter, goMapExplore, toggleLang, toggleTheme, setHomeView, startHosting,
    becomeHost, switchToHost,
    canHost, loadPaymentBookings, loadVerifications, loadOrganizerHoldingSummary, loadHomeLiveEvents,
    openPaymentDetails, openVerifications, goDashboard, forfeitExpiredHold,
    loadHomeStories, openStoryViewer, openSurveyStoryModal,
    loadMyRefunds, openMyRefunds, loadRefundQueue, goNotifications,
    loadMyAdminInvite, openAccountGroup,
    openPulseViewer, loadWeekendEvents, loadDiscoveryEvents, loadRealEventsById, loadPulse,
    loadHomeSurveyDiscovery, loadMoreHomeSurveyDiscovery, openEventPreferences,
    openSearch, setHomeFilters, located, allowLocation, rewardsEnabled, rewardsV2Enabled, openBookingConfirmed,
    resolvedTheme, openBrowse, setBrowse, backFromBrowse, openOrganizerProfile, goSchedule, goProfile,
  } = useBanBe();

  const s = state;
  const hasHosted = s.hasHosted;
  // Simple Shell (switch simple_shell, note 66): Going out | Hosting in the header, one hero, one chip row, location in
  // the search bar, map as a Home view. Off = this screen exactly as before.
  const simpleShell = flagOn(s.featureFlags, 'simple_shell');
  // v2.3 (note 81, switch home_v23, on top of simple_shell): paged Shortlist, rail of 4 + See all, Browse by type.
  const v23 = simpleShell && flagOn(s.featureFlags, 'home_v23');
  // Note 99 (migration 221): Home and Map share ONE search, type, time, price and sort. The tabs are the shared time
  // (homeFilters.date), the shared query (s.searchQuery) narrows Home too, Browse by type filters in place.
  const ud = v23 && flagOn(s.featureFlags, 'unified_discovery');
  // Calm Pass phase 3 (migration 208, note 71): Home event cards as polaroids. Cards view only; the list is unchanged.
  const polaroidCards = flagOn(s.featureFlags, 'polaroid_cards');
  // Follow-up (note 66): the Hosting view is `homeView` (session-only), shown only while organizer mode is on
  // (src/lib/homeMode.js). Organizer mode off is always Going out, whatever the restored or deep-linked state.
  const hostView = simpleShell && effectiveHomeView(s.organizerMode, s.homeView) === 'host';
  // Compact-vertical-list pass — see iOS HomeView.swift's
  // `visibleSurveyDiscoveryCount` for the full reasoning: deliberately
  // SEPARATE from both `s.homeSurveyDiscovery.length` and
  // `s.homeSurveyDiscoveryHasMore` (the real "more exist on the server"
  // signal) so a preview-row cap is never confused with the true total.
  const [visibleSurveyDiscoveryCount, setVisibleSurveyDiscoveryCount] = useState(3);
  // Reset-on-account-change — this component can stay mounted across a
  // sign-out/sign-in within the same session, so a new account must not
  // inherit a previous account's "already revealed 23 rows" state.
  useEffect(() => { setVisibleSurveyDiscoveryCount(3); }, [s.user?.id]);
  const revealMoreSurveyDiscovery = async () => {
    // Reveals already-loaded rows first (no network call); once that's
    // exhausted, fetches a real next page. Either way, +10 — a functional
    // update, not a read of this render's own (by-then-stale) `s` snapshot.
    if (visibleSurveyDiscoveryCount >= s.homeSurveyDiscovery.length) {
      await loadMoreHomeSurveyDiscovery();
    }
    setVisibleSurveyDiscoveryCount(n => n + 10);
  };

  const openSaved = (sv) => (sv.toEvent === 'event' ? goEvent(sv.key) : set({ screen: sv.toEvent, eventKey: sv.key }));
  const heldEv = s.holdDeadline && s.holdDeadline > s.now ? EVENTS.find(e => e.key === s.eventKey) : null;

  // Both phases, both roles: what this account is waiting on right now, as
  // a participant (their own bookings) and — separately — as the organizer
  // of events other people are booking. Loaded once signed in, refreshed
  // each time Home mounts (a hold or a verification can settle anywhere:
  // another tab or device, the bank webhook).
  // v2.3 Next up (note 81): booked events Home has not loaded yet (photo, venue zone, end time, map pin).
  useEffect(() => {
    if (!v23 || !s.user?.id) return;
    const missing = [...new Set((s.paymentBookings || []).map(b => b.event_id).filter(id => id && !(id in s.realEventsById)))];
    if (missing.length) loadRealEventsById(missing);
  }, [v23, s.user?.id, s.paymentBookings]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!s.user?.id) return;
    loadPaymentBookings();
    loadMyRefunds();
    if (canHost) {
      loadVerifications();
      loadOrganizerHoldingSummary();
      loadRefundQueue();
    }
  }, [s.user?.id, canHost, loadPaymentBookings, loadVerifications, loadOrganizerHoldingSummary, loadMyRefunds, loadRefundQueue]);

  // 2026-09-21 follow-up — real (not baked-in) ended/cancelled status for
  // every catalogue event Home might show, public info so this runs for
  // every visitor (see BanBeContext.jsx's own comment on loadHomeLiveEvents).
  useEffect(() => { loadHomeLiveEvents(); }, [loadHomeLiveEvents]);
  // Discovery-bug fix — fires on every Home mount, same as every other
  // real-events loader on this screen (App.jsx's Shell remounts the whole
  // screen component on a `screen` change, so navigating away and back
  // already re-fires this — a fresh admin approval is visible the very
  // next time this screen mounts, with no separate "refresh" affordance
  // needed).
  useEffect(() => { loadDiscoveryEvents(); }, [loadDiscoveryEvents]);
  // Retention roadmap P1 — "Cuối tuần này". Public info, same as
  // loadHomeLiveEvents above (runs for every visitor); re-fires on sign-in/
  // out too, since loadWeekendEvents' own followed-host sort depends on
  // `s.user` and is part of that function's dependency list.
  useEffect(() => { loadWeekendEvents(); }, [loadWeekendEvents]);
  // Banbe Pulse ticker + the Popular sort both read the daily ranking (public, so guests too).
  useEffect(() => { loadPulse('daily'); }, [loadPulse]);
  // Task 3.3 (07-notifications.md) — active stories row.
  useEffect(() => { if (s.user?.id) loadHomeStories(); }, [s.user?.id, loadHomeStories]);
  // The admin invite shows in the Things-to-do list below, so Home loads it itself.
  useEffect(() => { if (s.user?.id) loadMyAdminInvite(); }, [s.user?.id, loadMyAdminInvite]);
  // Source-of-discovery pass — independent of the story ring above; own
  // initial load, own refresh, own pagination state.
  useEffect(() => { if (s.user?.id) loadHomeSurveyDiscovery(); }, [s.user?.id, loadHomeSurveyDiscovery]);
  // Merges a real DB row's live status onto a static catalogue event —
  // same idea as curEvent's own single-event version (BanBeContext.jsx), just
  // applied to every event this screen might list instead of one.
  const withLive = (e) => {
    const overrides = liveEventOverrides(s.homeLiveEvents[e.key], e);
    return overrides ? { ...e, ...overrides } : e;
  };

  const myHolding = pickSoonest(s.paymentBookings, 'holding', 'hold_expires_at');
  const myPendingVerification = (s.paymentBookings || [])
    .filter(b => b.payment_state === 'pending_verification')
    .sort((a, b) => new Date(a.proof_uploaded_at || 0) - new Date(b.proof_uploaded_at || 0))[0] || null;

  const orgPendingCount = (s.verifications || []).length;
  const orgSoonestVerifyDue = (s.verifications || [])
    .map(v => v.verify_due_at).filter(Boolean).sort()[0] || null;
  const orgHolding = s.organizerHoldingSummary;

  // Any of these five countdown-relevant items ticking is reason enough to
  // re-render every second; none of them showing means no clock runs at all.
  const anyCountdownVisible = !!(heldEv || myHolding || myPendingVerification || orgPendingCount || orgHolding);
  const tickNow = useTicking(anyCountdownVisible);

  // TASK A (2026-10-01 UX foundation pass) — replaces the old fixed
  // "always show all four PhaseBanners" block: goer items (this account's
  // own bookings/refunds) always considered, host items only while
  // `canHost`, merged and re-sorted together by buildActionCenterItems()'s
  // shared priority order, capped to 3 + "Xem tất cả" by <ActionCenter>.
  const actionItems = useMemo(() => sortActionCenterItems([
    ...buildActionCenterItems({
      role: 'goer', T, now: tickNow,
      myHolding, myPendingVerification, myRefunds: s.myRefunds || [],
      myAdminInvite: s.myAdminInvite,
      onOpenPayment: (bookingId) => openPaymentDetails(bookingId, 'home'),
      onOpenMyRefunds: () => openMyRefunds('home'),
      onOpenAdminInvite: () => openAccountGroup('adminTeam'),
    }),
    // Simple Shell: host to-dos live on the Hosting Home (HostHome.jsx); Going out shows your own only.
    ...(canHost && !simpleShell ? buildActionCenterItems({
      role: 'host', T, now: tickNow,
      verifications: s.verifications || [], refundQueue: s.refundQueue || [], orgHolding,
      onOpenVerifications: () => openVerifications('home'),
      onOpenRefundCenter: () => openVerifications('home'),
      onOpenDashboard: goDashboard,
    }) : []),
  ]), [T, tickNow, myHolding, myPendingVerification, s.myRefunds, s.myAdminInvite, openAccountGroup, canHost, simpleShell, s.verifications, s.refundQueue, orgHolding, openPaymentDetails, openMyRefunds, openVerifications, goDashboard]);

  // Home is often the screen a buyer is sitting on when a hold's countdown
  // reaches zero — not just the ticket screen. myHolding above already
  // excludes a lapsed row (that's what makes the banner disappear on time),
  // which means it can't be used to notice the transition; this checks the
  // raw list directly so Home can forfeit it the same instant the banner
  // for it vanishes, rather than leaving that to whichever other screen the
  // buyer happens to open next.
  useEffect(() => {
    const justLapsed = (s.paymentBookings || []).find(
      b => b.payment_state === 'holding' && b.hold_expires_at && msUntil(b.hold_expires_at, tickNow) === 0
    );
    if (justLapsed) forfeitExpiredHold(justLapsed);
  }, [s.paymentBookings, tickNow, forfeitExpiredHold]);

  // Discovery-bug fix — every real event (loadDiscoveryEvents above),
  // reshaped to the exact same card fields the static catalogue's own
  // `withLive` output has, so it flows through the SAME filter/sort/map
  // pipeline below (category, area, saved/attending/soldOut/upcoming/ended
  // chips, card markup) with no second, parallel rendering path to drift
  // out of sync with the static one. Deduped against the static catalogue
  // by key (real ids are a slug + random suffix and practically never
  // collide, but a real event is authoritative if they ever did).
  // `liveEventOverrides` is reused here exactly as `withLive` reuses it for
  // a static row — the only difference is there's no static counterpart to
  // merge onto, so it's called with `staticEv: null`.
  const discoveryShaped = useMemo(() => (s.discoveryEvents || [])
    .filter(e => !EVENTS.some(se => se.key === e.key))
    .map(e => {
      // `tz`: dates read in the venue's zone (migration 195).
      const overrides = liveEventOverrides(
        { starts_at: e.startsAt, status: e.status, cancelled_at: e.cancelledAt, tz: e.tz,
          end_time: e.endTime, end_open: e.endOpen }, null
      ) || {};
      const seatsText = e.seatsRemaining != null ? `${e.seatsRemaining} chỗ trống` : '';
      return {
        key: e.key,
        name: e.name,
        img: e.photoUrl,
        // Map v6 (note 74): every public photo for the card pager (cover first, max 6).
        imgs: e.photoUrls || (e.photoUrl ? [e.photoUrl] : []),
        isReal: true,
        catKey: e.catKey,
        // Note 69: the second category (details.cat2, migration 207) also matches Home's category filter.
        cat2Key: secondCategory(e.details, e.catKey),
        // No static "invite-only" demo concept — a real non-public event
        // (draft/review/invite) is excluded from discovery the same honest
        // way the ticket asks for: it just never enters this array at all
        // (the query itself is `visibility='public'`), this flag only
        // covers the theoretical case of a future non-public real row
        // reaching this far.
        inviteOnly: e.visibility !== 'public',
        area: e.area,
        // Location hierarchy (migration 112) — carried through so the
        // shared curArea.match() (src/lib/locationTree.js) can place this
        // card in the same tree node the area sheet shows it under.
        countryCode: e.countryCode, stateProvince: e.stateProvince,
        neighborhood: e.neighborhood, city: e.city,
        meta: `${e.area}${e.area && overrides.when ? ' ▪︎ ' : ''}${overrides.when || ''}`,
        catDisplay: e.catLabel || e.catKey,
        price: e.priceVnd ? formatMoney(e.priceVnd, e.currency) : 'Miễn phí',
        seats: seatsText,
        soldOut: e.soldOut,
        cancelled: overrides.cancelled ?? false,
        cancelledHoursAgo: overrides.cancelledHoursAgo ?? null,
        endedHoursAgo: overrides.endedHoursAgo ?? null,
        until: overrides.until ?? null,
        untilLabel: overrides.untilLabel ?? '',
        agoLabel,
        // Home-visibility fix (2026-09-29) — see `feed`'s own comment below
        // for the full root-cause: kept only to sort real events among
        // THEMSELVES chronologically before merging into the feed, never
        // read past that point.
        startsAtRaw: e.startsAt || null,
        // For You candidates (src/lib/forYou.js) need the raw price: minor units of `currency` (migration 195).
        priceVnd: e.priceVnd || 0, currency: e.currency, tz: e.tz,
        status: e.status,
        // Note 50: Search, the fill badge and the Nearest sort need these; they used to be dropped here.
        // End time (migration 220) feeds the one "is this over" rule (audit 2026-11-19 row 6).
        endTime: e.endTime || null, endOpen: !!e.endOpen,
        keywords: e.keywords || [], organizerName: e.organizerName || '', organizerId: e.organizerId, organizerAvatarUrl: e.organizerAvatarUrl || '',
        capacity: e.capacity ?? null, lat: e.lat, lng: e.lng, description: e.description || '',
      };
    }), [s.discoveryEvents]);

  // "For You" (34-onboarding-for-you-criteria.md): REAL discoverable events only
  // (discoveryShaped never contains the static demo catalogue), under the current
  // area filter. Recomputed when preferences change (eventPrefs is replaced on save).
  const forYouRanked = useMemo(() => {
    if (!s.eventPrefs || prefsIsEmpty(s.eventPrefs)) return [];
    return forYouRankEvents(discoveryShaped.map(withLive).filter(e => curArea.match(e)), s.eventPrefs, true, Date.now());
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [discoveryShaped, s.eventPrefs, s.eventPrefsVersion, curArea, s.homeLiveEvents]);
  const hasForYou = forYouRanked.length > 0;
  const forYouOrder = useMemo(() => new Map(forYouRanked.map((m, i) => [m.key, i])), [forYouRanked]);
  // Refresh discovery when the preferences version changes (not on first mount,
  // Home already loads once).
  const prefsVersionSeen = useRef(s.eventPrefsVersion);
  useEffect(() => {
    if (prefsVersionSeen.current === s.eventPrefsVersion) return;
    prefsVersionSeen.current = s.eventPrefsVersion;
    if (s.eventPrefsVersion > 0) loadDiscoveryEvents();
  }, [s.eventPrefsVersion, loadDiscoveryEvents]);
  // Auto-reset when matches vanish, but never while discovery is still loading.
  useEffect(() => {
    if (s.filterForYou && !hasForYou && !s.discoveryEventsLoading) set({ filterForYou: false });
  }, [s.filterForYou, hasForYou, s.discoveryEventsLoading, set]);
  const forYouActive = s.filterForYou && hasForYou;
  // L6 (switch intent_foryou): title + one "because you said…" line from the FIRST goal the person stated in
  // onboarding. Stated answers only; ranking unchanged. Off = the plain "For You", no line.
  const forYouIntent = flagOn(s.featureFlags, 'intent_foryou') ? intentTitle(declaredGoals(s.eventPrefs)) : null;
  const forYouWhy = forYouIntent?.whyVi ? T(forYouIntent.whyVi, forYouIntent.whyEn) : null;
  // New-match attention state (src/lib/forYouAlert.js). Version = publication
  // moment + status + visibility of the raw discovery row (no updated_at today).
  const forYouAlertMatches = useMemo(() => {
    const raw = new Map((s.discoveryEvents || []).map(e => [e.key, e]));
    return forYouRanked.map(m => {
      const e = raw.get(m.key);
      return { id: m.key, version: forYouEventVersion(e), status: e?.status, accessible: e ? e.visibility === 'public' : false };
    });
  }, [forYouRanked, s.discoveryEvents]);
  const forYouAlert = useForYouAlert({
    userId: s.user?.id, matches: forYouAlertMatches, prefsVersion: s.eventPrefsVersion,
    loading: !!s.discoveryEventsLoading || !s.eventPrefs,
    // Note 64: while the v3 tour shows Home, nothing is observed or saved on the person's behalf.
    passive: !!s.tourActive,
  });

  const demoted = e => (e.cancelled && (e.cancelledHoursAgo == null || e.cancelledHoursAgo >= 2)) ? 1 : 0;
  // Home-visibility fix (2026-09-29) — real root cause of "an approved
  // event doesn't show on Home," CONFIRMED by directly querying the real
  // anon-key Home/Map queries against the live project (not guessed): the
  // event WAS already being returned by `loadDiscoveryEvents()` and WAS
  // already passing every filter below (visibility/category/area all
  // defaulted to "show everything") — RLS, status naming and the
  // date/timezone handling were never the bug. The actual defect: this
  // array used to be `[...EVENTS, ...discoveryShaped]` with NO chronological
  // sort at all (only `demoted` below, which is a stable no-op for two
  // non-cancelled events) — every real event was unconditionally appended
  // AFTER all ~20 hardcoded static demo events, in whatever order Supabase
  // happened to return them. A newly-approved real event was technically
  // present in the DOM, just buried at the very bottom of a long list of
  // unrelated demo cards — indistinguishable from "missing" for anyone who
  // didn't scroll that far, which is exactly what was reported. Fixed by
  // sorting real events chronologically among themselves (soonest first)
  // and placing that sorted group AHEAD of the static catalogue, rather
  // than reordering the static catalogue's own long-established internal
  // order (a separate, riskier change this pass does not attempt — the
  // static catalogue runs on its own simulated "today," see events.js's own
  // `TODAY` constant, and re-deriving its order from that is out of scope
  // here). `demoted` (cancelled sinks) still applies across the WHOLE
  // merged list afterward, unchanged.
  const realEventsSorted = useMemo(() => discoveryShaped.toSorted((a, b) => {
    if (!a.startsAtRaw && !b.startsAtRaw) return 0;
    if (!a.startsAtRaw) return 1;
    if (!b.startsAtRaw) return -1;
    return new Date(a.startsAtRaw) - new Date(b.startsAtRaw);
  }), [discoveryShaped]);
  const feed = useMemo(() => [...realEventsSorted, ...EVENTS]
    .map(withLive)
    // Ended events leave the feed (they live on the host's profile under "Past events"). One rule for every
    // surface (audit 2026-11-19 row 6): the host's end time, else 12h after the start when the server cron has
    // not flipped the row yet.
    .filter(e => e.endedHoursAgo == null && !isEventOver(e))
    .filter(e => !e.inviteOnly && curArea.match(e))
    .filter(e => !forYouActive || forYouOrder.has(e.key))
    .sort((a, b) => demoted(a) - demoted(b))
    .sort((a, b) => (forYouActive ? forYouOrder.get(a.key) - forYouOrder.get(b.key) : 0))
    .map(e => {
      let seats = e.seats;
      if (e.cancelled) seats = 'Đã hủy';
      else if (e.soldOut) seats = 'Hết chỗ';
      else if (e.endedHoursAgo != null) seats = e.agoLabel(e.endedHoursAgo);
      else if (e.until != null) seats = e.seats + ' ▪︎ ' + e.untilLabel.replace(/^Còn /, '');
      const saved = isSaved(e.key);
      const going = isGoing(e.key) && !e.cancelled && e.endedHoursAgo == null;
      return {
        ...e,
        metaDisplay: trStatus(e.catDisplay) + ' ▪︎ ' + trStatus(stripKm(e.meta, e)),
        seatsDisplay: trStatus(seats),
        saved, going,
        goingLabel: trStatus('Đang tham gia' + ((s.tickets[e.key] || 1) > 1 ? ' ▪︎ ' + s.tickets[e.key] + ' vé' : '')),
        saveLabel: saved ? T('Đã lưu', 'Saved') : T('Lưu', 'Save'),
      };
    }), [realEventsSorted, forYouActive, forYouOrder, s.tickets, s.homeLiveEvents, curArea, isSaved, isGoing, trStatus, stripKm, T]);

  // Popular sort + "Popular this week" label: the same Banbe Pulse score the Pulse viewer ranks by (note 17).
  const pulseScore = useMemo(() => new Map((s.pulseDaily || []).map(p => [p.event_id, Number(p.score) || 0])), [s.pulseDaily]);
  // ---- Discovery layer (note 50) ----------------------------------------------------------------
  // `feed` above is the category + area + For You base. Every event is normalized ONCE into the
  // src/lib/homeDiscovery.js item shape so quick chips, the filter sheet, its per-pill counts and the
  // feed all run the same pure logic (no second filter path to drift).
  // Demo events run on their own simulated "today"; catalogStartMs (events.js) shifts them by the same offset
  // their "in N days" label already uses, so a demo "tomorrow" is tomorrow here too.
  const nowMs = Date.now();
  const discoveryItems = useMemo(() => feed.map(e => {
    const live = s.homeLiveEvents[e.key];
    const startsAt = e.startsAtRaw ? Date.parse(e.startsAtRaw) : catalogStartMs(e, live?.starts_at);
    const fillRow = s.eventFill[e.key];
    const priceVnd = e.isReal ? (e.priceVnd || 0)
      : /miễn phí|free/i.test(e.price || '') ? 0 : (parseInt(String(e.price || '').replace(/[^\d]/g, ''), 10) || null);
    const distanceKm = located && s.userCoords && e.lat != null && e.lng != null ? haversineKm(s.userCoords, e) : null;
    return {
      key: e.key, startsAt, priceVnd, currency: e.isReal ? e.currency : 'VND', catKeys: [e.catKey, e.cat2Key].filter(Boolean),
      // Real events are judged in their venue zone (Today/Weekend in Los Angeles time for an LA event); the demo
      // catalogue keeps the fixed Vietnam offset its simulated dates use.
      tz: e.isReal ? e.tz : undefined,
      booked: fillRow ? fillRow.booked : null, capacity: fillRow ? fillRow.capacity : null,
      soldOut: !!e.soldOut, distanceKm, popularity: pulseScore.get(e.key) ?? null, details: e.details || {}, ev: e,
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [feed, s.eventFill, s.homeLiveEvents, located, s.userCoords, pulseScore]);
  const homeFilters = s.homeFilters || DEFAULT_FILTERS;
  // Note 99: the shared query (the same one Search and the Map use) narrows every Home list, with Search's matcher.
  const udQuery = ud ? String(s.searchQuery || '').trim() : '';
  const qItems = useMemo(() => {
    if (!udQuery) return discoveryItems;
    return discoveryItems.filter(({ ev: e, details }) => matchesSearchQuery(buildEventSearchDoc({
      ...e, catLabel: e.cat, area: e.isReal ? e.area : e.locationLabel, organizerName: e.organizerName || e.hostShort,
      description: e.desc, details,
    }), udQuery));
  }, [discoveryItems, udQuery]);
  // Home → Map (Map redesign phase 3): the Map opens with Home's applied filters and For You; it frames its own map
  // area, so its count can differ from Home's (it says so: "+N matching outside this area").
  const openMapWithContext = () => goMapExplore({ source: 'home', filters: homeFilters, forYou: forYouActive });
  const shownItems = useMemo(() => {
    const filtered = applyDiscoveryFilters(qItems, homeFilters, nowMs);
    // For You keeps its own ranking; any explicit sort overrides it, Soonest keeps the feed's order.
    return s.homeSort && s.homeSort !== 'soonest' ? sortEvents(filtered, s.homeSort) : filtered;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [qItems, homeFilters, s.homeSort, Math.floor(nowMs / 60000)]);
  const quickCounts = useMemo(() => ({
    ...optionCounts(discoveryItems, homeFilters, 'date', ['today', 'weekend'], nowMs),
    free: optionCounts(discoveryItems, homeFilters, 'free', null, nowMs).true,
    almostFull: optionCounts(discoveryItems, homeFilters, 'almostFull', null, nowMs).true,
    seatsLeft: optionCounts(discoveryItems, homeFilters, 'seatsLeft', null, nowMs).true,
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [discoveryItems, homeFilters, Math.floor(nowMs / 60000)]);
  const relaxHints = useMemo(() => (shownItems.length < 3 ? relaxationHints(discoveryItems, homeFilters, nowMs) : []),
  // eslint-disable-next-line react-hooks/exhaustive-deps
    [discoveryItems, homeFilters, shownItems.length]);
  // Event type profiles (switch event_type_profiles, migration 203): with exactly one category picked, that
  // type's own chips (a supper club: Vegetarian-friendly, Vegan, BYO). A chip with 0 events hides unless on.
  const typesOn = flagOn(s.featureFlags, 'event_type_profiles');
  const typeChips = typesOn && homeFilters.cats.length === 1 ? homeTypeFilters(profileFor(homeFilters.cats[0])) : [];
  const typeCounts = useMemo(() => (typeChips.length ? optionCounts(discoveryItems, homeFilters, 'typeFilters', typeChips.map(c => c.id), nowMs) : {}),
  // eslint-disable-next-line react-hooks/exhaustive-deps
    [discoveryItems, homeFilters, typeChips.length, Math.floor(nowMs / 60000)]);
  const toggleTypeFilter = (id) => setHomeFilters(f => {
    const cur = f.typeFilters || [];
    return { ...f, typeFilters: cur.includes(id) ? cur.filter(x => x !== id) : [...cur, id] };
  });
  // Category row (web + iOS twin): the counts are what tapping each category shows, with the very same filter the
  // feed renders with (categoryCounts); the row only lists categories that have events here, most first.
  const categoryCountMap = useMemo(() => categoryCounts(qItems, homeFilters, TYPE_KEYS, nowMs),
  // eslint-disable-next-line react-hooks/exhaustive-deps
    [qItems, homeFilters, Math.floor(nowMs / 60000)]);
  const categoryRow = categoryRowKeys(categoryCountMap, TYPE_KEYS, homeFilters.cats);
  const [categorySheetOpen, setCategorySheetOpen] = useState(false);
  const filterBadge = activeFilterCount(homeFilters);
  const sortActive = !!s.homeSort && s.homeSort !== 'soonest';
  const [sortMenuAnchor, setSortMenuAnchor] = useState(null);
  const [layoutMode, setLayoutMode] = useState(readLayout);
  const pickLayout = (m) => { setLayoutMode(m); try { localStorage.setItem(LAYOUT_KEY, m); } catch { /* per-viewer convenience only */ } };

  // Real events read in their venue's zone (migration 195); demo events (no tz) in the browser's, as before.
  const badgeDate = (ms, tz) => cardDateBadge(ms, tz, T);
  // Best-match label: the top For You match, only when the user has answers. Without answers the first card
  // is "Popular this week" when it's the area's top Pulse event — never called a "match".
  const topPulseKey = useMemo(() => {
    let best = null;
    for (const it of discoveryItems) if (it.popularity != null && (!best || it.popularity > best.popularity)) best = it;
    return best?.key || null;
  }, [discoveryItems]);
  // A catalogue event pages through its LIVE photos (what iOS shows), never the bundled stock gallery, which put
  // photos from other places on the card. No live photos yet: just its cover.
  const realById = s.realEventsById;
  const cardImgs = useCallback((e) => {
    if (e.imgs?.length) return e.imgs;
    const live = realById?.[e.key]?.photoUrls;
    return live?.length ? cardPhotoList(null, live) : (e.img ? [e.img] : []);
  }, [realById]);
  const cards = useMemo(() => shownItems.map((it, i) => {
    const e = it.ev;
    const fill = fillBadge(it.booked, it.capacity);
    if (e.soldOut && fill.left == null) fill.soldOut = true;
    const meta = [e.isReal ? e.area : e.locationLabel, it.distanceKm != null ? `${it.distanceKm.toFixed(1).replace('.', ',')} km` : null, trStatus(e.catDisplay || e.cat)]
      .filter(Boolean).join(' · ');
    let label = null;
    if (i === 0 && forYouRanked.length && forYouRanked[0].key === e.key) label = 'best';
    else if (i === 0 && !forYouActive && topPulseKey === e.key) label = 'popular';
    return {
      key: e.key, name: e.name, img: e.img, imgs: cardImgs(e), dateBadge: badgeDate(it.startsAt, e.isReal ? e.tz : null),
      priceLabel: it.priceVnd === 0 ? T('Miễn phí', 'Free') : trStatus(e.price), isFree: it.priceVnd === 0,
      metaLine: meta, fill, cancelled: !!e.cancelled, saved: e.saved, going: e.going, label,
      typeLine: typesOn && (e.isReal || Object.keys(e.details || {}).length > 0) ? cardLine(profileFor(e.catKey), { capacity: it.capacity ?? e.capacity, details: e.details }, s.lang === 'en' ? 'en' : 'vi') : null,
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [shownItems, forYouRanked, forYouActive, topPulseKey, trStatus, T, typesOn, s.lang, cardImgs]);

  // One "is this still on" rule for every Home rail and list (audit 2026-11-19 row 6). It used to drop anything
  // that had merely STARTED more than an hour ago, which is why the type tiles and their lists disagreed; the
  // event's own end time (or 12h after the start when none is stated) decides now.
  const isOpenItem = useCallback((it) => !it.ev.cancelled && Number.isFinite(it.startsAt)
    && !isEventOver({ startsAt: it.startsAt, tz: it.tz || it.ev.tz, endTime: it.ev.endTime, endOpen: it.ev.endOpen }, nowMs),
  // eslint-disable-next-line react-hooks/exhaustive-deps
  [nowMs]);

  // Home photo hero (note 80): For You / Tonight / Weekend rails built from the same items and filters as the list.
  const heroLists = useMemo(() => {
    if (!simpleShell) return null;
    const open = (it) => !it.soldOut && isOpenItem(it);
    const shape = (it) => {
      const e = it.ev;
      const fill = fillBadge(it.booked, it.capacity);
      return {
        key: e.key, name: e.name, img: e.img, saved: !!e.saved, dateBadge: badgeDate(it.startsAt, e.isReal ? e.tz : null),
        priceLabel: it.priceVnd === 0 ? T('Miễn phí', 'Free') : trStatus(e.price),
        metaLine: trStatus(e.catDisplay || e.cat) || '', left: fill.left != null ? T(`Còn ${fill.left} chỗ`, `${fill.left} left`) : '',
      };
    };
    const base = { ...homeFilters, date: 'any' };
    // v2.3 (note 81): at most four frames, then the See all card.
    const railMax = v23 ? 4 : 5;
    const byDate = (date) => applyDiscoveryFilters(qItems, { ...base, date }, nowMs).filter(open).slice(0, railMax).map(shape);
    const byKey = new Map(qItems.map(it => [it.key, it]));
    const ranked = forYouRanked.map(m => byKey.get(m.key)).filter(Boolean).filter(open);
    const soonest = applyDiscoveryFilters(qItems, base, nowMs).filter(open);
    // The empty Tonight card names the weekend's real size, so it needs the count before the rail's cap.
    const weekendAll = applyDiscoveryFilters(qItems, { ...base, date: 'weekend' }, nowMs).filter(open);
    return { foryou: (ranked.length ? ranked : soonest).slice(0, railMax).map(shape), tonight: byDate('today'),
      weekend: weekendAll.slice(0, railMax).map(shape), weekendTotal: weekendAll.length };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [simpleShell, v23, qItems, homeFilters, forYouRanked, T, trStatus, Math.floor(nowMs / 60000)]);
  // Home from the v5 prototype (note 80): which hero tab is open (For You | Tonight | Weekend).
  const [heroTab, setHeroTab] = useState('foryou');
  // Note 99: with unified discovery the open tab is the shared time itself.
  const curTab = ud ? tabForDate(homeFilters.date) : heroTab;
  // v2.3 (note 81, switch home_v23, on top of simple_shell): the Shortlist under the rail is the WHOLE tab, in the
  // tab's order, narrowed by Home's filters (the rail stays the tab's picks). total = before the filters.
  // The whole tab, in the tab's own order (For You ranked, else soonest), before Home's filters. Shared by the
  // Shortlist and See all.
  const tabItems = useCallback((tab) => {
    const open = isOpenItem;
    if (tab === 'tonight' || tab === 'weekend') {
      return applyDiscoveryFilters(discoveryItems, { ...DEFAULT_FILTERS, date: tab === 'tonight' ? 'today' : 'weekend' }, nowMs).filter(open);
    }
    if (tab === 'foryou') {
      const byKey = new Map(discoveryItems.map(it => [it.key, it]));
      const ranked = forYouRanked.map(m => byKey.get(m.key)).filter(Boolean).filter(open);
      if (ranked.length) return ranked;
    }
    return applyDiscoveryFilters(discoveryItems, DEFAULT_FILTERS, nowMs).filter(open);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [discoveryItems, forYouRanked, Math.floor(nowMs / 60000)]);
  // One v2.3 row (EventRowV23): when · type, title, then place or status with the price.
  const shapeRow = useCallback((it) => {
    const e = it.ev;
    const fill = fillBadge(it.booked, it.capacity);
    const soldOut = it.soldOut || fill.soldOut;
    // The type's own name (eventTypeProfiles.json) in the reader's language, not the catalogue's raw label.
    const def = TYPE_DEF_BY_KEY.get(it.catKeys?.[0]);
    return {
      key: e.key, name: e.name, img: e.img, saved: isSaved(e.key),
      type: def ? T(def.vi, def.en) : trStatus(e.catDisplay || e.cat), when: badgeDate(it.startsAt, e.isReal ? e.tz : null),
      place: [e.isReal ? e.area : e.locationLabel, it.distanceKm != null ? `${it.distanceKm.toFixed(1).replace('.', ',')} km` : null].filter(Boolean).join(' · '),
      priceLabel: it.priceVnd === 0 ? T('Miễn phí', 'Free') : trStatus(e.price), isFree: it.priceVnd === 0,
      status: soldOut ? { tone: 'alert', text: T('Hết chỗ', 'Sold out') }
        : fill.almostFull ? { tone: 'honey', text: T(`Sắp hết · còn ${fill.left} chỗ`, `Almost full · ${fill.left} left`) } : null,
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [T, trStatus, isSaved]);
  // The Shortlist follows the FILTERS, not the hero tab: it is every event Home lists, narrowed by Home's filters and
  // in Home's own order (homeSort, else the feed's). The tabs above only switch the rail, so the list under it never
  // empties just because For You is open. total = before the filters.
  const shortlistBase = useMemo(() => {
    if (!v23) return null;
    const open = isOpenItem;
    return applyDiscoveryFilters(qItems, DEFAULT_FILTERS, nowMs).filter(open);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [v23, qItems, Math.floor(nowMs / 60000)]);
  const shortlist = useMemo(() => {
    if (!shortlistBase) return null;
    const narrowed = applyDiscoveryFilters(shortlistBase, homeFilters, nowMs);
    return { rows: (s.homeSort && s.homeSort !== 'soonest' ? sortEvents(narrowed, s.homeSort) : narrowed).map(shapeRow), total: shortlistBase.length };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shortlistBase, homeFilters, s.homeSort, shapeRow, Math.floor(nowMs / 60000)]);
  // v2.3 live line (note 81): the daily Pulse ranking + real seat fill + the Tonight / Weekend counts, only for events
  // Home actually lists (so every update can be opened). One list for the ticker, the Reduced form and Live now.
  const [liveIndex, setLiveIndex] = useState(0);
  const reducedMotion = useReducedMotion();
  // Picking a view from the band (a row in its menu, or a tab) sends the feed back to the events — whether or not the
  // view actually changed, since the pick can happen far down the page where the list that changes is out of sight.
  // App.jsx owns the scroll through homeScrollTopToken; area picks do the same in pickArea (BanBeContext), so
  // re-tapping the area already on works too. The first render is not a pick, so a restored scroll is never overridden.
  const returnToEvents = useCallback(() => set({ homeScrollTopToken: Date.now() }), [set]);
  const [liveOpen, setLiveOpen] = useState(false);
  const live = useMemo(() => {
    if (!v23 || browse) return [];
    const byKey = new Map(discoveryItems.map(it => [it.key, it]));
    const lookup = (id) => {
      const it = byKey.get(id);
      if (!it || it.ev.cancelled) return null;
      return { seatsLeft: fillBadge(it.booked, it.capacity).left, when: badgeDate(it.startsAt, it.ev.isReal ? it.ev.tz : null) };
    };
    return liveUpdates({ pulse: s.pulseDaily, lookup, tonight: tabItems('tonight').length, weekend: tabItems('weekend').length });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [v23, browse, s.pulseDaily, discoveryItems, tabItems, T, Math.floor(nowMs / 60000)]);
  useEffect(() => { if (liveIndex >= live.length) setLiveIndex(0); }, [live.length, liveIndex]);
  // Browse's scope: the whole catalogue (every live event Home lists) or one tab. Catalogue events that share a key
  // with a real row lose its host fields in the merge, so the host (id, name, photo) is read from the loaded real row.
  const browseItems = useMemo(() => {
    if (!browse) return null;
    const scope = s.browseScope || 'all';
    const base = scope === 'all' ? applyDiscoveryFilters(discoveryItems, DEFAULT_FILTERS, nowMs).filter(it => !it.ev.cancelled) : tabItems(scope);
    return base.map((it) => {
      const real = s.realEventsById?.[it.key];
      if (it.ev.organizerId || !real?.organizerId) return it;
      return { ...it, ev: { ...it.ev, organizerId: real.organizerId, organizerName: real.organizerName || '', organizerAvatarUrl: real.organizerAvatarUrl || '' } };
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [browse, s.browseScope, discoveryItems, tabItems, s.realEventsById, Math.floor(nowMs / 60000)]);
  const onShortlistAction = (act) => {
    if (act === 'clear-filters') { clearFilters(); set({ homeSort: 'soonest' }); }
    else if (act === 'map') openMapWithContext();
    // Prototype v2's end-card "Tất cả loại": a type sheet over Home, not a Browse-by-type screen.
    else if (act === 'types') { if (ud) setTypeSheetOpen(true); else openBrowse({ type: 'all', scope: 'all' }); }
  };

  // Prototype v2: the rail's end card ("Xem tất cả N · trong Gần bạn hoặc trên bản đồ") scrolls Home down to the
  // "Gần bạn" list. It does NOT open a separate Browse-by-type screen.
  const scrollToNearby = () => {
    const el = document.querySelector('[data-testid="home-shortlist-section"]');
    if (!el) return;
    const sc = document.querySelector('[data-testid="app-scroll-viewport"]');
    const box = el.getBoundingClientRect();
    const top = (sc ? sc.scrollTop : window.scrollY) + box.top - (sc ? sc.getBoundingClientRect().top : 0) - 70;
    (sc || window).scrollTo({ top: Math.max(0, top), behavior: 'smooth' });
  };

  const heroSeeAll = (tab) => {
    if (v23) { if (ud) scrollToNearby(); else openBrowse({ type: 'all', scope: tab }); return; }
    if (tab === 'foryou') { if (!s.filterForYou && hasForYou) toggleHomeFilter('forYou'); }
    else if (homeFilters.date !== (tab === 'tonight' ? 'today' : 'weekend')) pickFilter(tab === 'tonight' ? 'today' : 'weekend');
    setTimeout(() => document.querySelector('[data-testid^="home-event-"]')?.scrollIntoView({ block: 'start', behavior: 'smooth' }), 120);
  };

  // Note 85: See all carries Home's three tabs, so a reader changes tab without going back to Home first. The tab is
  // what changes: its search and its own filters start clean (the same reset a fresh See all takes), and the type
  // survives only where the new tab still has it (a tab can be a different slice of the catalogue).
  const browseScopeTo = (tab) => {
    const keepType = (browseTypeCounts(tabItems(tab))[s.browseType] || 0) > 0;
    setBrowse({ browseScope: tab, browseType: keepType ? s.browseType : 'all', browseFrom: null, browseQuery: '', browseFilters: DEFAULT_FILTERS });
  };

  // Note 86: from inside a tab's See all, Browse by type opens the whole catalogue's list (every event, note 88) and
  // remembers the tab, so Back there returns to that tab instead of Home.
  const browseTypesFrom = (tab) => openBrowse({ type: 'all', scope: 'all', from: tab && tab !== 'all' ? tab : null });

  // Retention roadmap P1 ("Cuối tuần này") — reuses the SAME district
  // (curArea) and category (homeFilters.cats) picks already driving the main feed
  // above, rather than inventing a separate preference of its own; there is
  // no existing price preference anywhere in this app to reuse, so price
  // isn't filtered here, only displayed. `weekendEvents` itself is already
  // real-events-only and pre-sorted (followed hosts first, then soonest —
  // see loadWeekendEvents' own comment); this only narrows by the two
  // shared filters and caps it to a compact strip.
  // Location hierarchy (2026-09-30) — the second, duplicated
  // AREA_DISTRICT_MATCH table that used to live here is gone: the weekend
  // strip now uses the SAME curArea.match() the main feed above does
  // (src/lib/locationTree.js's eventMatchesLocation), so the two can
  // never disagree about which events are "in" the selected location.
  const weekendList = useMemo(() => (s.weekendEvents || [])
    .filter(e => curArea.match(e))
    .filter(e => !(s.homeFilters?.cats || []).length || s.homeFilters.cats.includes(e.catKey))
    .slice(0, 12)
    .map(e => {
      // Seats left comes from the live fill RPC, never from `events.seats_remaining` — that column is not decremented
      // when a booking is made, so printing it overstated availability (audit 2026-11-19 row 13). No fill yet means no
      // figure, rather than a guessed one.
      const fill = s.eventFill?.[e.key];
      const left = fill && fill.capacity != null && fill.booked != null ? Math.max(0, fill.capacity - fill.booked) : null;
      return {
        ...e,
        saved: isSaved(e.key),
        priceDisplay: e.priceLabel || T('Miễn phí', 'Free'),
        seatsDisplay: left != null
          ? (left === 0 ? T('Hết chỗ', 'Sold out') : T(`Còn ${left} chỗ`, `${left} left`))
          : (e.soldOut ? T('Hết chỗ', 'Sold out') : ''),
      };
    }), [s.weekendEvents, s.eventFill, curArea, s.homeFilters, isSaved, T]);

  // L5 weekly digest (src/lib/coreLoops.js): its notification opens Home at "This weekend". Waits for the rail to
  // exist (it is hidden on the very first load) and runs after the shell's own scroll restore, once per token.
  const weekendRef = useRef(null);
  const weekendScrolledFor = useRef(0);
  const weekendRailReady = !(s.weekendEventsLoading && weekendList.length === 0);
  useEffect(() => {
    const token = s.homeWeekendScrollToken;
    if (!token || weekendScrolledFor.current === token || !weekendRailReady) return undefined;
    const t = setTimeout(() => {
      const el = weekendRef.current;
      if (!el) return;
      weekendScrolledFor.current = token;
      el.scrollIntoView({ block: 'start', behavior: 'smooth' });
    }, 350);
    return () => clearTimeout(t);
  }, [s.homeWeekendScrollToken, weekendRailReady]);

  const heldKey = heldEv ? heldEv.key : null;
  // Note 50: the "Your events" strip is gone (Schedule + Account own your events). What stays is the one part
  // with real value: the note-37 reminder, as a "Next up" banner. Only a confirmed ticket can carry a reminder,
  // so only those keys are resolved here.
  const savedKeys = [...new Set([...s.attending, ...s.favorites, ...s.invited])].filter(k => isGoing(k) && k !== heldKey);

  // Blocker fix (retention roadmap follow-up) — a saved/attending/invited
  // event that ISN'T one of the 20 static demo ones (a real, host-created
  // event) used to just vanish here (EVENTS.find returns undefined,
  // filtered out by Boolean below) even though the favorite/booking row
  // itself was completely real. Anything not in the catalogue is now
  // resolved through the SAME canonical realEventsById cache the weekend
  // section uses (loadRealEventsById) — one lookup, not a second one.
  const missingRealKeys = savedKeys.filter(k => !EVENTS.some(e => e.key === k) && !(k in s.realEventsById));
  useEffect(() => {
    if (missingRealKeys.length) loadRealEventsById(missingRealKeys);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [missingRealKeys.join(','), loadRealEventsById]);

  // Task 2a (2026-09-21 follow-up) — real 48h-after-ENDED expiry: `withLive`
  // merges the actual DB row's status/starts_at (homeLiveEvents) so
  // `endedHoursAgo` is a genuinely ticking value instead of the static
  // catalogue's baked-in-forever number — an upcoming/ongoing event's
  // `endedHoursAgo` stays `null` (liveEventOverrides only sets it once
  // `status === 'ended'`), so this clause never fires for anything that
  // hasn't actually finished yet.
  const savedList = savedKeys
    .map(k => {
      const catalogEv = EVENTS.find(e => e.key === k);
      if (catalogEv) {
        const e = withLive(catalogEv);
        const nTix = s.tickets[e.key] || 1;
        const tixStr = nTix > 1 ? ' ▪︎ ' + nTix + ' vé' : '';
        const invited = e.inviteOnly && s.invited.includes(e.key);
        let tag, status, chip;
        if (e.cancelled) { tag = 'Đã hủy'; status = 'Đã hoàn tiền'; chip = CHIP_COLORS.cancelled; }
        else if (e.endedHoursAgo != null) { tag = 'Đã diễn ra'; status = e.agoLabel(e.endedHoursAgo); chip = CHIP_COLORS.past; }
        else if (invited && !isGoing(e.key)) { tag = T('Riêng tư', 'Private'); status = T('Chỉ bạn và +1 ▪︎ ', 'Just you + 1 ▪︎ ') + e.untilLabel; chip = CHIP_COLORS.invite; }
        else if (e.key === heldKey) { tag = 'Đang giữ'; status = 'Trả để xác nhận' + tixStr; chip = CHIP_COLORS.hold; }
        else if (isGoing(e.key)) { tag = 'Đã thanh toán'; status = e.untilLabel + tixStr; chip = CHIP_COLORS.going; }
        else { tag = 'Đã lưu'; status = e.untilLabel; chip = CHIP_COLORS.saved; }
        // Reminder: a ticket-holder's event within 24h of starting, or ongoing.
        const reminder = isGoing(e.key) && e.key !== heldKey ? reminderPhase(e.startDate) : null;
        if (reminder) { tag = reminder === 'live' ? 'Đang diễn ra' : 'Sắp diễn ra'; chip = CHIP_COLORS.reminder; }
        return {
          key: e.key, name: e.name, photoUrl: e.img, endedHoursAgo: e.endedHoursAgo, reminder,
          startMs: e.startDate instanceof Date ? e.startDate.getTime() : NaN, tz: null,
          status: trStatus(status), tag: trStatus(tag), chip,
          canRemove: !isGoing(e.key) && e.key !== heldKey && !invited,
          toEvent: e.cancelled ? 'refunded' : 'event',
        };
      }
      const real = s.realEventsById[k];
      if (real === undefined) return null; // still loading — quiet, no flash
      if (real === null) {
        // Honest "unavailable" — deleted, or RLS no longer lets this
        // account see it. Never invented, never silently dropped.
        return {
          key: k, name: T('Sự kiện không khả dụng', 'Event unavailable'), photoUrl: null,
          status: '', tag: T('Không khả dụng', 'Unavailable'), chip: CHIP_COLORS.cancelled,
          endedHoursAgo: null, canRemove: isSaved(k), toEvent: null, unavailable: true,
        };
      }
      const startsAt = real.startsAt ? new Date(real.startsAt) : null;
      const untilLabel = startsAt ? (() => { const { weekdayShort, dayMonth, time } = formatVnEventDate(startsAt, real.tz); return `${weekdayShort}, ${dayMonth} ▪︎ ${time}`; })() : '';
      const endedHoursAgo = real.status === 'ended' && startsAt ? Math.max(0, Math.round((Date.now() - startsAt.getTime()) / 3600000)) : null;
      const cancelled = real.status === 'cancelled';
      const invited = real.visibility === 'invite' && s.invited.includes(k);
      let tag, status, chip;
      if (cancelled) { tag = T('Đã hủy', 'Cancelled'); status = T('Đã hoàn tiền', 'Refunded'); chip = CHIP_COLORS.cancelled; }
      else if (endedHoursAgo != null) { tag = T('Đã diễn ra', 'Past'); status = T(endedHoursAgo + ' giờ trước', endedHoursAgo + 'h ago'); chip = CHIP_COLORS.past; }
      else if (invited && !isGoing(k)) { tag = T('Riêng tư', 'Private'); status = T('Chỉ bạn và +1 ▪︎ ', 'Just you + 1 ▪︎ ') + untilLabel; chip = CHIP_COLORS.invite; }
      else if (k === heldKey) { tag = T('Đang giữ', 'Holding'); status = T('Trả để xác nhận', 'Pay to confirm'); chip = CHIP_COLORS.hold; }
      else if (isGoing(k)) { tag = T('Đã thanh toán', 'Paid'); status = untilLabel; chip = CHIP_COLORS.going; }
      else { tag = T('Đã lưu', 'Saved'); status = untilLabel; chip = CHIP_COLORS.saved; }
      const reminder = !cancelled && endedHoursAgo == null && isGoing(k) && k !== heldKey ? reminderPhase(startsAt, { status: real.status }) : null;
      if (reminder) { tag = reminder === 'live' ? T('Đang diễn ra', 'Happening now') : T('Sắp diễn ra', 'Starting soon'); chip = CHIP_COLORS.reminder; }
      return {
        key: k, name: real.name, photoUrl: real.photoUrl, endedHoursAgo, reminder,
        startMs: startsAt ? startsAt.getTime() : NaN, tz: rowTimeZone(real),
        status, tag, chip,
        canRemove: !isGoing(k) && k !== heldKey && !invited,
        toEvent: cancelled ? 'refunded' : 'event',
      };
    })
    .filter(Boolean)
    .filter(e => !(e.endedHoursAgo != null && e.endedHoursAgo > 48))
    // Reminder events (starting within 24h / happening now) lead the strip, "live" first;
    // Array.sort is stable so everything else keeps its existing order.
    .sort((a, b) => reminderRank(a.reminder) - reminderRank(b.reminder));
  const nextUp = savedList.find(x => x.reminder) || null;
  // v2.3 Next up (note 81): every upcoming ticket of the viewer as a ticket card, one per event, soonest first, from
  // the bookings Home already loads (src/lib/nextUp.js). Replaces the 24 h reminder banner while home_v23 is on.
  const nextUpItems = (() => {
    if (!v23 || !s.user) return [];
    const nowMs2 = Date.now();
    const evInfo = {};
    const shape = {};
    for (const b of s.paymentBookings || []) {
      const id = b.event_id || b.events?.id;
      if (!id || evInfo[id]) continue;
      const real = s.realEventsById[id] || null;
      const demo = EVENTS.find(e => e.key === id) || null;
      const tz = real ? rowTimeZone(real) : 'Asia/Ho_Chi_Minh';
      const date = real?.eventDate || b.events?.event_date;
      const start = String(real?.eventTime || b.events?.event_time || '').slice(0, 5);
      const startMs = real?.startsAt ? Date.parse(real.startsAt) : (date && start ? wallClockToMs(date, start, tz) : NaN);
      if (!Number.isFinite(startMs)) continue;
      const endTime = real?.endTime ? String(real.endTime).slice(0, 5) : (demo?.endTime || null);
      const endOpen = !!(real?.endOpen || (!real?.endTime && demo?.endOpen));
      const endMs = endTime && date ? wallClockToMs(date, endTime, tz) + (endsNextDay(start, endTime) ? 86400000 : 0) : null;
      evInfo[id] = { startMs, endMs, cancelled: real?.status === 'cancelled' || real?.status === 'removed' };
      const nextDay = !!endTime && endsNextDay(start, endTime);
      shape[id] = {
        name: real?.name || b.events?.name || demo?.name || '', img: real?.photoUrl || demo?.img || '',
        kicker: [trStatus(real?.catLabel || demo?.cat || ''), real?.area || b.events?.area || demo?.area || ''].filter(Boolean).join(' · '),
        badge: dateBadge(startMs, tz, s.lang === 'en'), tz,
        time: start,
        // "to 22:30", "(+1)" when it ends after midnight, or open-ended (note 82).
        timeNote: endTime ? T(`đến ${endTime}${nextDay ? ' (+1)' : ''}`, `to ${endTime}${nextDay ? ' (+1)' : ''}`) : endOpen ? T('chưa có giờ kết thúc', 'no end time yet') : null,
        mapsUrl: real?.lat != null ? mapsUrl({
          lat: real.lat, lng: real.lng, name: real.name, addressLine: real.addressLine,
          area: real.area, city: real.city,
        }) : (demo ? mapsUrl(demo) : null),
      };
    }
    return nextUpGroups(s.paymentBookings || [], evInfo, nowMs2).map(g => ({
      g, ev: shape[g.eventId], status: nextUpStatus(g, nowMs2), chip: nextUpChip(g, nowMs2, shape[g.eventId].tz), people: peopleLine(g),
    }));
  })();
  const onNextUp = (action, it) => {
    if (action === 'open') return goEvent(it.g.eventId);
    if (action === 'pay') return openPaymentDetails(it.g.primaryId, 'home');
    return openBookingConfirmed(it.g.primaryId, it.g.eventId, 'home');
  };
  // L7 day-of card (switch live_activity): on the event's own day in the VENUE's zone, a confirmed ticket of the
  // person's own (not one gifted away) is one tap away from the Next-up banner. No countdown, no urgency words.
  const nextUpTicket = flagOn(s.featureFlags, 'live_activity') && nextUp && isEventLocalDay(nextUp.startMs, Date.now(), nextUp.tz)
    ? (s.paymentBookings || []).find(b => isBookingTicket(b) && !b.recipient_name
      && (b.event_id === nextUp.key || b.events?.key === nextUp.key || b.events?.id === nextUp.key)) || null
    : null;

  // Phase 1 Q8 "Saved, coming up": the person's saved events that are live and start within 30 days, soonest first,
  // at most 5 (src/lib/quickWins.js), each with its real date and, when known, its real fill ("12 of 20 taken" from
  // get_public_event_fill). No timers, no urgency words. Hidden for guests and when empty.
  const favKeys = s.user ? (s.favorites || []) : [];
  const missingFavKeys = favKeys.filter(k => !EVENTS.some(e => e.key === k) && !(k in s.realEventsById));
  useEffect(() => {
    if (missingFavKeys.length) loadRealEventsById(missingFavKeys);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [missingFavKeys.join(','), loadRealEventsById]);
  const savedUpcoming = savedComingUp(favKeys.map(k => {
    const catalogEv = EVENTS.find(e => e.key === k);
    if (catalogEv) {
      const e = withLive(catalogEv);
      return { key: k, name: e.name, status: e.cancelled ? 'cancelled' : e.endedHoursAgo != null ? 'ended' : 'live', startsAt: e.startDate || null, tz: null };
    }
    const real = s.realEventsById[k];
    return real ? { key: k, name: real.name, status: real.status, startsAt: real.startsAt, tz: rowTimeZone(real) } : null;
  }).filter(Boolean), Date.now());
  const missingFillKeys = savedUpcoming.map(e => e.key).filter(k => !(k in s.eventFill));
  useEffect(() => {
    if (!missingFillKeys.length) return undefined;
    let live = true;
    supabase.rpc('get_public_event_fill', { p_event_ids: missingFillKeys }).then(({ data, error }) => {
      if (!live || error || !Array.isArray(data)) return;
      set(prev => ({ eventFill: { ...prev.eventFill, ...Object.fromEntries(data.map(r => [r.event_id, { booked: r.booked, capacity: r.capacity }])) } }));
    }, () => {});
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [missingFillKeys.join(',')]);

  const homeHostLinkLabel = hasHosted ? T('Trang tổ chức của bạn', 'Your host page') : T('Dành cho người tổ chức ▪︎ hoàn toàn miễn phí', 'For organizers ▪︎ completely free');
  const homeHostLink = hasHosted ? () => switchToHost('home') : becomeHost;

  // Header row: drop the "Home" title first when the wordmark + shortcuts + search would not fit
  // (same rule as iOS ViewThatFits; every control keeps its 44px touch target).
  const headerRef = useRef(null);
  const shortcutsOn = rewardsEnabled && s.rewardsSummaryStatus === 'loaded' && !!s.rewardsSummary;
  const capStreak = capsuleStreak(s.rewardsSummary, rewardsV2Enabled);
  const streakChars = String(capStreak.value).length;
  const coinChars = compactCoins(s.rewardsSummary?.balance ?? 0).length;
  // MEASURED, not estimated (2026-10-18): the estimate undershot the real control widths, so the title was
  // overlapped by the capsule. Start from the full layout (96px wordmark + title) and step down while the left
  // group would touch the right group: smaller wordmark first, then drop the title, last resort no wordmark.
  const [fitStep, setFitStep] = useState(0);
  const layout = HEADER_FIT_STEPS[fitStep] || HEADER_FIT_STEPS[HEADER_FIT_STEPS.length - 1];
  const showTitle = layout.showTitle;
  const headerKey = `${shortcutsOn}|${streakChars}|${coinChars}|${s.lang}|${s.unreadNotifications > 0}`;
  useEffect(() => {
    const el = headerRef.current;
    if (!el || typeof ResizeObserver === 'undefined') return undefined;
    let last = el.clientWidth;
    const ro = new ResizeObserver(() => { if (el.clientWidth !== last) { last = el.clientWidth; setFitStep(0); } });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  useEffect(() => { setFitStep(0); }, [headerKey]);
  useLayoutEffect(() => {
    const el = headerRef.current;
    if (!el || fitStep >= HEADER_FIT_STEPS.length - 1) return;
    const left = el.children[0], right = el.children[1];
    if (!left || !right) return;
    const overflow = left.getBoundingClientRect().right + 8 > right.getBoundingClientRect().left + 0.5;
    if (overflow) setFitStep(fitStep + 1);
  });

  // The area picker, anchored under whichever control opened it (the location pill, or the search bar's area button).
  const openAreaMenu = (e) => {
    // Anchor in the coordinates of the overlay container: on desktop the app sits inside a phone frame
    // (.bb-screen is the containing block for fixed overlays); elsewhere .bb-screen is display:contents
    // and its rect is empty, so the viewport is the reference.
    const r = e.currentTarget.getBoundingClientRect();
    const frame = e.currentTarget.closest('.bb-screen')?.getBoundingClientRect();
    const inFrame = frame && frame.width > 0;
    set({ areaMenuOpen: true, areaMenuAnchor: {
      left: r.left - (inFrame ? frame.left : 0), bottom: r.bottom - (inFrame ? frame.top : 0),
      width: inFrame ? frame.width : window.innerWidth } });
  };
  const areaName = curArea.key === 'all' ? T('Mọi nơi', 'Everywhere') : curArea.label;
  // Home from the v5 prototype (note 80): Browse counts, By type summary and the type pick (heroTab is declared above, the Shortlist reads it).
  const [quickOpen, setQuickOpen] = useState(false);
  const shellTypeCounts = useMemo(() => {
    const o = { ...categoryCountMap };
    delete o.all;
    return o;
  }, [categoryCountMap]);
  const shellFilterSummary = [
    areaName,
    { today: T('Hôm nay', 'Today'), tomorrow: T('Ngày mai', 'Tomorrow'), weekend: T('Cuối tuần', 'Weekend'), week: T('7 ngày tới', 'Next 7 days') }[homeFilters.date] || T('Mọi lúc', 'Any time'),
    homeFilters.free ? T('Miễn phí', 'Free') : T('Mọi mức giá', 'Any price'),
  ].join(' · ');
  // ---- Note 99: unified discovery helpers ----
  const [typeSheetOpen, setTypeSheetOpen] = useState(false);
  const udOwned = ownedFilterCount(homeFilters, s.homeSort);
  const udParts = !ud ? [] : [
    udQuery && { text: `“${udQuery}”`, strong: true },
    homeFilters.cats?.[0] && { text: T(TYPE_DEF_BY_KEY.get(homeFilters.cats[0])?.vi || homeFilters.cats[0], TYPE_DEF_BY_KEY.get(homeFilters.cats[0])?.en || homeFilters.cats[0]), strong: true },
    homeFilters.free ? { text: T('Miễn phí', 'Free'), strong: true }
      : (homeFilters.priceMin != null || homeFilters.priceMax != null) && { text: T('Theo khoảng giá', 'Price range'), strong: true },
    homeFilters.seatsLeft && { text: T('Còn chỗ', 'Seats left'), strong: true },
    homeFilters.almostFull && { text: T('Sắp hết', 'Almost full'), strong: true },
    s.homeSort && s.homeSort !== 'soonest' && SORT_LABELS?.[s.homeSort] && { text: T(...SORT_LABELS[s.homeSort]), strong: false },
    homeFilters.date !== 'any' && DATE_LABELS?.[homeFilters.date] && { text: T(...DATE_LABELS[homeFilters.date]), strong: false },
  ].filter(Boolean);
  const clearUnified = () => {
    set({ searchQuery: '', homeSort: 'soonest' });
    searchBarStore.setSearchQuery('');
    setHomeFilters(prev => ({ ...DEFAULT_FILTERS, date: prev?.date || 'any' }));
  };
  // Search (an overlay over this live Home) narrows its event hits to what Home's filters let through.
  const udKeys = useMemo(() => (ud ? applyDiscoveryFilters(discoveryItems, homeFilters, nowMs).map(it => it.key).join('|') : null),
  // eslint-disable-next-line react-hooks/exhaustive-deps
    [ud, discoveryItems, homeFilters, Math.floor(nowMs / 60000)]);
  useEffect(() => { if (s.unifiedKeys !== udKeys) set({ unifiedKeys: udKeys }); }, [udKeys]); // eslint-disable-line react-hooks/exhaustive-deps
  const shellPickType = (k) => {
    if (!(homeFilters.cats || []).includes(k)) pickFilter(k);
    setTimeout(() => document.querySelector('[data-testid="home-by-type"]')?.scrollIntoView({ block: 'start', behavior: 'smooth' }), 120);
  };


  // Simple Shell: exactly one block at the top (src/lib/homeHero.js). Saved-coming-up only when nothing else leads.
  const goerHero = simpleShell ? pickGoerHero({
    signedIn: !!s.user, nextUp, actionCount: actionItems.length,
    checklistVisible: !!s.user && checklistVisible(s.activation, (s.favorites || []).length > 0),
  }) : null;
  // Sort moved into Filters, so a non-default sort counts on the Filters badge too.
  const simpleFilterBadge = filterBadge + (sortActive ? 1 : 0);
  const hasPulse = tickerItems(s.pulseDaily).length > 0;

  const savedUpcomingEl = savedUpcoming.length > 0 && (
    <section data-testid="home-saved-upcoming" aria-labelledby="home-saved-upcoming-title" style={{ padding: '6px 20px 10px' }}>
        <h2 id="home-saved-upcoming-title" style={{ ...display(17), margin: '0 0 6px' }}>{T('Đã lưu, sắp diễn ra', 'Saved, coming up')}</h2>
        {savedUpcoming.map((e, i) => {
          const fill = s.eventFill[e.key];
          const ft = fill ? fillText(fill.capacity, fill.booked) : null;
          return (
            <div key={e.key} onClick={() => goEvent(e.key)} role="button" tabIndex={0} data-testid={`home-saved-upcoming-${e.key}`}
              onKeyDown={(k) => { if (k.key === 'Enter' || k.key === ' ') { k.preventDefault(); goEvent(e.key); } }}
              style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '10px 0', borderTop: i > 0 ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}>
              <span style={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                <span style={{ fontSize: 14.5, fontWeight: 600, color: ink, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{e.name}</span>
                <span style={{ fontSize: 12.5, color: ink, opacity: 0.65 }}>
                  {whenLabel(e.startsAt, e.tz, s.lang === 'en')}{ft ? ` · ${T(ft.vi, ft.en)}` : ''}
                </span>
              </span>
              <span aria-hidden style={{ fontSize: 16, color: ink, opacity: 0.4, flex: 'none' }}>›</span>
            </div>
          );
        })}
      </section>
  );
  const pulseTicker = <div style={{ padding: '0 20px' }}><PulseTicker pulse={s.pulseDaily} onOpen={openPulseViewer} T={T} /></div>;
  // Host stories (07-notifications.md Task 3.3). Banbe Pulse moved to the ticker under the search bar (note 51),
  // so this row exists ONLY when there are stories: no stories, no row, no empty band. Compact 52px rings.
  const storyRow = s.homeStories.length > 0 && (
    <div data-hscroll="true" data-testid="home-story-row" style={{ display: 'flex', gap: 12, overflowX: 'auto', padding: '10px 20px 6px', scrollbarWidth: 'none' }}>
      {s.homeStories.map(g => (
        <div
          key={g.organizerId}
          onClick={(e) => {
            const r = e.currentTarget.getBoundingClientRect();
            openStoryViewer(g.organizerId, { top: r.top, left: r.left, width: r.width, height: r.height });
          }}
          data-testid="home-story-avatar"
          data-org-id={g.organizerId}
          data-story-state={g.allViewed ? 'viewed' : 'unviewed'}
          style={{ flex: 'none', width: 56, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, cursor: 'pointer' }}
        >
          <div style={{
            width: 52, height: 52, borderRadius: 14, display: 'flex', alignItems: 'center', justifyContent: 'center',
            border: `2.5px solid ${g.allViewed ? 'transparent' : alert}`,
            boxShadow: g.allViewed ? `inset 0 0 0 2.5px ${rule}` : 'none',
          }}>
            <div style={{ ...fieldGlass({ width: 44, height: 44, borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center' }), fontSize: 15, fontWeight: 700 }}>
              {(g.orgName || '?').charAt(0).toUpperCase()}
            </div>
          </div>
          <span style={{ fontSize: 'var(--bb-text-meta)', color: ink, textAlign: 'center', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: 56 }}>{g.orgName}</span>
        </div>
      ))}
    </div>
  );

  // Event-type chips under the category row (exactly one category picked), both layouts.
  const typeChipRow = typeChips.length > 0 && (
    <div data-hscroll="true" role="group" aria-label={T('Lọc theo loại sự kiện', 'Filter by event type')} data-testid="home-type-chips"
      style={{ display: 'flex', gap: 8, overflowX: 'auto', scrollbarWidth: 'none', padding: '8px 20px 0' }}>
      {typeChips.map(c => {
        const active = (homeFilters.typeFilters || []).includes(c.id);
        const n = typeCounts[c.id];
        if (!active && !n) return null;
        return (
          <button type="button" key={c.id} onClick={() => toggleTypeFilter(c.id)} aria-pressed={active}
            data-testid={`home-type-${c.id.replace(':', '-')}`}
            style={homeCapsule({ fontWeight: active ? 600 : 400, border: 'none', fontFamily: 'inherit', gap: 6, ...(simpleShell ? { minHeight: 44 } : null) }, active)}>
            {T(c.vi, c.en)}
            {!active && <span style={{ fontSize: 12, opacity: 0.6, fontVariantNumeric: 'tabular-nums' }}>{n}</span>}
          </button>
        );
      })}
    </div>
  );

  // The streak/coins capsule (Rewards on). Note 69: Simple Shell shows it beside the search bar on Going out (it was
  // only in the old header, so Rewards had no way in from Home).
  const renderRewardCapsule = () => {
            const sum = s.rewardsSummary;
            const lbl = shortcutLabels(T, sum, rewardsV2Enabled);
            const open = () => set({ screen: 'rewards', rewardsBack: 'home' });
            const key = (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open(); } };
            // 38px visual capsule; each half keeps a 44px tall tap area via vertical hit slop.
            const slop = hitSlop(HEADER.capsule);
            const btn = { display: 'flex', alignItems: 'center', justifyContent: 'center', gap: HEADER.iconGap, minWidth: HEADER.capsule - 2 * HEADER.btnPad, padding: `${slop}px ${HEADER.btnPad}px`, margin: `-${slop}px 0`, boxSizing: 'content-box', fontVariantNumeric: 'tabular-nums', fontSize: 12.5, fontWeight: 600, cursor: 'pointer', flex: 'none' };
            return (
              <div style={{ ...homeCapsule(), height: HEADER.capsule, padding: 0, gap: 0, alignItems: 'center', flex: 'none' }} data-testid="home-reward-shortcuts">
                <div onClick={open} onKeyDown={key} role="button" tabIndex={0} aria-label={lbl.streak} data-testid="home-streak" style={btn}>
                  <span aria-hidden="true" style={{ fontSize: HEADER.icon, lineHeight: 1, opacity: capStreak.value > 0 ? 1 : 0.45 }}>🔥</span>
                  <span>{capStreak.value}</span>
                </div>
                <span aria-hidden="true" style={{ width: HEADER.divider, height: 18, background: 'currentColor', opacity: 0.18 }} />
                <div onClick={open} onKeyDown={key} role="button" tabIndex={0} aria-label={lbl.coins} data-testid="home-coins" style={btn}>
                  <svg aria-hidden="true" width={HEADER.icon} height={HEADER.icon} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5v9M9.6 9.6c.5-.8 1.4-1.2 2.4-1.2 1.4 0 2.4.7 2.4 1.8 0 2.4-4.8 1.2-4.8 3.6 0 1.1 1 1.8 2.4 1.8 1 0 1.9-.4 2.4-1.2" /></svg>
                  <span>{compactCoins(sum.balance)}</span>
                </div>
              </div>
            );
  };

  const surveySection = s.user ? (
      <div style={{ padding: simpleShell ? '28px 20px 0' : '16px 20px 16px', borderTop: simpleShell ? 'none' : `1px solid ${rule}` }} data-testid="home-survey-discovery-section">
        {/* Collapse/expand pass — collapsed by default; the compact
            horizontal strip below (already the "compact cards, not a tall
            stack" shape this ticket asks for) only renders while expanded.
            `homeSurveyDiscoveryExpanded` lives in BanBeContext state, not
            local component state, so it survives Home unmounting/remounting
            around a trip into the survey modal and back. */}
        <div
          onClick={() => set({ homeSurveyDiscoveryExpanded: !s.homeSurveyDiscoveryExpanded })}
          data-testid="home-survey-discovery-toggle"
          style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', minHeight: 32 }}
        >
          <span style={{ ...display(SECTION_TITLE) }}>
            {T('Góp ý cho sự kiện sắp tới', 'Help Shape Upcoming Events')}
          </span>
          {!s.homeSurveyDiscoveryLoading && !s.homeSurveyDiscoveryError && s.homeSurveyDiscovery.length > 0 && (
            // Honest LOADED count, never a fabricated total — "+" only when
            // the server told us more exist (`hasMore`), never guessed from
            // a page-size cap.
            <span style={{ fontSize: 13, fontWeight: 600, color: ink, opacity: 0.75, background: `${ink}1a`, borderRadius: 999, padding: '2px 10px' }}>
              {s.homeSurveyDiscoveryHasMore ? `${s.homeSurveyDiscovery.length}+` : s.homeSurveyDiscovery.length}
            </span>
          )}
          <span style={{ flex: 1 }} />
          <svg width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round"
            style={{ color: ink, opacity: 0.55, transform: s.homeSurveyDiscoveryExpanded ? 'rotate(180deg)' : 'none', transition: 'transform 0.15s ease' }}>
            <path d="M6 9l6 6 6-6" />
          </svg>
        </div>
        {s.homeSurveyDiscoveryExpanded && (
        <div style={{ marginTop: 10 }}>
        {s.homeSurveyDiscoveryLoading && !s.homeSurveyDiscovery.length && (
          <div style={{ fontSize: 12, opacity: 0.6 }} data-testid="home-survey-discovery-loading">{T('Đang tải…', 'Loading…')}</div>
        )}
        {!s.homeSurveyDiscoveryLoading && s.homeSurveyDiscoveryError && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }} data-testid="home-survey-discovery-error">
            <span style={{ fontSize: 12, color: alert }}>{s.homeSurveyDiscoveryError}</span>
            <span onClick={loadHomeSurveyDiscovery} style={{ fontSize: 12, textDecoration: 'underline', cursor: 'pointer', alignSelf: 'flex-start' }}>{T('Thử lại', 'Retry')}</span>
          </div>
        )}
        {!s.homeSurveyDiscoveryLoading && !s.homeSurveyDiscoveryError && s.homeSurveyDiscovery.length === 0 && (
          <div style={{ fontSize: 12, opacity: 0.6 }} data-testid="home-survey-discovery-empty">
            {T('Chưa có khảo sát công khai nào.', 'No public surveys right now.')}
          </div>
        )}
        {s.homeSurveyDiscovery.length > 0 && (
          // Compact-vertical-list pass — replaces the previous horizontal
          // `data-hscroll` carousel entirely. Plain vertical flow inside
          // Home's own page (no nested scroll container of any kind), so
          // this never competes with the root-screen swipe gesture at
          // all — that conflict was specific to HORIZONTAL motion inside a
          // `overflowX: auto` row; a vertical list has nothing for that
          // gesture to misread.
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }} data-testid="home-survey-discovery-row">
            {s.homeSurveyDiscovery.slice(0, visibleSurveyDiscoveryCount).map(card => (
              <div
                key={card.survey_id}
                onClick={() => openSurveyStoryModal(card.public_id)}
                data-testid="home-survey-discovery-card"
                role="button"
                tabIndex={0}
                aria-label={card.closes_at
                  ? T(`Trả lời khảo sát: ${card.title}, tổ chức bởi ${card.host_name}, hạn ${new Date(card.closes_at).toLocaleDateString('vi-VN')}`,
                      `Answer survey: ${card.title}, hosted by ${card.host_name}, deadline ${new Date(card.closes_at).toLocaleDateString('vi-VN')}`)
                  : T(`Trả lời khảo sát: ${card.title}, tổ chức bởi ${card.host_name}`, `Answer survey: ${card.title}, hosted by ${card.host_name}`)}
                style={{ ...fieldGlass({ display: 'flex', alignItems: 'flex-start', gap: 10, padding: '11px 12px', borderRadius: 12, cursor: 'pointer' }) }}
              >
                {card.host_avatar_url ? (
                  <img src={card.host_avatar_url} alt="" loading="lazy" decoding="async" style={{ width: 28, height: 28, borderRadius: 999, objectFit: 'cover', flexShrink: 0 }} />
                ) : (
                  <div style={{
                    width: 28, height: 28, borderRadius: 999, background: `${ink}1a`, flexShrink: 0,
                    display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, fontWeight: 700, color: ink,
                  }}>
                    {(card.host_name || '?').charAt(0).toUpperCase()}
                  </div>
                )}
                <div style={{ minWidth: 0, flex: 1 }}>
                  <div style={{ fontSize: 13, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{card.title}</div>
                  <div style={{ fontSize: 'var(--bb-text-meta)', color: ink, opacity: 0.65, marginTop: 2, display: 'flex', alignItems: 'center', gap: 5, flexWrap: 'wrap' }}>
                    <span>{card.host_name}</span>
                    {card.closes_at && (
                      <>
                        {/* Solid small square separator — decorative, hidden
                            from accessibility, never a bullet/dash/large
                            clock glyph. */}
                        <span aria-hidden="true" style={{ width: 3, height: 3, borderRadius: 1, background: ink, opacity: 0.55, flexShrink: 0 }} />
                        <span>{T('Hạn', 'Deadline')}: {new Date(card.closes_at).toLocaleDateString('vi-VN')}</span>
                      </>
                    )}
                  </div>
                </div>
                <span aria-hidden="true" style={{ fontSize: 13, color: ink, opacity: 0.35, flexShrink: 0, marginTop: 2 }}>›</span>
              </div>
            ))}
            {(visibleSurveyDiscoveryCount < s.homeSurveyDiscovery.length || s.homeSurveyDiscoveryHasMore) && (
              <div
                onClick={revealMoreSurveyDiscovery}
                data-testid="home-survey-discovery-show-more"
                style={{ fontSize: 12, fontWeight: 600, color: ink, textAlign: 'center', cursor: 'pointer', padding: '8px 0' }}
              >
                {s.homeSurveyDiscoveryLoadingMore ? T('Đang tải…', 'Loading…') : T('Xem thêm', 'Show More')}
              </div>
            )}
          </div>
        )}
        </div>
        )}
      </div>
  ) : null;

  if (browse) {
    return (
      <Browse T={T} lang={s.lang === 'en' ? 'en' : 'vi'} scope={s.browseScope || 'all'} type={s.browseType || 'all'} query={s.browseQuery || ''}
        filters={s.browseFilters} items={browseItems || []} now={nowMs} areaLabel={areaName} shapeRow={shapeRow}
        areaKey={curArea.key} areaActive={curArea.key !== 'all'}
        onChooseArea={() => set({ areaAsking: true })} onAllAreas={() => pickArea('all')}
        accountName={s.user?.name || s.user?.email?.split('@')[0] || ''} accountAvatarUrl={s.user?.avatarUrl || ''}
        onScope={browseScopeTo}
        from={s.browseFrom || null} onBrowseTypes={() => browseTypesFrom(s.browseScope)}
        onType={(k) => setBrowse({ browseType: k })} onQuery={(q) => setBrowse({ browseQuery: q })}
        onFilters={(f) => setBrowse({ browseFilters: f ? toBrowseFilters(f) : DEFAULT_FILTERS })}
        onBack={backFromBrowse} onOpenEvent={goEvent} onOpenHost={(id) => openOrganizerProfile(id, 'browse')}
        onMap={(type) => goMapExplore({ source: 'browse', filters: { ...toBrowseFilters(s.browseFilters), cats: type && type !== 'all' ? [type] : [] } })}
        // The dock (and the "+" sheet it owns) is not mounted on this screen, so "Host a night" goes straight to the
        // shared Start hosting action: guest -> sign-in prompt, organizer mode off -> the invitation, on -> Home > Hosting.
        onHost={() => startHosting({ land: 'home' })} onToggleSave={toggleFav} onAccount={goProfile} />
    );
  }

  return (
    <>
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Home">
      {/* iOS parity header: wordmark + "Home" title + round glass search
          button, then a row of three equal glass capsules (language, area,
          theme). Search lives here again (same openEventSearch action and
          data-testid as the old floating button). */}
      {/* Pinned like iOS (HomeView's `header` sits above its ScrollView): stays put while the feed scrolls under it. */}
      {!simpleShell && (
      <div data-testid="home-fixed-header" data-reveal="0" style={{ padding: `${DOCK_HEADER.top} ${DOCK_HEADER.side}px 8px`, display: 'flex', flexDirection: 'column', gap: 10, position: 'sticky', top: 0, zIndex: 6, background: paper }}>
        <div ref={headerRef} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', height: DOCK_HEADER.rowHeight }}>
          {/* Note 53: the shared dock header — same logo, gap, title and row height as Schedule/Messages/Account. */}
          <DockHeaderTitle title={T('Nhà', 'Home')} testId="home-title" wordmark={layout.wordmark} showTitle={simpleShell ? false : showTitle} />
          <div style={{ display: 'flex', alignItems: 'center', gap: HEADER.groupGap, flex: 'none' }} data-testid="home-header-actions">
          {/* Simple Shell: the mode switch takes the capsule's place here; the capsule sits beside the search bar. */}
          {simpleShell && <HomeModeSwitch />}
          {!simpleShell && shortcutsOn && renderRewardCapsule()}
          {/* Note 44 web parity: Notifications left the dock (Schedule took its slot), so its bell lives here. */}
          <button
            type="button"
            // Remembers where the bell is so Notifications can burst out of it (src/lib/bellOrigin.js).
            onClick={(e) => { setBellOrigin(e.currentTarget.getBoundingClientRect()); goNotifications(); }}
            data-testid="home-notifications"
            aria-label={s.unreadNotifications ? T(`Thông báo, ${s.unreadNotifications} chưa đọc`, `Notifications, ${s.unreadNotifications} unread`) : T('Thông báo', 'Notifications')}
            // 44px transparent tap target (negative margin: takes only 36px of layout) around a 36px glass circle.
            style={{ position: 'relative', width: HEADER.minTouch, height: HEADER.minTouch, margin: -hitSlop(HEADER.bell), padding: 0, border: 'none', background: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', color: ink, cursor: 'pointer', fontFamily: 'inherit' }}
          >
            <span aria-hidden="true" style={{ ...homeCapsule(), width: HEADER.bell, height: HEADER.bell, borderRadius: '50%', padding: 0, justifyContent: 'center' }}>
            <svg aria-hidden="true" width={17} height={17} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 3.5c-2.8 0-5 2.2-5 5v4.6l-1.6 2.7c-.3.5.1 1.2.7 1.2h11.8c.6 0 1-.7.7-1.2L17 13.1V8.5c0-2.8-2.2-5-5-5z" />
              <path d="M9.6 18.6a2.4 2.4 0 0 0 4.8 0" />
            </svg>
            </span>
            {s.unreadNotifications > 0 && (
              <span aria-hidden="true" data-testid="home-notifications-badge" style={{ position: 'absolute', top: 2, right: 2, minWidth: 16, height: 16, borderRadius: 8, padding: '0 4px', boxSizing: 'border-box', background: 'var(--bb-alert)', color: 'var(--bb-on-alert)', fontSize: 'var(--bb-text-meta)', fontWeight: 700, lineHeight: '16px', textAlign: 'center' }}>
                {s.unreadNotifications > 9 ? '9+' : s.unreadNotifications}
              </span>
            )}
          </button>
          </div>
        </div>
        {/* Note 50: language + theme live in Settings > Language & Appearance; the area menu is a location pill
            ("Deliver to"-style) and the full-width search bar takes the slot "Your events" used to fill. */}
        {/* Simple Shell: area moves into the search bar; language + theme stay in Settings and Welcome. */}
        {!simpleShell && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, minWidth: 0 }}>
        <button type="button" onClick={openAreaMenu} aria-haspopup="menu" data-testid="home-area-toggle"
          style={{ ...quickToggle, flex: '0 1 auto', minWidth: 0 }}>
          <svg aria-hidden="true" width={15} height={15} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ flex: 'none' }}><path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z" /><circle cx="12" cy="9.5" r="2.5" /></svg>
          <span style={{ opacity: 0.6, fontWeight: 500, flex: 'none' }}>{T('Gần', 'Near')}</span>
          <span style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{areaName}</span>
          <span aria-hidden="true" style={{ fontSize: 'var(--bb-text-meta)', marginLeft: 2, flex: 'none' }}>▾</span>
        </button>
        {/* Quick language + light/dark switch, same plain-text style as the location pill and right beside it.
            Each shows what a tap switches TO (same convention the old capsules used). */}
        <button type="button" onClick={toggleLang} data-testid="home-lang-toggle" style={quickToggle}
          aria-label={T('Chuyển sang English', 'Switch to Vietnamese')}>
          <svg aria-hidden="true" width={15} height={15} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3c2.6 2.8 3.9 5.8 3.9 9s-1.3 6.2-3.9 9c-2.6-2.8-3.9-5.8-3.9-9S9.4 5.8 12 3z" /></svg>
          {T('EN', 'VN')}
        </button>
        <button type="button" onClick={toggleTheme} data-testid="home-theme-toggle" style={quickToggle}
          aria-label={resolvedTheme === 'dark' ? T('Chuyển sang giao diện sáng', 'Switch to light mode') : T('Chuyển sang giao diện tối', 'Switch to dark mode')}>
          {resolvedTheme === 'dark'
            ? <svg aria-hidden="true" width={15} height={15} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="4" /><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6 7 7M17 17l1.4 1.4M5.6 18.4 7 17M17 7l1.4-1.4" /></svg>
            : <svg aria-hidden="true" width={15} height={15} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z" /></svg>}
          {resolvedTheme === 'dark' ? T('Sáng', 'Light') : T('Tối', 'Dark')}
        </button>
        </div>
        )}
        {/* A little breathing room under the search bar, like Map's own search field (iOS: 12pt). */}
        {!hostView && (
          <div style={{ marginBottom: 4, opacity: s.searchOverlayOpen ? 0 : 1 }}>
            {simpleShell
              ? (
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <HomeSearchBar onOpen={openSearch} T={T} areaLabel={areaName} onArea={openAreaMenu} everywhere={curArea.key === 'all'} />
                  </div>
                  {shortcutsOn && renderRewardCapsule()}
                </div>
              )
              : <HomeSearchBar onOpen={openSearch} T={T} />}
          </div>
        )}
      </div>
      )}
      {simpleShell ? (
        <>
        <HomeShellV5 T={T} lang={s.lang === 'en' ? 'en' : 'vi'} tab={hostView ? 'hosting' : curTab} canHost={!!s.user}
          onTab={(k) => {
            if (k === 'hosting') { if (!s.organizerMode) { if (!s.organizerModeBusy) startHosting({ land: 'home' }); } else if (!hostView) setHomeView('host'); return; }
            if (hostView) setHomeView('goer');
            if (ud) setHomeFilters(prev => ({ ...prev, date: DATE_FOR_TAB[k] || 'any' })); else setHeroTab(k);
          }}
          onReturnToEvents={returnToEvents}
          lists={heroLists} items={shownItems} user={s.user} typeCounts={shellTypeCounts} badgeDate={badgeDate} trStatus={trStatus}
          dateLabel={new Date().toLocaleDateString(s.lang === 'en' ? 'en-GB' : 'vi-VN', { weekday: 'long', day: 'numeric', month: 'long' })}
          areaLabel={areaName} areaActive={curArea.key !== 'all'}
          filtersActive={filterBadge > 0 || curArea.key !== 'all'} hasPrefs={!!s.eventPrefs && !prefsIsEmpty(s.eventPrefs)}
          onClearFilters={() => { clearFilters(); set({ homeSort: 'soonest' }); }}
          onOpenEvent={goEvent} onToggleSave={toggleFav} onSeeAll={heroSeeAll} onAccount={() => setQuickOpen(true)}
          onSearch={openSearch} onArea={openAreaMenu} onMap={openMapWithContext} onFilters={() => set({ homeFilterSheetOpen: true })} filterSummary={shellFilterSummary}
          onFindType={() => setCategorySheetOpen(true)} onPickType={shellPickType}
          onSetPrefs={() => openEventPreferences('home')}
          // "Browse all events" opens the every-event list itself (owner 2026-11-18): it used to scroll Home down to
          // the By type section, which only ever held a handful of events, never all of them.
          onBrowseAll={() => { if (ud) { scrollToNearby(); return; } browseTypesFrom(curTab); }}
          hostBody={<div data-reveal="1"><HostHome /><div style={{ height: 44 }} /></div>} below={surveySection}
          seeAll={v23 && curTab !== 'hosting' ? { count: tabItems(curTab).length, label: TAB_LABEL[curTab] } : null}
          searchActive={!!udQuery}
          unifiedChrome={ud}
          unifiedBrowse={ud ? (
            <UnifiedTypeGrid counts={shellTypeCounts} selected={homeFilters.cats?.[0] || null} total={categoryCountMap.all ?? shownItems.length}
              onPick={(k) => pickFilter(homeFilters.cats?.[0] === k ? 'all' : k)} onClear={() => pickFilter('all')}
              onOpenSheet={() => setTypeSheetOpen(true)} T={T} />
          ) : null}
          onBrowseType={v23 ? (k) => { if (ud) { pickFilter(k); return; } openBrowse({ type: k, scope: 'all' }); } : null}
          browseTotal={v23 ? applyDiscoveryFilters(discoveryItems, DEFAULT_FILTERS, nowMs).filter(it => !it.ev.cancelled).length : null}
          shortlist={shortlist && (
            <div data-reveal="2">
              <ShortlistV23 T={T} lang={s.lang === 'en' ? 'en' : 'vi'} rows={shortlist.rows} total={shortlist.total}
                filterBadge={ud ? udOwned : filterBadge} onFilters={() => set({ homeFilterSheetOpen: true })} onOpenEvent={goEvent} onAction={onShortlistAction}
                onToggleSave={toggleFav} />
              {ud && shortlist.rows.length > 0 && (
                <UnifiedMapBanner count={shortlist.rows.length} areaLabel={curArea.key !== 'all' ? areaName : ''} onOpen={openMapWithContext} T={T} />
              )}
              <p style={{ margin: '28px 0 0', textAlign: 'center', fontSize: 12, color: 'var(--bb-fg-3)' }}>
                banbe · {T('chọn một buổi, gặp vài người', 'pick an evening, meet a few people')}
              </p>
            </div>
          )}>
          <div data-reveal="1" data-testid="home-hero" data-hero={goerHero}>
            {nextUpItems.length > 0 && <NextUpV23 items={nextUpItems} onAction={onNextUp} onSchedule={goSchedule} T={T} />}
            {goerHero === 'nextUp' && !nextUpItems.length && (
              <NextUpBanner item={nextUp && { ...nextUp, when: nextUp.status }} onOpen={() => openSaved(nextUp)} T={T}
                onShowTicket={nextUpTicket ? () => openBookingConfirmed(nextUpTicket.id, nextUpTicket.event_id, 'home') : null} />
            )}
            {goerHero === 'action' && <ActionCenter items={actionItems} onSeeAll={goNotifications} T={T} />}
            {goerHero === 'checklist' && <ActivationChecklistCard />}
            {goerHero === 'guest' && <GuestBrowseBanner />}
            {goerHero === 'none' && savedUpcomingEl}
            {/* Prototype v2 order: the live line and the shared-state bar sit between the hero and Browse by type. */}
            <LiveLine updates={live} index={Math.min(liveIndex, Math.max(0, live.length - 1))} onIndex={setLiveIndex} onOpen={() => setLiveOpen(true)} T={T} />
            {ud && shortlist && (udQuery || udOwned > 0) && (
              <UnifiedStateBar parts={udParts} count={shortlist.rows.length} onMap={openMapWithContext} onClear={clearUnified} T={T} />
            )}
          </div>
        </HomeShellV5>
        {quickOpen && <QuickSheetV5 onClose={() => setQuickOpen(false)} />}
        {ud && typeSheetOpen && (
          <UnifiedTypeSheet counts={shellTypeCounts} total={categoryCountMap.all ?? shownItems.length} selected={homeFilters.cats?.[0] || null} T={T}
            onPick={(k) => { pickFilter(k); setTypeSheetOpen(false); }} onClose={() => setTypeSheetOpen(false)} />
        )}
        {liveOpen && live.length > 0 && (
          <LiveNowSheet updates={live} shownIndex={reducedMotion ? liveIndex : null} T={T} onClose={() => setLiveOpen(false)}
            onOpenEvent={(id, i) => { setLiveIndex(i); goEvent(id); }} />
        )}
        {categorySheetOpen && (
          <CategorySheet keys={categorySheetKeys(categoryDefs(), s.lang === 'en' ? 'en' : 'vi')} counts={categoryCountMap} values={homeFilters.cats} T={T}
            onPick={(k) => { shellPickType(k); setCategorySheetOpen(false); }} onClose={() => setCategorySheetOpen(false)} />
        )}
        </>
      ) : hostView ? (
        <div data-reveal="1"><HostHome /><div style={{ height: 44 }} /></div>
      ) : (
      <>
      {/* Note 64: regions 1 and 2 are the sign-in reveal order (header 0, summary 1, feed 2, dock 3). Plain block
          wrappers, so layout is unchanged; they only animate while <html data-reveal="1">. */}
      {simpleShell ? (
        <>
        <div data-reveal="1" data-testid="home-hero" data-hero={goerHero}>
          {goerHero === 'nextUp' && (
            <NextUpBanner item={nextUp && { ...nextUp, when: nextUp.status }} onOpen={() => openSaved(nextUp)} T={T}
              onShowTicket={nextUpTicket ? () => openBookingConfirmed(nextUpTicket.id, nextUpTicket.event_id, 'home') : null} />
          )}
          {goerHero === 'action' && <ActionCenter items={actionItems} onSeeAll={goNotifications} T={T} />}
          {goerHero === 'checklist' && <ActivationChecklistCard />}
          {goerHero === 'guest' && <GuestBrowseBanner />}
          {goerHero === 'none' && savedUpcomingEl}
        </div>
        </>
      ) : (
      <div data-reveal="1">
      {/* First thing in the scrolling feed, like iOS (PulseTickerView at the top of the LazyVStack). */}
      {pulseTicker}

      {/* TASK A (2026-10-01 UX foundation pass) — replaces the old fixed
          four-banner block: one unified, priority-sorted, 3-card-capped
          Action Center covering both roles this account can hold. See
          src/lib/actionCenter.js for the source list and ordering rule. */}
      <NextUpBanner item={nextUp && { ...nextUp, when: nextUp.status }} onOpen={() => openSaved(nextUp)} T={T}
        onShowTicket={nextUpTicket ? () => openBookingConfirmed(nextUpTicket.id, nextUpTicket.event_id, 'home') : null} />

      {savedUpcomingEl}

      {/* Note 49: a guest sees a sign-in banner instead of the personal Action Center / checklist. */}
      {s.user ? (
        <>
          <ActionCenter items={actionItems} onSeeAll={goNotifications} T={T} />
          <ActivationChecklistCard />
        </>
      ) : <GuestBrowseBanner />}

      {storyRow}

      </div>
      )}

      <div data-reveal="2">
      {/* Note 66 follow-up: the category row and its "Show all" A-Z sheet are back on the Simple Shell path too (one
          compact row under the hero, then the type chips, then the chip row). Same counts/order as before. */}
      <CategoryRow values={homeFilters.cats} onPick={pickFilter} T={T} keys={categoryRow} counts={categoryCountMap}
        onShowAll={() => setCategorySheetOpen(true)} compact={simpleShell} />
      {categorySheetOpen && (
        <CategorySheet keys={categorySheetKeys(categoryDefs(), s.lang === 'en' ? 'en' : 'vi')} counts={categoryCountMap} values={homeFilters.cats} T={T}
          onPick={(k) => { pickFilter(k); setCategorySheetOpen(false); }} onClose={() => setCategorySheetOpen(false)} />
      )}
      {simpleShell && typeChipRow}
      {!simpleShell && (<>

      {/* Quick row: Filters + Sort open the sheet; For You stays pinned at the leading edge (notes 34/36); the
          one-tap chips scroll (data-hscroll so the root tab swipe ignores them). */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '10px 0 6px', paddingInlineStart: 20 }}>
        <button type="button" onClick={() => set({ homeFilterSheetOpen: true })} data-testid="home-filters-button"
          aria-label={filterBadge ? T(`Bộ lọc, ${filterBadge} đang bật`, `Filters, ${filterBadge} on`) : T('Bộ lọc', 'Filters')}
          style={{ ...homeCapsule({ padding: '0 12px', gap: 6, position: 'relative', border: 'none', fontFamily: 'inherit' }, filterBadge > 0) }}>
          <svg aria-hidden="true" width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round"><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></svg>
          {filterBadge > 0 && <span data-testid="home-filters-badge" style={{ fontSize: 12, fontWeight: 700 }}>{filterBadge}</span>}
        </button>
        <button type="button" data-testid="home-sort-button" aria-haspopup="menu"
          onClick={(e) => {
            // Same anchoring as the location pill (see its comment): coordinates inside the phone frame.
            const r = e.currentTarget.getBoundingClientRect();
            const frame = e.currentTarget.closest('.bb-screen')?.getBoundingClientRect();
            const inFrame = frame && frame.width > 0;
            setSortMenuAnchor({ left: r.left - (inFrame ? frame.left : 0), bottom: r.bottom - (inFrame ? frame.top : 0), width: inFrame ? frame.width : window.innerWidth });
          }}
          aria-label={T(`Sắp xếp: ${SORT_LABELS[s.homeSort || 'soonest'][0]}`, `Sort: ${SORT_LABELS[s.homeSort || 'soonest'][1]}`)}
          style={{ ...homeCapsule({ padding: '0 12px', border: 'none', fontFamily: 'inherit' }, sortActive) }}>
          <svg aria-hidden="true" width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d="M7 4v16M3.5 16.5 7 20l3.5-3.5M17 20V4M13.5 7.5 17 4l3.5 3.5" /></svg>
        </button>
        {hasForYou && (
          <ForYouChip
            T={T}
            active={!!s.filterForYou}
            pending={forYouAlert.pending}
            animate={forYouAlert.animate}
            capsuleStyle={homeCapsule({ fontWeight: s.filterForYou ? 600 : 400 }, !!s.filterForYou)}
            title={forYouIntent?.goal ? forYouIntent : null}
            onClick={() => {
              if (!s.filterForYou) forYouAlert.acknowledge(forYouRanked.map(m => m.key));
              toggleHomeFilter('forYou');
            }}
          />
        )}
        <div data-hscroll="true" data-testid="home-filter-extra-scroller" style={{ flex: '1 1 0', minWidth: 0, display: 'flex', gap: 8, overflowX: 'auto', scrollbarWidth: 'none', paddingInlineEnd: 20 }}>
          {QUICK_CHIPS.map(c => {
            const active = c.on(homeFilters);
            const n = quickCounts[c.key];
            if (!active && !n) return null;
            return (
              <button type="button" key={c.key} onClick={() => setHomeFilters(c.apply)} aria-pressed={active}
                data-testid={`home-quick-${c.key.toLowerCase()}`}
                style={homeCapsule({ fontWeight: active ? 600 : 400, border: 'none', fontFamily: 'inherit', gap: 6 }, active)}>
                {T(c.vi, c.en)}
                {!active && <span style={{ fontSize: 12, opacity: 0.6, fontVariantNumeric: 'tabular-nums' }}>{n}</span>}
              </button>
            );
          })}
        </div>
      </div>
      {typeChipRow}
      </>)}
      {simpleShell && (
        // Simple Shell: ONE chip row. For You first, the one-tap chips, then Filters (Sort and the rest live in the
        // sheet; categories and type chips are the rows above). The middle scrolls (data-hscroll so the root tab swipe ignores it).
        <div data-testid="home-chip-row" style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '12px 0 6px', paddingInlineStart: 20 }}>
          {hasForYou && (
            <ForYouChip
              T={T}
              active={!!s.filterForYou}
              pending={forYouAlert.pending}
              animate={forYouAlert.animate}
              capsuleStyle={homeCapsule({ fontWeight: s.filterForYou ? 600 : 400, minHeight: 44 }, !!s.filterForYou)}
              title={forYouIntent?.goal ? forYouIntent : null}
              onClick={() => {
                if (!s.filterForYou) forYouAlert.acknowledge(forYouRanked.map(m => m.key));
                toggleHomeFilter('forYou');
              }}
            />
          )}
          <div data-hscroll="true" data-testid="home-filter-extra-scroller" style={{ flex: '1 1 0', minWidth: 0, display: 'flex', gap: 8, overflowX: 'auto', scrollbarWidth: 'none' }}>
            {QUICK_CHIPS.map(c => {
              const active = c.on(homeFilters);
              const n = quickCounts[c.key];
              if (!active && !n) return null;
              return (
                <button type="button" key={c.key} onClick={() => setHomeFilters(c.apply)} aria-pressed={active}
                  data-testid={`home-quick-${c.key.toLowerCase()}`}
                  style={homeCapsule({ fontWeight: active ? 600 : 400, border: 'none', fontFamily: 'inherit', gap: 6, minHeight: 44 }, active)}>
                  {T(c.vi, c.en)}
                  {!active && <span style={{ fontSize: 12, opacity: 0.6, fontVariantNumeric: 'tabular-nums' }}>{n}</span>}
                </button>
              );
            })}
          </div>
          <button type="button" onClick={() => set({ homeFilterSheetOpen: true })} data-testid="home-filters-button"
            aria-label={simpleFilterBadge ? T(`Bộ lọc, ${simpleFilterBadge} đang bật`, `Filters, ${simpleFilterBadge} on`) : T('Bộ lọc', 'Filters')}
            style={{ ...homeCapsule({ padding: '0 12px', gap: 6, position: 'relative', border: 'none', fontFamily: 'inherit', minHeight: 44, marginInlineEnd: 20 }, simpleFilterBadge > 0) }}>
            <svg aria-hidden="true" width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round"><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></svg>
            {simpleFilterBadge > 0 && <span data-testid="home-filters-badge" style={{ fontSize: 12, fontWeight: 700 }}>{simpleFilterBadge}</span>}
          </button>
        </div>
      )}
      {forYouActive && (
        <div style={{ padding: '0 20px 4px' }}>
          {forYouWhy && <div data-testid="home-foryou-why" style={{ fontSize: 13, opacity: 0.75, marginBottom: 4 }}>{forYouWhy}</div>}
          <span
            onClick={() => openEventPreferences('home')}
            data-testid="home-foryou-edit-answers"
            role="button"
            style={{ fontSize: 12.5, fontWeight: 600, textDecoration: 'underline', cursor: 'pointer' }}
          >
            {T('Chỉnh câu trả lời của bạn', 'Edit my answers')}
          </span>
        </div>
      )}

      {/* Section header: what you're looking through, and a cards/list switch (no single default suits everyone). */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 20px 12px' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, minWidth: 0 }}>
          <span style={{ ...display(SECTION_TITLE), whiteSpace: 'nowrap' }}>
            {homeFilters.date !== 'any' && DATE_LABELS[homeFilters.date] ? T(...DATE_LABELS[homeFilters.date]) : forYouActive ? (forYouIntent?.goal ? T(forYouIntent.vi, forYouIntent.en) : T('Dành cho bạn', 'For you')) : T('Sắp diễn ra', 'Upcoming')}
          </span>
          <span data-testid="home-result-count" data-count={shownItems.length} style={{ fontSize: 13, opacity: 0.6, whiteSpace: 'nowrap', ...(simpleShell ? { color: ink } : null) }}>
            {T(`${shownItems.length} sự kiện`, `${shownItems.length} event${shownItems.length === 1 ? '' : 's'}`)}
          </span>
        </div>
        <div role="radiogroup" aria-label={T('Kiểu hiển thị', 'Layout')} style={{ display: 'flex', gap: 2, padding: 2, borderRadius: 999, background: 'rgba(var(--bb-fg-rgb),0.06)' }}>
          {[['cards', T('Thẻ', 'Cards'), 'M4 4h16v7H4zM4 13h16v7H4z'], ['list', T('Danh sách', 'List'), 'M4 6h16M4 12h16M4 18h16'],
            // Simple Shell: Map is a Home view (it left the dock); this opens the map screen, which keeps its own state.
            ...(simpleShell ? [['map', T('Bản đồ', 'Map'), 'M9 4 3 6.5v13.5l6-2.5 6 2.5 6-2.5V4l-6 2.5L9 4zM9 4v13.5M15 6.5V20']] : [])].map(([m, lbl, d]) => (
            <button key={m} type="button" role="radio" aria-checked={layoutMode === m} aria-label={lbl} onClick={() => (m === 'map' ? openMapWithContext() : pickLayout(m))} data-testid={`home-layout-${m}`}
              style={{ width: 34, height: 30, borderRadius: 999, border: 'none', cursor: 'pointer', color: ink, display: 'flex', alignItems: 'center', justifyContent: 'center',
                background: layoutMode === m ? 'var(--bb-bg)' : 'transparent', boxShadow: layoutMode === m ? '0 1px 3px rgba(27,25,22,0.18)' : 'none' }}>
              <svg aria-hidden="true" width={15} height={15} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d={d} /></svg>
            </button>
          ))}
        </div>
      </div>

      {cards.map((ev, i) => {
        const card = layoutMode === 'list'
          ? <DiscoveryRow key={ev.key} ev={ev} onOpen={() => goEvent(ev.key)} T={T} />
          : <DiscoveryCard key={ev.key} ev={ev} onOpen={() => goEvent(ev.key)} onToggleSave={() => toggleFav(ev.key)} T={T} filled={simpleShell} polaroid={polaroidCards} />;
        if (!simpleShell) return card;
        // Simple Shell: stories (only if any) after the 3rd card, the Pulse ticker (only with items) after the 6th.
        // Fewer cards than that: they follow the last card.
        const out = [card];
        if (storyRow && i === Math.min(2, cards.length - 1)) out.push(<div key="home-stories-slot" style={{ paddingBottom: 14 }}>{storyRow}</div>);
        if (hasPulse && i === Math.min(5, cards.length - 1)) out.push(<div key="home-pulse-slot" style={{ paddingBottom: 18 }}>{pulseTicker}</div>);
        return out.length > 1 ? out : card;
      })}
      {simpleShell && cards.length === 0 && storyRow}

      {/* Requirements are soft: when filters leave almost nothing, offer the one change that adds the most. */}
      {relaxHints.length > 0 && feed.length > 0 && (
        <div data-testid="home-relax-hints" style={{ display: 'flex', flexWrap: 'wrap', gap: 8, padding: '4px 20px 18px' }}>
          {relaxHints.map(h => (
            <button key={h.id} type="button" onClick={() => setHomeFilters(h.filters)} data-testid={`home-relax-${h.id}`}
              style={homeCapsule({ border: 'none', fontFamily: 'inherit', fontWeight: 600 })}>
              {T(`+${h.gain} sự kiện nếu ${RELAX_LABELS[h.id][0]}`, `+${h.gain} event${h.gain === 1 ? '' : 's'} with ${RELAX_LABELS[h.id][1]}`)}
            </button>
          ))}
        </div>
      )}

      {cards.length === 0 && forYouActive && (
        <div style={{ padding: '20px 0 30px' }}>
          {/* Calm Pass phase 2: For You plus other filters left nothing. Say it is the combination, not "no events". */}
          <EmptyState scene="findPlans" testId="home-empty-foryou"
            title={T('Chưa có sự kiện khớp lựa chọn của bạn', 'No events match your picks yet')}
            message={T('Các bộ lọc khác đang thu hẹp kết quả Dành cho bạn. Xem tất cả, hoặc chỉnh sở thích của bạn.', 'Your other filters narrow For You down to nothing. See everything, or change what you like.')}
            actionLabel={T('Xem tất cả sự kiện', 'See all events')} actionTestId="home-empty-foryou-see-all"
            onAction={() => { clearFilters(); set({ filterForYou: false, homeSort: 'soonest' }); }}
            secondaryLabel={T('Chỉnh sở thích', 'Edit my picks')} secondaryTestId="home-empty-foryou-prefs" onSecondary={() => openEventPreferences('home')} />
        </div>
      )}

      {cards.length === 0 && !forYouActive && (
        <div style={{ padding: '20px 0 30px' }}>
          {/* Note 48 (iOS parity): a cute scene + one clear next step instead of a bare line. */}
          <EmptyState scene="findPlans" testId="home-empty"
            title={T('Tuần này hơi yên ắng…', 'A quiet week here…')}
            message={curArea.key === 'all'
              ? T('Chưa có buổi nào khớp bộ lọc này. Bỏ lọc để xem mọi buổi vui tuần này nhé!', 'Nothing matches these filters yet. Clear them to see every fun gathering this week!')
              : T(`Chưa có buổi nào ở ${curArea.label} khớp bộ lọc. Xem tất cả hoặc mở bản đồ để tìm quanh bạn nhé!`, `Nothing in ${curArea.label} matches these filters yet. See everything, or open the map to look around you!`)}
            actionLabel={T('Xem tất cả sự kiện', 'See all events')} actionTestId="home-empty-see-all" onAction={() => { clearFilters(); set({ homeSort: 'soonest' }); }}
            secondaryLabel={T('Tìm trên bản đồ', 'Look on the map')} secondaryTestId="home-empty-map" onSecondary={openMapWithContext} />
        </div>
      )}

      {cards.length > 0 && (
        <div style={{ padding: '34px 20px 6px', textAlign: 'center', borderTop: `1px solid ${rule}` }}>
          <p style={{ ...display(11.5, { margin: 0 }) }}>{T('Hết rồi, ra ngoài chơi thôi!', "That's it, go have fun!")}</p>
        </div>
      )}

      {/* Retention roadmap P1 ("Cuối tuần này") — real live+public events
          for the applicable weekend (see loadWeekendEvents), never demo
          cards. Placed after the main feed (not the "Sự kiện của bạn"
          strip near the top) on purpose: it's a discovery section, not a
          personal one, and keeping the main feed's own card markup first
          in the DOM avoids collisions with generic "first card containing
          this event's name" test/query patterns already written against
          it. Suppressed during the very first load (list still empty AND
          still loading) so it never flashes the empty state for an
          instant before real data arrives — same "no false state on
          initial load" bar Stage 1's favorites work already holds to. */}
      {homeFilters.date !== 'weekend' && !(s.weekendEventsLoading && weekendList.length === 0) && (
        <div ref={weekendRef} data-testid="home-weekend-section" style={{ scrollMarginTop: 72, padding: '16px 20px 4px', borderTop: `1px solid ${rule}` }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
            <span style={{ ...display(SECTION_TITLE) }}>{T('Cuối tuần này', 'This weekend')}</span>
          </div>
          {weekendList.length > 0 ? (
            <div data-hscroll="true" style={{ display: 'flex', gap: 10, overflowX: 'auto', paddingBottom: 10 }}>
              {weekendList.map(e => (
                <div key={e.key} data-testid={`weekend-event-${e.key}`} data-zoom-src={e.key} onClick={() => goEvent(e.key)} style={{ flex: 'none', width: 168, cursor: 'pointer' }}>
                  <div style={{ position: 'relative' }}>
                    {e.photoUrl ? (
                      <div style={bg(e.photoUrl, { width: 168, height: 110 })} />
                    ) : (
                      // Honest placeholder — never a static demo photo
                      // standing in for a real one (roadmap's own rule).
                      <div style={{ ...cardGlass({ width: 168, height: 110 }), display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                        <span style={{ fontSize: 'var(--bb-text-meta)', color: ink, opacity: 0.55 }}>{T('Chưa có ảnh', 'No photo yet')}</span>
                      </div>
                    )}
                    <span
                      onClick={(ev) => { ev.stopPropagation(); toggleFav(e.key); }}
                      data-testid={`weekend-save-${e.key}`}
                      style={e.saved ? photoChip(CHIP_COLORS.going, { top: 6, right: 6, fontSize: 'var(--bb-text-meta)', padding: '4px 8px', borderRadius: 12 }) : lightChip({ top: 6, right: 6, fontSize: 'var(--bb-text-meta)', padding: '4px 8px', borderRadius: 12 })}
                    >
                      {e.saved ? T('Đã lưu', 'Saved') : T('Lưu', 'Save')}
                    </span>
                    {e.soldOut && (
                      <span style={photoChip(CHIP_COLORS.cancelled, { bottom: 6, left: 6, fontSize: 'var(--bb-text-meta)', padding: '4px 8px', borderRadius: 12 })}>{T('Hết chỗ', 'Sold out')}</span>
                    )}
                  </div>
                  <div style={{ ...display(14, { marginTop: 7, lineHeight: 1.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</div>
                  <div style={{ fontSize: 'var(--bb-text-meta)', color: ink, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{trStatus(e.when)}{e.area ? ' ▪︎ ' + e.area : ''}</div>
                  <div style={{ fontSize: 'var(--bb-text-meta)', color: ink, marginTop: 1, display: 'flex', justifyContent: 'space-between', gap: 6 }}>
                    <span>{e.priceDisplay}</span>
                    <span>{e.seatsDisplay}</span>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p data-testid="weekend-empty" style={{ fontSize: 12.5, color: ink, opacity: 0.7, padding: '4px 0 12px' }}>
              {T('Chưa có sự kiện phù hợp cuối tuần này.', 'No matching events this weekend yet.')}
            </p>
          )}
        </div>
      )}

      {/* Section 5 — public survey-story discovery, independent of follow
          status (s.homeSurveyDiscovery is built that way in
          loadHomeStories()'s own comment — never mixed into the
          follow-gated ring row above). Tapping a card opens the same
          in-app response modal a story's own "Answer Survey" CTA does.
          Visibility-investigation fix — this section is now ALWAYS
          rendered (title + one of loading/error/empty/cards), not only
          when cards already exist, so a real load failure is never
          indistinguishable from the section simply not existing — "never
          silently treat query/decode errors as an empty discovery feed."
          Deduplication is handled server-side in loadHomeStories() (one
          card per organizer, deduped by survey_id first — see that
          function's own comment); `card.survey_id` as the React key is the
          same dedup key, so a render-level duplicate is structurally
          impossible here too. */}
      {/* Note 49: surveys need an account (the discovery RPC is authenticated-only) — hidden for a guest. */}
      {surveySection}

      <div style={{ padding: '6px 20px 8px', fontSize: 'var(--bb-text-meta)', color: ink }}>
        {T('Vài buổi vui dành cho riêng bạn tuần này. Không xếp hạng, không quảng cáo, không lướt vô tận.', 'A few fun gatherings made just for you this week. No ratings, no ads, no endless scrolling.')}
      </div>
      {/* Simple Shell: hosting is one tap away in the header's mode switch, so this link only shows with the switch off. */}
      {simpleShell ? <div style={{ height: 40 }} /> : (
        <div onClick={homeHostLink} style={{ padding: '4px 20px 44px', fontSize: 14.5, fontWeight: 600, letterSpacing: '-0.01em', color: ink, cursor: 'pointer' }}>{homeHostLinkLabel} ›</div>
      )}
      </div>
      </>
      )}
    </div>
    {sortMenuAnchor && (
      <SortMenu
        anchor={sortMenuAnchor} value={s.homeSort || 'soonest'} T={T}
        canSortNearest={!!(located && s.userCoords)}
        onPick={(m) => { set({ homeSort: m }); setSortMenuAnchor(null); }}
        onAskLocation={() => { setSortMenuAnchor(null); allowLocation(); }}
        onClose={() => setSortMenuAnchor(null)}
      />
    )}
    {s.homeFilterSheetOpen && (
      <HomeFilterSheet
        items={discoveryItems} filters={homeFilters} sort={s.homeSort} now={nowMs} T={T}
        canSortNearest={!!(located && s.userCoords)}
        unified={ud}
        areaLabel={curArea.key === 'all' ? '' : curArea.label}
        forYou={hasForYou ? { on: !!s.filterForYou, set: (v) => set({ filterForYou: v }) } : null}
        onClose={() => set({ homeFilterSheetOpen: false })}
        onApply={(f, sort) => { setHomeFilters(f); set({ homeFilterSheetOpen: false, homeSort: sort }); }}
        {...(simpleShell ? { simpleShell: true } : {})}
      />
    )}
    </>
  );
}

