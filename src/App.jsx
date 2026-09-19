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
import Preferences from './screens/Preferences.jsx';
import EditName from './screens/EditName.jsx';
import Notifications from './screens/Notifications.jsx';
import EventList from './screens/EventList.jsx';
import Security from './screens/Security.jsx';
import PaymentDetails from './screens/PaymentDetails.jsx';
import Billing from './screens/Billing.jsx';
import Payout from './screens/Payout.jsx';
import Documents from './screens/Documents.jsx';
import DocumentView from './screens/DocumentView.jsx';
import Verifications from './screens/Verifications.jsx';
import Disputes from './screens/Disputes.jsx';
import ToastStack from './screens/ToastStack.jsx';
import Policy from './screens/Policy.jsx';
import MapExplore from './screens/MapExplore.jsx';

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
  billing: Billing,
  payout: Payout,
  documents: Documents,
  documentView: DocumentView,
  verifications: Verifications,
  disputes: Disputes,
  policy: Policy,
  mapExplore: MapExplore,
};

function Shell() {
  const { state, T } = useGoc();
  const Screen = SCREENS[state.screen] || Home;
  const scrollRef = useRef(null);
  const scrollPositions = useRef({});
  const lastScrollTop = useRef(0);
  const [barCollapsed, setBarCollapsed] = useState(false);
  const showBar = showsBottomBar(state.screen);

  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = scrollPositions.current[state.screen] || 0;
    lastScrollTop.current = scrollPositions.current[state.screen] || 0;
    setBarCollapsed(false);
  }, [state.screen]);

  // Mirrors iOS 26's onScrollDown minimize behavior: scrolling down shrinks
  // the floating pill a bit, scrolling up (or being at the very top) puts
  // it straight back to full size.
  const handleScroll = (e) => {
    const top = e.currentTarget.scrollTop;
    scrollPositions.current[state.screen] = top;
    const delta = top - lastScrollTop.current;
    if (top <= 4) setBarCollapsed(false);
    else if (delta > 6) setBarCollapsed(true);
    else if (delta < -6) setBarCollapsed(false);
    lastScrollTop.current = top;
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
        {state.reasonPrompt && <ReasonSheet />}
        {state.loading && <Loading label={T('Đang giữ chỗ cho bạn…', 'Holding your seat…')} />}
      </div>
      {showBar && <BottomTabBar collapsed={barCollapsed} />}
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
