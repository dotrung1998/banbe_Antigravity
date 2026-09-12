import { useLayoutEffect, useRef } from 'react';
import { GocProvider, useGoc } from './state/GocContext.jsx';

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
};

function Shell() {
  const { state, T } = useGoc();
  const Screen = SCREENS[state.screen] || Home;
  const scrollRef = useRef(null);
  const scrollPositions = useRef({});

  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = scrollPositions.current[state.screen] || 0;
  }, [state.screen]);

  const handleScroll = (e) => {
    scrollPositions.current[state.screen] = e.currentTarget.scrollTop;
  };

  return (
    <div data-bb-theme={state.theme} style={{ position: 'fixed', inset: 0, display: 'flex', justifyContent: 'center', background: '#EFEBE0' }}>
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        style={{ width: '100%', maxWidth: 480, height: '100%', position: 'relative', overflowY: 'auto', WebkitOverflowScrolling: 'touch', background: 'var(--bb-bg)' }}
      >
        <Screen key={state.screen} />
        {state.areaAsking && <AreaSheet />}
        {state.askingLocation && <LocationSheet />}
        {state.scanningQr && <QrScanSheet />}
        {state.photoViewer && <PhotoViewer />}
        {state.reasonPrompt && <ReasonSheet />}
        {state.loading && <Loading label={T('Đang giữ chỗ cho bạn…', 'Holding your seat…')} />}
      </div>
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
