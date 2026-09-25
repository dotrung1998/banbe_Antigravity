import { useLayoutEffect, useRef, useState } from 'react';
import { GocProvider, useGoc } from './state/GocContext.jsx';
import BottomTabBar, { showsBottomBar } from './screens/BottomTabBar.jsx';

import Splash from './screens/Splash.jsx';
import LangPick from './screens/LangPick.jsx';
import ThemePick from './screens/ThemePick.jsx';
import Loading from './screens/Loading.jsx';
import Home from './screens/Home.jsx';
import Account from './screens/Account.jsx';
import Inbox from './screens/Inbox.jsx';
import EventDetail from './screens/EventDetail.jsx';
import Organizer from './screens/Organizer.jsx';
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
import ToastStack from './screens/ToastStack.jsx';
import Policy from './screens/Policy.jsx';
import MapExplore from './screens/MapExplore.jsx';
import DockCreateButton from './screens/DockCreateButton.jsx';
import EditProfile from './screens/EditProfile.jsx';
import PublicProfile from './screens/PublicProfile.jsx';

const SCREENS = {
  splash: Splash,
  langPick: LangPick,
  themePick: ThemePick,
  home: Home,
  profile: Account,
  inbox: Inbox,
  event: EventDetail,
  organizer: Organizer,
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
  policy: Policy,
  mapExplore: MapExplore,
  editProfile: EditProfile,
  publicProfile: PublicProfile,
};

function Shell() {
  const { state, T } = useGoc();
  const Screen = SCREENS[state.screen] || Home;
  const scrollRef = useRef(null);
  const scrollPositions = useRef({});
  const lastScrollTop = useRef(0);
  const scrollRaf = useRef(null);
  const pendingScrollTop = useRef(0);
  const [barCollapsed, setBarCollapsed] = useState(false);
  // Task 1 (2026-09-22 follow-up, 07-notifications.md) — a fullscreen
  // StoryViewer session must suppress the dock entirely, not just visually
  // (it fully unmounts here, so there's nothing left to intercept taps —
  // the same "hidden, not merely lower z-index" bar this ticket asks for
  // on iOS's separate-UIWindow overlay).
  const showBar = showsBottomBar(state.screen) && !state.storyViewer && !state.pulseOpen;

  useLayoutEffect(() => {
    const el = scrollRef.current;
    const target = scrollPositions.current[state.screen] || 0;
    if (el) el.scrollTop = target;
    lastScrollTop.current = target;
    if (scrollRaf.current) { cancelAnimationFrame(scrollRaf.current); scrollRaf.current = null; }
    setBarCollapsed(false);

    // Home task 3 (2026-09-21 follow-up) — this synchronous restore alone
    // wasn't enough for Home specifically: `loadHomeLiveEvents()`
    // (GocContext.jsx, added 1c62d4c) fetches asynchronously and can
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
    <div data-bb-theme={state.theme} style={{ position: 'fixed', inset: 0, display: 'flex', justifyContent: 'center', background: '#EFEBE0' }}>
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        style={{ width: '100%', maxWidth: 480, height: '100%', position: 'relative', overflowY: 'auto', WebkitOverflowScrolling: 'touch', background: 'var(--bb-bg)' }}
      >
        <div style={{ paddingBottom: showBar ? 92 : 0 }}>
          <Screen key={state.screen} />
        </div>
        {state.areaAsking && <AreaSheet />}
        {state.askingLocation && <LocationSheet />}
        {state.scanningQr && <QrScanSheet />}
        {state.photoViewer && <PhotoViewer />}
        {state.chatPhotoViewer && <ChatPhotoViewer />}
        {state.storyViewer && <StoryViewer />}
        {state.pulseOpen && <PulseViewer />}
        {state.reasonPrompt && <ReasonSheet />}
        {state.loading && <Loading label={T('Đang giữ chỗ cho bạn…', 'Holding your seat…')} />}
      </div>
      {showBar && <BottomTabBar collapsed={barCollapsed} />}
      <DockCreateButton />
      <ToastStack />
    </div>
  );
}

export default function App() {
  return (
    <GocProvider>
      <Shell />
    </GocProvider>
  );
}
