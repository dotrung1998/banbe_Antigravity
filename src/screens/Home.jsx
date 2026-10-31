import { glassCapsuleInactive } from '../lib/glassOpacity.js';
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { EVENTS, bg, agoLabel, haversineKm, catalogStartMs } from '../data/events.js';
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
import { formatMoney, zonedParts } from '../lib/eventMarket.js';
import ActionCenter from './ActionCenter.jsx';
import ActivationChecklistCard from './ActivationChecklistCard.jsx';
import { GuestBrowseBanner } from './GuestPromptSheet.jsx';
import EmptyState from '../components/ui/EmptyState.jsx';
import { CategoryRow, CategorySheet, HomeSearchBar, DiscoveryCard, DiscoveryRow, NextUpBanner } from '../components/home/HomeDiscoveryParts.jsx';
import HomeFilterSheet, { DATE_LABELS, RELAX_LABELS, SORT_LABELS } from './sheets/HomeFilterSheet.jsx';
import SortMenu from './sheets/SortMenu.jsx';
import PulseTicker from '../components/home/PulseTicker.jsx';
import { setBellOrigin } from '../lib/bellOrigin.js';
import { supabase } from '../lib/supabase.js';
import { savedComingUp, fillText, whenLabel } from '../lib/quickWins.js';
import { rowTimeZone } from '../lib/eventMarket.js';
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


export default function Home() {
  const {
    state, set, T, trStatus, stripKm, curArea, isSaved, isGoing, toggleFav,
    goEvent, pickFilter, clearFilters, toggleHomeFilter, goMapExplore, toggleLang, toggleTheme,
    becomeHost, switchToHost,
    canHost, loadPaymentBookings, loadVerifications, loadOrganizerHoldingSummary, loadHomeLiveEvents,
    openPaymentDetails, openVerifications, goDashboard, forfeitExpiredHold,
    loadHomeStories, openStoryViewer, openSurveyStoryModal,
    loadMyRefunds, openMyRefunds, loadRefundQueue, goNotifications,
    loadMyAdminInvite, openAccountGroup,
    openPulseViewer, loadWeekendEvents, loadDiscoveryEvents, loadRealEventsById, loadPulse,
    loadHomeSurveyDiscovery, loadMoreHomeSurveyDiscovery, openEventPreferences,
    openSearch, setHomeFilters, located, allowLocation, rewardsEnabled, rewardsV2Enabled, openBookingConfirmed,
    resolvedTheme,
  } = useBanBe();

  const s = state;
  const hasHosted = s.hasHosted;
  // Simple Shell (switch simple_shell, note 66): Going out | Hosting in the header, one hero, one chip row, location in
  // the search bar, map as a Home view. Off = this screen exactly as before.
  const simpleShell = flagOn(s.featureFlags, 'simple_shell');
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
  // another tab, the organizer's Telegram bot, the bank webhook).
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
        { starts_at: e.startsAt, status: e.status, cancelled_at: e.cancelledAt, tz: e.tz }, null
      ) || {};
      const seatsText = e.seatsRemaining != null ? `${e.seatsRemaining} chỗ trống` : '';
      return {
        key: e.key,
        name: e.name,
        img: e.photoUrl,
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
        keywords: e.keywords || [], organizerName: e.organizerName || '', organizerId: e.organizerId,
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
  const realEventsSorted = useMemo(() => [...discoveryShaped].sort((a, b) => {
    if (!a.startsAtRaw && !b.startsAtRaw) return 0;
    if (!a.startsAtRaw) return 1;
    if (!b.startsAtRaw) return -1;
    return new Date(a.startsAtRaw) - new Date(b.startsAtRaw);
  }), [discoveryShaped]);
  const feed = useMemo(() => [...realEventsSorted, ...EVENTS]
    .map(withLive)
    // Ended events leave the feed (they live on the host's profile under "Past events"). A live row
    // 12h+ past its start is already over even if the server cron hasn't flipped it yet.
    .filter(e => e.endedHoursAgo == null && !(e.startsAtRaw && Date.now() - new Date(e.startsAtRaw).getTime() > 12 * 3600000))
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
  // Home → Map (Map redesign phase 3): the Map opens with Home's applied filters and For You; it frames its own map
  // area, so its count can differ from Home's (it says so: "+N matching outside this area").
  const openMapWithContext = () => goMapExplore({ source: 'home', filters: homeFilters, forYou: forYouActive });
  const shownItems = useMemo(() => {
    const filtered = applyDiscoveryFilters(discoveryItems, homeFilters, nowMs);
    // For You keeps its own ranking; any explicit sort overrides it, Soonest keeps the feed's order.
    return s.homeSort && s.homeSort !== 'soonest' ? sortEvents(filtered, s.homeSort) : filtered;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [discoveryItems, homeFilters, s.homeSort, Math.floor(nowMs / 60000)]);
  const quickCounts = useMemo(() => ({
    ...optionCounts(discoveryItems, homeFilters, 'date', ['today', 'weekend'], nowMs),
    free: optionCounts(discoveryItems, homeFilters, 'free', null, nowMs).true,
    almostFull: optionCounts(discoveryItems, homeFilters, 'almostFull', null, nowMs).true,
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
  const categoryCountMap = useMemo(() => categoryCounts(discoveryItems, homeFilters, TYPE_KEYS, nowMs),
  // eslint-disable-next-line react-hooks/exhaustive-deps
    [discoveryItems, homeFilters, Math.floor(nowMs / 60000)]);
  const categoryRow = categoryRowKeys(categoryCountMap, TYPE_KEYS, homeFilters.cats);
  const [categorySheetOpen, setCategorySheetOpen] = useState(false);
  const filterBadge = activeFilterCount(homeFilters);
  const sortActive = !!s.homeSort && s.homeSort !== 'soonest';
  const [sortMenuAnchor, setSortMenuAnchor] = useState(null);
  const [layoutMode, setLayoutMode] = useState(readLayout);
  const pickLayout = (m) => { setLayoutMode(m); try { localStorage.setItem(LAYOUT_KEY, m); } catch { /* per-viewer convenience only */ } };

  // Real events read in their venue's zone (migration 195); demo events (no tz) in the browser's, as before.
  const badgeDate = (ms, tz) => {
    if (ms == null) return '';
    const partsOf = (t) => {
      if (tz) return zonedParts(t, tz);
      const d = new Date(t);
      return { year: d.getFullYear(), month: d.getMonth() + 1, day: d.getDate(), hour: d.getHours(), minute: d.getMinutes(), weekday: d.getDay() };
    };
    const p = partsOf(ms);
    const wd = T(['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'][p.weekday], ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'][p.weekday]);
    const hh = String(p.hour).padStart(2, '0'), mm = String(p.minute).padStart(2, '0');
    const sameDay = (a, b) => a.year === b.year && a.month === b.month && a.day === b.day;
    const today = partsOf(Date.now()); const tomorrow = partsOf(Date.now() + 86400000);
    const day = sameDay(p, today) ? T('HÔM NAY', 'TODAY') : sameDay(p, tomorrow) ? T('MAI', 'TMRW') : `${wd} ${p.day}/${p.month}`;
    return `${day} · ${hh}:${mm}`;
  };
  // Best-match label: the top For You match, only when the user has answers. Without answers the first card
  // is "Popular this week" when it's the area's top Pulse event — never called a "match".
  const topPulseKey = useMemo(() => {
    let best = null;
    for (const it of discoveryItems) if (it.popularity != null && (!best || it.popularity > best.popularity)) best = it;
    return best?.key || null;
  }, [discoveryItems]);
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
      key: e.key, name: e.name, img: e.img, dateBadge: badgeDate(it.startsAt, e.isReal ? e.tz : null),
      priceLabel: it.priceVnd === 0 ? T('Miễn phí', 'Free') : trStatus(e.price), isFree: it.priceVnd === 0,
      metaLine: meta, fill, cancelled: !!e.cancelled, saved: e.saved, going: e.going, label,
      typeLine: typesOn && (e.isReal || Object.keys(e.details || {}).length > 0) ? cardLine(profileFor(e.catKey), { capacity: it.capacity ?? e.capacity, details: e.details }, s.lang === 'en' ? 'en' : 'vi') : null,
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [shownItems, forYouRanked, forYouActive, topPulseKey, trStatus, T, typesOn, s.lang]);

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
    .map(e => ({
      ...e,
      saved: isSaved(e.key),
      priceDisplay: e.priceLabel || T('Miễn phí', 'Free'),
      seatsDisplay: e.soldOut ? T('Hết chỗ', 'Sold out') : (e.seatsRemaining != null ? T(e.seatsRemaining + ' chỗ trống', e.seatsRemaining + ' left') : ''),
    })), [s.weekendEvents, curArea, s.homeFilters, isSaved, T]);

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
          <span style={{ fontSize: 9.5, color: ink, textAlign: 'center', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: 56 }}>{g.orgName}</span>
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

  return (
    <>
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Home">
      {/* iOS parity header: wordmark + "Home" title + round glass search
          button, then a row of three equal glass capsules (language, area,
          theme). Search lives here again (same openEventSearch action and
          data-testid as the old floating button). */}
      {/* Pinned like iOS (HomeView's `header` sits above its ScrollView): stays put while the feed scrolls under it. */}
      <div data-testid="home-fixed-header" data-reveal="0" style={{ padding: `${DOCK_HEADER.top}px ${DOCK_HEADER.side}px 8px`, display: 'flex', flexDirection: 'column', gap: 10, position: 'sticky', top: 0, zIndex: 6, background: paper }}>
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
              <span aria-hidden="true" data-testid="home-notifications-badge" style={{ position: 'absolute', top: 2, right: 2, minWidth: 16, height: 16, borderRadius: 8, padding: '0 4px', boxSizing: 'border-box', background: 'var(--bb-alert)', color: 'var(--bb-on-alert)', fontSize: 10, fontWeight: 700, lineHeight: '16px', textAlign: 'center' }}>
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
          <span aria-hidden="true" style={{ fontSize: 9, marginLeft: 2, flex: 'none' }}>▾</span>
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
      {hostView ? (
        <div data-reveal="1"><HostHome /><div style={{ height: 44 }} /></div>
      ) : (
      <>
      {/* Note 64: regions 1 and 2 are the sign-in reveal order (header 0, summary 1, feed 2, dock 3). Plain block
          wrappers, so layout is unchanged; they only animate while <html data-reveal="1">. */}
      {simpleShell ? (
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
                        <span style={{ fontSize: 11, color: ink, opacity: 0.55 }}>{T('Chưa có ảnh', 'No photo yet')}</span>
                      </div>
                    )}
                    <span
                      onClick={(ev) => { ev.stopPropagation(); toggleFav(e.key); }}
                      data-testid={`weekend-save-${e.key}`}
                      style={e.saved ? photoChip(CHIP_COLORS.going, { top: 6, right: 6, fontSize: 9, padding: '4px 8px', borderRadius: 12 }) : lightChip({ top: 6, right: 6, fontSize: 9, padding: '4px 8px', borderRadius: 12 })}
                    >
                      {e.saved ? T('Đã lưu', 'Saved') : T('Lưu', 'Save')}
                    </span>
                    {e.soldOut && (
                      <span style={photoChip(CHIP_COLORS.cancelled, { bottom: 6, left: 6, fontSize: 9, padding: '4px 8px', borderRadius: 12 })}>{T('Hết chỗ', 'Sold out')}</span>
                    )}
                  </div>
                  <div style={{ ...display(14, { marginTop: 7, lineHeight: 1.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</div>
                  <div style={{ fontSize: 11, color: ink, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{trStatus(e.when)}{e.area ? ' ▪︎ ' + e.area : ''}</div>
                  <div style={{ fontSize: 11, color: ink, marginTop: 1, display: 'flex', justifyContent: 'space-between', gap: 6 }}>
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
      {s.user && (
      <div style={{ padding: '16px 20px 16px', borderTop: `1px solid ${rule}` }} data-testid="home-survey-discovery-section">
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
                  <img src={card.host_avatar_url} alt="" style={{ width: 28, height: 28, borderRadius: 999, objectFit: 'cover', flexShrink: 0 }} />
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
                  <div style={{ fontSize: 11, color: ink, opacity: 0.65, marginTop: 2, display: 'flex', alignItems: 'center', gap: 5, flexWrap: 'wrap' }}>
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
      )}

      <div style={{ padding: '6px 20px 8px', fontSize: 11, color: ink }}>
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
        areaLabel={curArea.key === 'all' ? '' : curArea.label}
        onClose={() => set({ homeFilterSheetOpen: false })}
        onApply={(f, sort) => { setHomeFilters(f); set({ homeFilterSheetOpen: false, homeSort: sort }); }}
        {...(simpleShell ? { simpleShell: true } : {})}
      />
    )}
    </>
  );
}

