import PhoneStatusBar from './components/PhoneFrame.jsx';
import { ImportSheet, ImportedTicketSheet } from './screens/sheets/TicketImportSheet.jsx';
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { BanBeProvider, useBanBe } from './state/BanBeContext.jsx';
import useUrlSync from './lib/useUrlSync.js';
import BottomTabBar, { showsBottomBar, DOCK_ORDER, DOCK_MAX_WIDTH, DOCK_MARGIN, DOCK_GAP, CREATE_SIZE, BAR_BOTTOM_OFFSET } from './screens/BottomTabBar.jsx';
import { paper, ink, rule } from './theme.js';

import Splash from './screens/Splash.jsx';
import LangPick from './screens/LangPick.jsx';
import ThemePick from './screens/ThemePick.jsx';
import Loading from './screens/Loading.jsx';
import Home from './screens/Home.jsx';
import Account from './screens/Account.jsx';
import AccountGroup from './screens/AccountGroup.jsx';
import Inbox from './screens/Inbox.jsx';
import EventDetail from './screens/EventDetail.jsx';
import Reserve from './screens/Reserve.jsx';
import Confirmed from './screens/Confirmed.jsx';
import Refunded from './screens/Refunded.jsx';
import Login from './screens/Login.jsx';
import ResetPassword from './screens/ResetPassword.jsx';
import Chat from './screens/Chat.jsx';
import Dashboard from './screens/Dashboard.jsx';
import HostIntro from './screens/HostIntro.jsx';
import CreateEvent from './screens/CreateEvent.jsx';
import Attendance from './screens/Attendance.jsx';
import AreaSheet from './screens/sheets/AreaSheet.jsx';
import LocationSheet from './screens/sheets/LocationSheet.jsx';
import QrScanSheet from './screens/sheets/QrScanSheet.jsx';
import ReasonSheet from './screens/sheets/ReasonSheet.jsx';
import PhotoViewer from './screens/sheets/PhotoViewer.jsx';
import ChatPhotoViewer from './screens/sheets/ChatPhotoViewer.jsx';
import StoryViewer from './screens/sheets/StoryViewer.jsx';
import PulseViewer from './screens/sheets/PulseViewer.jsx';
import SurveyResponseModal from './screens/sheets/SurveyResponseModal.jsx';
import DeleteAccountSheet from './screens/sheets/DeleteAccountSheet.jsx';
import Preferences from './screens/Preferences.jsx';
import EditName from './screens/EditName.jsx';
import Notifications from './screens/Notifications.jsx';
import EventList from './screens/EventList.jsx';
import Security from './screens/Security.jsx';
import PaymentDetails from './screens/PaymentDetails.jsx';
import RefundAccounts from './screens/RefundAccounts.jsx';
import MyRefunds from './screens/MyRefunds.jsx';
import Billing from './screens/Billing.jsx';
import Payout from './screens/Payout.jsx';
import Documents from './screens/Documents.jsx';
import DocumentView from './screens/DocumentView.jsx';
import Verifications from './screens/Verifications.jsx';
import Disputes from './screens/Disputes.jsx';
import AdminEvents from './screens/AdminEvents.jsx';
import AdminTestAccounts from './screens/AdminTestAccounts.jsx';
import AdminDobCorrections from './screens/AdminDobCorrections.jsx';
import ToastStack from './screens/ToastStack.jsx';
import Policy from './screens/Policy.jsx';
import Guide from './screens/Guide.jsx';
import Faq from './screens/Faq.jsx';
import MapExplore from './screens/MapExplore.jsx';
import DockCreateButton from './screens/DockCreateButton.jsx';
import StoryCreateOverlay from './screens/StoryCreateOverlay.jsx';
import EditProfile from './screens/EditProfile.jsx';
import PublicProfile from './screens/PublicProfile.jsx';
import OrganizerProfile from './screens/OrganizerProfile.jsx';
import Reports from './screens/Reports.jsx';
import TeamPage from './screens/TeamPage.jsx';
import SurveyPublic from './screens/SurveyPublic.jsx';
import SurveysHosting from './screens/SurveysHosting.jsx';
import RootRefreshIndicator from './screens/RootRefreshIndicator.jsx';
import AccountGate from './screens/AccountGate.jsx'; // account gate (web parity)
import EventPreferences from './screens/EventPreferences.jsx';
import Following from './screens/Following.jsx';
import Rewards from './screens/Rewards.jsx';
import EventOnboarding, { useEventOnboardingActive } from './screens/EventOnboarding.jsx';

const SCREENS = {
  splash: Splash,
  langPick: LangPick,
  themePick: ThemePick,
  home: Home,
  profile: Account,
  accountGroup: AccountGroup,
  inbox: Inbox,
  event: EventDetail,
  reserve: Reserve,
  confirmed: Confirmed,
  refunded: Refunded,
  login: Login,
  resetPassword: ResetPassword,
  chat: Chat,
  dashboard: Dashboard,
  hostIntro: HostIntro,
  create: CreateEvent,
  attendance: Attendance,
  preferences: Preferences,
  eventPreferences: EventPreferences,
  following: Following,
  rewards: Rewards,
  editName: EditName,
  notifications: Notifications,
  eventList: EventList,
  security: Security,
  paymentDetails: PaymentDetails,
  refundAccounts: RefundAccounts,
  myRefunds: MyRefunds,
  billing: Billing,
  payout: Payout,
  documents: Documents,
  documentView: DocumentView,
  verifications: Verifications,
  disputes: Disputes,
  adminEvents: AdminEvents,
  adminTestAccounts: AdminTestAccounts,
  adminDobCorrections: AdminDobCorrections,
  policy: Policy,
  guide: Guide,
  faq: Faq,
  mapExplore: MapExplore,
  editProfile: EditProfile,
  publicProfile: PublicProfile,
  organizerProfile: OrganizerProfile,
  reports: Reports,
  organizerTeam: TeamPage,
  surveyPublic: SurveyPublic,
  surveysHosting: SurveysHosting,
};

// TASK 1 (2026-10-05 fix pass) — the dock and the create-"+" button laid
// out as ONE row, replacing two independently absolutely-positioned
// elements (BottomTabBar centered via its own left:50%/width math,
// DockCreateButton pinned at `right: 16`) that could and did overlap on a
// real iPhone: BottomTabBar's old 400px max width left under 4px of
// clearance from a 390px-wide viewport's edges alone, with no room left for
// a 46px circle beside it. `DOCK_MAX_WIDTH` on the bar itself is an upper
// bound, not a fixed width (its own items are flex-based — see
// BottomTabBar.jsx), so this row's own `calc(100% - margin*2)` cap is what
// actually makes the bar shrink first on a narrow screen instead of
// overflowing past the "+" button.
function DockRow({ collapsed, showCreate }) {
  return (
    <div
      style={{
        position: 'absolute', left: '50%', bottom: BAR_BOTTOM_OFFSET,
        width: `calc(100% - ${DOCK_MARGIN * 2}px)`,
        maxWidth: DOCK_MAX_WIDTH + (showCreate ? DOCK_GAP + CREATE_SIZE : 0),
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: DOCK_GAP,
        // Same layer BottomTabBar's own zIndex used to sit at — see that
        // constant's own history (623ec1e) for why 25 specifically (above
        // MapExplore's own WebGL canvas, below Notifications' full-screen
        // action-sheet scrim at 30).
        zIndex: 25,
        // BUG (2026-10-06 fix pass) — the shrink-on-scroll scale used to
        // live on BottomTabBar's own div alone, so only the dock visibly
        // resized on scroll while the "+" beside it stayed full size. A
        // single transform HERE, on the row that contains both, scales
        // them together as one unit — see BottomTabBar.jsx's own comment
        // at this transform's former call site.
        // iPhone fix pass (2026-09-27), Item 1 follow-up — real bug found
        // while writing this ticket's own deterministic test (not
        // reproducible on iOS, which has no CSS equivalent): the row's
        // OWN centering/scale used to live on the `transform` shorthand
        // (`translateX(-50%) scale(...)`), which the `animation: bbIn ...
        // both` below ALSO drives (a fill-mode of `both` keeps applying
        // the animation's own `transform` value — here, `bbIn`'s `to`
        // keyframe, `translateY(0)`, i.e. IDENTITY — for as long as the
        // element stays mounted, completely overriding this static value
        // for the same property the instant the 0.28s entrance animation
        // finishes). Measured directly: after any dock remount (e.g.
        // returning to a root tab from a non-bar screen) the dock's real
        // `getComputedStyle().transform` settles to the identity matrix,
        // not `translateX(-50%) scale(...)` — silently un-centering the
        // whole 358px-wide row 179px to the right of where `left: 50%`
        // means it to sit, pushing Inbox/Account off the right edge of a
        // narrow viewport entirely (confirmed: `tab-profile`'s own real
        // bounding box lands outside the viewport once this fires).
        // `translate`/`scale` are their own standalone CSS properties
        // (not the `transform` shorthand) precisely so this can't
        // collide with `bbIn`'s own `transform`-only entrance animation —
        // the two now animate/apply completely independently, and this
        // row's real center/size can never again be silently overridden
        // by a completed mount-in animation.
        translate: '-50% 0',
        scale: collapsed ? 0.86 : 1,
        transformOrigin: 'center bottom',
        transition: 'scale 0.28s cubic-bezier(.22,.61,.36,1)',
        // Restores with the existing (previously unused) bottom-up "bbIn"
        // keyframe every time this row remounts — e.g. right after the
        // Khu vực sheet (or any other screen that suppresses the dock)
        // closes — instead of the bar just snapping back into place.
        animation: 'bbIn 0.28s cubic-bezier(.22,.61,.36,1) both',
      }}
    >
      <BottomTabBar collapsed={collapsed} />
      {showCreate && <DockCreateButton />}
    </div>
  );
}

function Shell() {
  const goc = useBanBe();
  useUrlSync(goc);
  const {
    state, T,
    goHome, goMapExplore, goNotifications, goInbox, goProfile,
    loadHomeLiveEvents, loadDiscoveryEvents, loadWeekendEvents, loadHomeStories, loadHomeSurveyDiscovery,
    loadNotifications, loadInboxThreads,
    loadPaymentBookings, loadMyRefunds, loadVerifications, loadRefundQueue, loadOrganizerHoldingSummary, loadMyOrgStats,
    canHost,
  } = useBanBe();
  const scrollRef = useRef(null);
  const scrollPositions = useRef({});
  const lastScrollTop = useRef(0);
  const scrollRaf = useRef(null);
  const pendingScrollTop = useRef(0);
  const [barCollapsed, setBarCollapsed] = useState(false);
  // Stage 2 (2026-09-27 nav/discovery pass) — always mirrors the latest
  // `state` so async gesture code (the pull-to-refresh await below) can
  // read fresh values without a stale closure, without re-subscribing
  // every callback to `state` itself.
  const stateRef = useRef(state);
  stateRef.current = state;
  // iPhone fix pass (2026-09-27), Item 1 — the real tap-race root cause:
  // `endGesture`'s committed-swipe branch (below) used to unconditionally
  // call `gotoDockIndex(...)` from its own 250ms-delayed `setTimeout`, with
  // nothing checking whether some OTHER navigation had already happened in
  // the meantime. Reproduction: swipe from Home to Inbox (that commit's
  // settle timer is now pending), then — before 250ms elapses — tap
  // Account in the dock. The tap's own `goProfile()` (BottomTabBar.jsx)
  // sets `screen: 'profile'` immediately; the STALE swipe-settle timeout
  // still fires afterward and calls `gotoDockIndex(idx±1)` (the target it
  // captured back when the swipe committed, e.g. Inbox), silently
  // stomping the newer tap and bouncing back to Inbox. Bumped on EVERY
  // `state.screen` change, from wherever it comes from (a dock tap, a
  // swipe commit, any other navigation), so the delayed callback below can
  // tell whether it's still the most recent navigation before touching
  // `state.screen` again — same iOS-side fix (RootView.swift's own
  // `navGeneration`), same shape on both platforms.
  const navGenerationRef = useRef(0);
  useEffect(() => { navGenerationRef.current += 1; }, [state.screen]);
  // Task 1 (2026-09-22 follow-up, 07-notifications.md) — a fullscreen
  // StoryViewer session must suppress the dock entirely, not just visually
  // (it fully unmounts here, so there's nothing left to intercept taps —
  // the same "hidden, not merely lower z-index" bar this ticket asks for
  // on iOS's separate-UIWindow overlay).
  // iPhone fix pass (2026-09-26) — the "Khu vực" sheet (AreaSheet.jsx) used
  // to render at a LOWER z-index than the dock row below, so the dock (and
  // its separate "+" button) stayed visible and tappable THROUGH the
  // sheet's own dimmed backdrop. Suppressed here the same centralized way
  // StoryViewer/Pulse already are, rather than a second, independent
  // visibility flag or another UIWindow-style overlay.
  // Post-signup onboarding overlay (note 34): the dock is hidden while it is up.
  const eventOnboardingActive = useEventOnboardingActive();
  const showBar = showsBottomBar(state.screen) && !state.storyViewer && !state.pulseOpen && !state.areaAsking && !state.storySurveyModalPublicId && !eventOnboardingActive;

  // Stage 2 (2026-09-27 nav/discovery pass) — root-tab swipe + pull-to-
  // refresh, both gated on the SAME "is a root tab actually showing right
  // now" condition `showBar` already computes (no sheet/story/Pulse/area-
  // sheet open) — a full-screen gesture layer has no business engaging
  // over any of those.
  const gestureBlocked = !showBar || state.askingLocation || state.scanningQr || state.photoViewer || state.chatPhotoViewer || state.reasonPrompt;
  const SWIPE_START_PX = 10;
  const SWIPE_COMMIT_PX = 70;
  // Reserves the true left/right screen edges for the OS's own edge-swipe-
  // back gesture (iOS Safari) on every root screen — never just Map.
  const EDGE_RESERVE_PX = 24;
  const PULL_TRIGGER_PX = 64;
  const PULL_MAX_PX = 100;
  const gestureRef = useRef({ active: false, phase: null, startX: 0, startY: 0, lastX: 0, lastY: 0, pointerId: null, scrollTopAtStart: 0, width: 0 });
  const [swipeX, setSwipeX] = useState(0);
  const [pullDist, setPullDist] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const [refreshError, setRefreshError] = useState('');
  // Only true while a drag is actively driving swipeX/pullDist — lets the
  // render below skip the snap-back CSS transition exactly then, so the
  // gesture follows the finger with zero lag instead of chasing a tween.
  const [isSwiping, setIsSwiping] = useState(false);
  const [isPulling, setIsPulling] = useState(false);
  // Root-tab-swipe fix pass (2026-09-27, follow-up B) — the real cause of
  // "destination screen is blank/partly missing during the drag, then
  // slides in AGAIN from the left after release": only the CURRENT
  // screen was ever rendered/transformed here, so a drag revealed nothing
  // behind it, and committing changed `state.screen`, which changed
  // `<Screen key={state.screen}/>`'s own key — forcing React to unmount
  // the old component and mount a BRAND NEW instance of the destination,
  // replaying that screen's own CSS mount-in animation (every screen's
  // root div carries `animation: banbeIn ...`) on top of a drag that had
  // already visually placed it. `swipeNeighbor` (the adjacent screen's
  // key, or null) makes the render below mount that REAL destination
  // screen early and move it together with the current one in one shared
  // transform-based coordinate system (see the render's own CSS Grid
  // stacking comment) — and since a screen's `key` never changes across
  // the eventual commit (see endGesture's own comment), React keeps that
  // SAME instance instead of remounting it, so its `banbeIn` animation
  // plays exactly once, during the reveal, never a second time on release.
  const [swipeNeighbor, setSwipeNeighbor] = useState(null);

  // Each root screen's own real data reload — reuses the SAME loaders each
  // screen's own mount effect already calls, never a second/duplicate
  // poll. 'mapExplore' is deliberately absent: Map renders as a fixed,
  // full-viewport overlay (MapExplore.jsx), so THIS container's own
  // scrollTop never moves there and is always 0 — treating that as "at
  // the top, pull to refresh" would hijack the map's OWN vertical
  // gestures (its bottom sheet's drag-to-resize handle, its event list's
  // native scroll). Map gets its own local pull-to-refresh directly on
  // its event list container instead (MapExplore.jsx), which has a real,
  // independent scrollTop.
  const runRefresh = async (screen) => {
    const s = stateRef.current;
    if (screen === 'home') {
      await Promise.all([
        loadHomeLiveEvents(), loadDiscoveryEvents(), loadWeekendEvents(),
        ...(s.user?.id ? [loadHomeStories(), loadHomeSurveyDiscovery()] : []),
      ]);
    } else if (screen === 'notifications') {
      await loadNotifications();
    } else if (screen === 'inbox') {
      await loadInboxThreads();
    } else if (screen === 'profile') {
      const tasks = [loadPaymentBookings(), loadMyRefunds()];
      if (canHost) {
        tasks.push(loadVerifications(), loadRefundQueue(), loadOrganizerHoldingSummary());
        if (s.myOrganizerId) tasks.push(loadMyOrgStats());
      }
      await Promise.all(tasks);
    }
  };

  // The adjacent screen sits exactly one full container-width away from
  // the current one, in the direction it's coming from, and slides in as
  // `swipeX` follows the finger — one shared coordinate system with the
  // current screen (which uses `swipeX` directly), not an independent
  // transition.
  const neighborOffset = (screen) => {
    const idx = DOCK_ORDER.indexOf(stateRef.current.screen);
    const nIdx = DOCK_ORDER.indexOf(screen);
    if (idx === -1 || nIdx === -1) return 0;
    const width = gestureRef.current.width || window.innerWidth;
    const sign = nIdx > idx ? 1 : -1;
    return swipeX + sign * width;
  };

  const gotoDockIndex = (idx) => {
    const key = DOCK_ORDER[idx];
    ({ home: goHome, mapExplore: goMapExplore, notifications: goNotifications, inbox: goInbox, profile: goProfile })[key]?.();
  };

  const onGesturePointerDown = (e) => {
    if (gestureBlocked) return;
    const el = scrollRef.current;
    // The app renders centered with its own maxWidth — on a wider viewport
    // that leaves empty space on both sides, so edge-zone math below needs
    // the drag's start X relative to THIS container's own left edge, never
    // the raw (absolute, viewport-relative) e.clientX a wide desktop
    // viewport would otherwise report. `startX` itself stays absolute —
    // it's what dx (the actual drag delta) is measured against below.
    const containerLeft = el ? el.getBoundingClientRect().left : 0;
    gestureRef.current = {
      active: true, phase: 'undetermined',
      startX: e.clientX, startY: e.clientY, lastX: e.clientX, lastY: e.clientY,
      startXRel: e.clientX - containerLeft,
      pointerId: e.pointerId,
      scrollTopAtStart: el ? el.scrollTop : 0,
      width: el ? el.clientWidth : window.innerWidth,
    };
  };

  const onGesturePointerMove = (e) => {
    const g = gestureRef.current;
    if (!g.active || e.pointerId !== g.pointerId) return;
    const dx = e.clientX - g.startX;
    const dy = e.clientY - g.startY;
    g.lastX = e.clientX; g.lastY = e.clientY;

    if (g.phase === 'undetermined') {
      if (Math.abs(dx) < SWIPE_START_PX && Math.abs(dy) < SWIPE_START_PX) return;
      if (Math.abs(dy) >= Math.abs(dx)) {
        // Vertical-dominant: a real pull-to-refresh candidate only when it
        // started genuinely at the top (nothing left to scroll into) and
        // is a downward drag — otherwise this is just an ordinary scroll,
        // left entirely to the browser's own native handling. Excludes
        // 'mapExplore' (see runRefresh's own comment on why) — its own
        // list container implements this locally instead.
        g.phase = (dy > 0 && g.scrollTopAtStart <= 0 && stateRef.current.screen !== 'mapExplore') ? 'pull' : 'native-scroll';
      } else {
        const overHscroll = e.target?.closest?.('[data-hscroll]');
        const screen = stateRef.current.screen;
        if (overHscroll || g.startXRel < EDGE_RESERVE_PX) {
          g.phase = 'native-scroll';
        } else if (screen === 'mapExplore' && g.startXRel < g.width - EDGE_RESERVE_PX) {
          // Map pan owns the rest of the canvas — only a narrow strip near
          // the right edge starts a tab-swipe here (the ticket's own
          // "narrow safe edge/tab-area gesture" for Map specifically).
          g.phase = 'native-scroll';
        } else {
          g.phase = 'horizontal';
        }
      }
    }

    if (g.phase === 'horizontal') {
      e.preventDefault();
      setIsSwiping(true);
      const idx = DOCK_ORDER.indexOf(stateRef.current.screen);
      const canNext = idx !== -1 && idx < DOCK_ORDER.length - 1;
      const canPrev = idx > 0;
      let clamped = dx;
      if (dx < 0 && !canNext) clamped = dx * 0.25;
      if (dx > 0 && !canPrev) clamped = dx * 0.25;
      setSwipeX(clamped);
      // Mount the real adjacent screen as soon as a direction is known —
      // its own existing loader (`.task`/mount effect) starts right away
      // instead of waiting for the gesture to commit.
      const neighbor = clamped < 0 && canNext ? DOCK_ORDER[idx + 1] : clamped > 0 && canPrev ? DOCK_ORDER[idx - 1] : null;
      setSwipeNeighbor(neighbor);
    } else if (g.phase === 'pull') {
      e.preventDefault();
      setIsPulling(true);
      setPullDist(Math.min(PULL_MAX_PX, Math.max(0, dy) * 0.5));
    }
  };

  const endGesture = () => {
    const g = gestureRef.current;
    if (!g.active) return;
    g.active = false;
    const dx = g.lastX - g.startX;

    if (g.phase === 'horizontal') {
      const idx = DOCK_ORDER.indexOf(stateRef.current.screen);
      const width = g.width || window.innerWidth;
      const commitNext = dx <= -SWIPE_COMMIT_PX && idx !== -1 && idx < DOCK_ORDER.length - 1;
      const commitPrev = dx >= SWIPE_COMMIT_PX && idx > 0;
      setIsSwiping(false);
      if (commitNext || commitPrev) {
        // Settle the SAME two already-mounted screens (current + the real
        // neighbor from onGesturePointerMove) the rest of the way to their
        // final positions over one real CSS transition — never a second
        // push/slide transition. Only once that settle finishes does
        // `state.screen` actually flip (gotoDockIndex); `swipeNeighbor`'s
        // key never changes across that flip, so the destination screen's
        // component instance (and its already-completed mount animation)
        // carries straight through instead of remounting.
        setSwipeX(commitNext ? -width : width);
        // iPhone fix pass (2026-09-27), Item 1 — captured BEFORE the
        // settle delay starts; see `navGenerationRef`'s own doc comment
        // above for why.
        const expectedGeneration = navGenerationRef.current;
        setTimeout(() => {
          // A newer navigation (a dock tap, another swipe, anything that
          // changed `state.screen`) already happened while this settle was
          // in flight — that navigation's own destination must win, so
          // this stale commit only cleans up its own local visual state
          // and never touches `state.screen` again.
          if (navGenerationRef.current === expectedGeneration) {
            gotoDockIndex(commitNext ? idx + 1 : idx - 1);
          }
          // Unanimated reset — the newly-current screen is already sitting
          // exactly in place, so this swap must not itself visibly move.
          setIsSwiping(true);
          setSwipeX(0);
          setSwipeNeighbor(null);
          requestAnimationFrame(() => setIsSwiping(false));
        }, 250);
      } else {
        setSwipeX(0);
        setTimeout(() => setSwipeNeighbor(null), 250);
      }
    } else if (g.phase === 'pull') {
      setIsPulling(false);
      if (pullDist >= PULL_TRIGGER_PX) {
        setRefreshing(true);
        setRefreshError('');
        const screen = stateRef.current.screen;
        setPullDist(PULL_TRIGGER_PX * 0.72);
        (async () => {
          try {
            await runRefresh(screen);
          } catch (err) {
            console.warn('Pull-to-refresh failed:', err);
            setRefreshError(T('Không thể làm mới. Vui lòng thử lại.', "Couldn't refresh. Please try again."));
            setTimeout(() => setRefreshError(''), 3000);
          } finally {
            setRefreshing(false);
            setPullDist(0);
          }
        })();
      } else {
        setPullDist(0);
      }
    }
    g.phase = null;
  };

  const cancelGesture = () => {
    gestureRef.current.active = false;
    gestureRef.current.phase = null;
    setIsSwiping(false);
    setSwipeX(0);
    if (swipeNeighbor) setTimeout(() => setSwipeNeighbor(null), 250);
    if (!refreshing) { setIsPulling(false); setPullDist(0); }
  };

  // Refresh-indicator fix pass (2026-09-27, follow-up B) — "dismiss on
  // ... tab switch": a plain dock TAP (not a swipe-commit, which already
  // resets these itself) changes `state.screen` directly, and without
  // this, a pull started on one tab that's still `refreshing` when the
  // user taps straight to another tab would keep rendering there until
  // the old tab's own reload happened to resolve.
  useLayoutEffect(() => {
    setPullDist(0);
    setRefreshing(false);
    setRefreshError('');
  }, [state.screen]);

  useLayoutEffect(() => {
    const el = scrollRef.current;
    const target = scrollPositions.current[state.screen] || 0;
    if (el) el.scrollTop = target;
    lastScrollTop.current = target;
    if (scrollRaf.current) { cancelAnimationFrame(scrollRaf.current); scrollRaf.current = null; }
    setBarCollapsed(false);

    // Home task 3 (2026-09-21 follow-up) — this synchronous restore alone
    // wasn't enough for Home specifically: `loadHomeLiveEvents()`
    // (BanBeContext.jsx, added 1c62d4c) fetches asynchronously and can
    // shrink/reorder `feed`/`savedList` a beat AFTER this effect already
    // ran, silently pulling the restored position back toward the top
    // once the page's total scrollable height changes underneath it —
    // exactly the reported "Event Detail round trip resets Home to the
    // top" symptom. Fixed generically (not Home-specific): watch the
    // scroll container's own height for changes and re-apply the SAME
    // saved target for as long as the user hasn't scrolled again
    // themselves in the meantime (a real scroll flips `userScrolled`,
    // which stops this from fighting a deliberate manual scroll) — this
    // reuses the exact same `scrollPositions`/`state.screen` keying
    // already established, just makes it resilient to late-arriving
    // async content on any screen, not only Home.
    if (!el || target === 0) return undefined;
    let userScrolled = false;
    const onScroll = () => { userScrolled = true; };
    el.addEventListener('scroll', onScroll, { once: true });
    const ro = new ResizeObserver(() => {
      if (!userScrolled && el) el.scrollTop = target;
    });
    ro.observe(el);
    // Generous settle window for a real network fetch to resolve and
    // reflow — stops watching after that so this can't fight the user
    // forever on a screen with legitimately dynamic content.
    const settleTimeout = setTimeout(() => ro.disconnect(), 2000);
    return () => { ro.disconnect(); clearTimeout(settleTimeout); el.removeEventListener('scroll', onScroll); };
  }, [state.screen]);

  // Mirrors iOS 26's onScrollDown minimize behavior: scrolling down shrinks
  // the floating pill a bit, scrolling up (or being at the very top) puts
  // it straight back to full size.
  //
  // BUG 1 follow-up (64f2719 real-device report): this used to call
  // setBarCollapsed synchronously on every raw `scroll` event — which on a
  // touchpad/momentum scroll can fire far more often than the screen can
  // repaint — forcing a React re-render per pixel scrolled. Reading
  // scrollTop and deciding the direction still happens on every event (it's
  // cheap), but the actual state write (the only part that triggers a
  // re-render) is coalesced to at most once per animation frame via rAF, so
  // a burst of scroll events between two frames only ever produces one
  // update instead of one each.
  const handleScroll = (e) => {
    const top = e.currentTarget.scrollTop;
    scrollPositions.current[state.screen] = top;
    pendingScrollTop.current = top;
    if (scrollRaf.current) return;
    scrollRaf.current = requestAnimationFrame(() => {
      scrollRaf.current = null;
      // Read the LATEST scrollTop at flush time, not whatever it was when
      // this frame's rAF was scheduled — several scroll events typically
      // land in the gap between the schedule and the callback, and only
      // the most recent one should decide direction.
      const latestTop = pendingScrollTop.current;
      // BUG 3 follow-up (623ec1e real-device report): re-verified this sign
      // convention against the spec ("scrolling further down the page —
      // scrollTop increasing — shrinks the bar; scrolling back toward the
      // top restores it") rather than assuming it needed flipping.
      // `scrollTop` increasing IS "further down the page" by definition
      // (W3C: distance from the top), so a positive `scrollingDown` delta
      // here already matches "shrink" below — this was not inverted.
      // Tightened the trigger threshold from 6px to 4px so a real,
      // deliberate scroll registers reliably rather than needing an
      // unusually large jump between two coalesced rAF frames.
      const scrollingDown = latestTop - lastScrollTop.current;
      if (latestTop <= 4) setBarCollapsed(false);
      else if (scrollingDown > 4) setBarCollapsed(true);
      else if (scrollingDown < -4) setBarCollapsed(false);
      lastScrollTop.current = latestTop;
    });
  };

  return (
    <div className="bb-stage" data-bb-theme={state.theme} style={{ position: 'fixed', inset: 0, display: 'flex', justifyContent: 'center', background: '#EFEBE0' }}>
     {/* On a desktop browser .bb-device/.bb-screen draw a phone around the app
         (index.css); anywhere else they are `display: contents` and change
         nothing. .bb-screen is also the containing block for every
         position:fixed overlay inside it, so sheets, toasts and the dock stay
         within the phone instead of spanning the whole window. */}
     <div className="bb-device"><div className="bb-screen">
      <PhoneStatusBar />
      <div
        ref={scrollRef}
        data-testid="app-scroll-viewport"
        onScroll={handleScroll}
        onPointerDown={onGesturePointerDown}
        onPointerMove={onGesturePointerMove}
        onPointerUp={endGesture}
        onPointerCancel={cancelGesture}
        style={{
          width: '100%', maxWidth: 480, height: '100%', position: 'relative', overflowY: 'auto', WebkitOverflowScrolling: 'touch', background: 'var(--bb-bg)',
          // Stage 2 — 'pan-y' keeps native vertical scrolling completely
          // untouched while telling the browser NOT to natively claim
          // horizontal drags on this element, leaving those free for our
          // own swipe/pull gesture (see onGesturePointerMove) instead of
          // fighting it via preventDefault on every event.
          touchAction: gestureBlocked ? 'auto' : 'pan-y',
        }}
      >
        {/* Refresh-indicator fix pass (2026-09-27, follow-up A) — the
            generic circular spinner is gone: this now shows the OUTLINE
            icon of the tab actually being refreshed (state.screen — this
            container never renders for mapExplore, see runRefresh's own
            comment, so screen here is always one of the other four), with
            a thin stroke traveling around that icon's own outline, not an
            enclosing circle (RootRefreshIndicator.jsx). Follows pull
            distance before release, held at PULL_TRIGGER_PX*0.72 (a fixed
            "travel" position) while the real reload is in flight; a
            friendly line on failure instead. */}
        {(pullDist > 0 || refreshing || refreshError) && (
          <div
            data-testid="pull-to-refresh-indicator"
            style={{
              position: 'absolute', top: 14, left: 0, right: 0, display: 'flex', justifyContent: 'center', zIndex: 5,
              transform: `translateY(${Math.max(0, pullDist - 28)}px)`, transition: isPulling ? 'none' : 'transform 0.22s ease',
              pointerEvents: 'none',
            }}
          >
            {refreshError ? (
              <span style={{ fontSize: 11.5, fontWeight: 600, color: ink, background: paper, borderRadius: 999, padding: '7px 14px', boxShadow: '0 4px 14px rgba(27,25,22,0.16)' }}>{refreshError}</span>
            ) : (
              <RootRefreshIndicator
                screen={state.screen}
                progress={pullDist / PULL_TRIGGER_PX}
                refreshing={refreshing}
                label={T('Đang làm mới', 'Refreshing')}
              />
            )}
          </div>
        )}
        {/* Root-tab-swipe fix pass (2026-09-27, follow-up B) — a CSS Grid
            "stack" (both children share the same `gridArea`, so the
            container's own box is sized from content exactly as a plain
            div's would be with just one child) instead of a single
            `<Screen key={state.screen}/>`. While `swipeNeighbor` is set,
            the real destination screen renders here as a SECOND sibling
            (same array, same parent) instead of nothing — see
            onGesturePointerMove's own comment for why it's mounted this
            early. Each screen keeps a stable `key={s}` across the whole
            drag-then-commit sequence (endGesture never changes it, only
            drops the old sibling), so React never tears down and remounts
            the destination the way changing `<Screen key={state.screen}/>`'s
            own key used to. */}
        <div style={{ paddingBottom: showBar ? 92 : 0, display: 'grid', gridTemplateColumns: 'minmax(0, 1fr)' }}>
          {[state.screen, ...(swipeNeighbor ? [swipeNeighbor] : [])].map((s) => {
            const isCurrent = s === state.screen;
            const ScreenComp = SCREENS[s] || Home;
            const off = isCurrent ? swipeX : neighborOffset(s);
            return (
              <div
                key={s}
                style={{
                  gridArea: '1 / 1',
                  transform: (off || (isCurrent && pullDist)) ? `translate(${off}px, ${isCurrent ? pullDist : 0}px)` : undefined,
                  transition: (isSwiping || isPulling) ? 'none' : 'transform 0.25s cubic-bezier(.22,.61,.36,1)',
                  pointerEvents: isCurrent ? undefined : 'none',
                }}
              >
                <ScreenComp />
              </div>
            );
          })}
        </div>
        {state.areaAsking && <AreaSheet />}
        {state.askingLocation && <LocationSheet />}
        {state.scanningQr && <QrScanSheet />}
        {state.photoViewer && <PhotoViewer />}
        {state.chatPhotoViewer && <ChatPhotoViewer />}
        {state.storyViewer && <StoryViewer />}
        {state.pulseOpen && <PulseViewer />}
        {state.storySurveyModalPublicId && <SurveyResponseModal />}
        {state.reasonPrompt && <ReasonSheet />}
        {state.importOpen && <ImportSheet />}
        {state.importedTicketOpen && <ImportedTicketSheet />}
        {state.loading && <Loading label={T('Đang giữ chỗ cho bạn…', 'Holding your seat…')} />}
      </div>
      {showBar && <DockRow collapsed={barCollapsed} showCreate={state.organizerMode} />}
      {/* TASK 1 (dock "+" menu pass) — mounted unconditionally (not gated
          on showBar/organizerMode) since Account.jsx's own "Đăng story"
          entry point can still open it even on a screen without the dock. */}
      <StoryCreateOverlay />
      {state.deleteAccountOpen && <DeleteAccountSheet />}
      <ToastStack />
      {/* account gate (web parity) — blocking overlay above every screen until the server gate clears */}
      <AccountGate />
      {/* event onboarding (note 34) — below the gate, above every screen */}
      <EventOnboarding />
     </div></div>
    </div>
  );
}

export default function App() {
  return (
    <BanBeProvider>
      <Shell />
    </BanBeProvider>
  );
}
