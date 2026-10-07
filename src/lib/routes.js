// URL <-> screen mapping. The app keeps its screen in `state.screen` (no
// router library), so this file is the single table that turns the current
// state into a browser path and a path back into a screen + params. The sync
// itself lives in src/lib/useUrlSync.js.
//
// Every screen in App.jsx's SCREENS map has a path here. Screens that hang
// off an id carry it as a path segment (/org/<id>, /u/<handle>,
// /payment/<bookingId> ...). A few screens can only be rebuilt from
// in-memory state (a half-filled reservation, an open chat thread, a booking
// confirmation): `needs` says what must already be in state, and `parent` is
// the path used instead on a cold load or when that state is gone, so a
// pasted/refreshed link lands somewhere real rather than on a broken screen.

const enc = encodeURIComponent;
const dec = (v) => { try { return decodeURIComponent(v); } catch { return v; } };

// screen -> fixed path
const STATIC = {
  home: '/',
  mapExplore: '/map',
  inbox: '/inbox',
  profile: '/profile',
  login: '/login',
  resetPassword: '/reset-password',
  langPick: '/welcome/language',
  themePick: '/welcome/theme',
  hostIntro: '/host',
  create: '/host/create',
  dashboard: '/host/dashboard',
  notifications: '/notifications',
  preferences: '/settings',
  security: '/settings/security',
  eventPreferences: '/settings/event-preferences',
  editName: '/profile/name',
  editProfile: '/profile/edit',
  refundAccounts: '/refunds/accounts',
  myRefunds: '/refunds',
  billing: '/billing',
  payout: '/payout',
  documents: '/documents',
  verifications: '/verifications',
  disputes: '/disputes',
  adminEvents: '/admin/events',
  adminTestAccounts: '/admin/test-accounts',
  policy: '/policy',
  faq: '/help/faq',
  reports: '/reports',
  surveysHosting: '/surveys',
  confirmed: '/ticket',
  refunded: '/refunded',
};

const PATH_TO_STATIC = Object.fromEntries(Object.entries(STATIC).map(([screen, path]) => [path, screen]));

// Screens that are part of the sign-in / onboarding sequence. While a deep
// link is waiting for the user to get through these, the URL is left alone.
export const TRANSIENT_SCREENS = new Set(['splash', 'langPick', 'themePick', 'login']);

/** state -> path (null = this screen has no URL, leave the address bar alone). */
export function screenToPath(st) {
  const { screen } = st;
  if (screen === 'splash') return null;
  if (STATIC[screen]) return STATIC[screen];
  switch (screen) {
    case 'event': return st.eventKey ? `/event/${enc(st.eventKey)}` : '/';
    case 'reserve': return st.eventKey ? `/event/${enc(st.eventKey)}/reserve` : '/';
    case 'chat': return st.eventKey ? `/event/${enc(st.eventKey)}/chat` : '/';
    case 'accountGroup': return st.accountGroupKey ? `/profile/group/${enc(st.accountGroupKey)}` : '/profile';
    case 'eventList': return `/events/${enc(st.eventListMode || 'going')}`;
    case 'publicProfile': return st.publicProfileHandle ? `/u/${enc(st.publicProfileHandle)}` : '/profile';
    case 'organizerProfile': return st.organizerProfileId ? `/org/${enc(st.organizerProfileId)}` : '/';
    case 'organizerTeam': return st.organizerTeamOrganizerId ? `/org/${enc(st.organizerTeamOrganizerId)}/team` : '/';
    case 'guide': return st.guideKey ? `/help/guides/${enc(st.guideKey)}` : '/profile/group/helpLegal';
    case 'surveyPublic': return st.surveyPublicId ? `/surveys/${enc(st.surveyPublicId)}` : '/surveys';
    case 'documentView': return st.documentId ? `/documents/${enc(st.documentId)}` : '/documents';
    case 'attendance': return st.attendanceEventKey ? `/host/attendance/${enc(st.attendanceEventKey)}` : '/host/dashboard';
    case 'paymentDetails': return st.paymentBookingId ? `/payment/${enc(st.paymentBookingId)}` : '/payment';
    default: return '/';
  }
}

const EVENT_LIST_MODES = new Set(['going', 'saved', 'completed']);

/**
 * path -> { screen, params, parent?, needs? } or null for an unknown path.
 * `params` are plain state fields; `open` names a context action to call with
 * `openArgs` instead of a bare set() when the screen needs data fetched.
 */
export function pathToRoute(pathname) {
  const path = pathname.length > 1 ? pathname.replace(/\/+$/, '') : pathname;
  if (PATH_TO_STATIC[path]) {
    const screen = PATH_TO_STATIC[path];
    if (screen === 'confirmed' || screen === 'refunded') return { screen, params: {}, parent: '/', needs: () => false };
    return { screen, params: {} };
  }
  let m;
  if ((m = path.match(/^\/event\/([^/]+)$/))) return { screen: 'event', params: { eventKey: dec(m[1]) } };
  // The retired /event/<key>/organizer page (merged into the host profile,
  // /org/<id>): an old link resolves the organizer from the event key.
  if ((m = path.match(/^\/event\/([^/]+)\/organizer$/))) return { screen: 'organizerProfile', params: {}, open: 'openOrganizerOfEvent', openArgs: [dec(m[1]), 'home'] };
  if ((m = path.match(/^\/event\/([^/]+)\/reserve$/))) {
    const key = dec(m[1]);
    return { screen: 'reserve', params: {}, parent: `/event/${enc(key)}`, needs: (st) => st.eventKey === key && (st.attendeeDrafts || []).length > 0 };
  }
  if ((m = path.match(/^\/event\/([^/]+)\/chat$/))) {
    const key = dec(m[1]);
    return { screen: 'chat', params: {}, parent: `/event/${enc(key)}`, needs: (st) => st.eventKey === key && !!st.chatBack };
  }
  if ((m = path.match(/^\/profile\/group\/([^/]+)$/))) return { screen: 'accountGroup', params: { accountGroupKey: dec(m[1]) } };
  if ((m = path.match(/^\/events\/([^/]+)$/)) && EVENT_LIST_MODES.has(dec(m[1]))) {
    const mode = dec(m[1]);
    return { screen: 'eventList', params: {}, open: mode === 'saved' ? 'goSavedList' : mode === 'completed' ? 'goCompletedList' : 'goGoingList', openArgs: [] };
  }
  if ((m = path.match(/^\/u\/([^/]+)$/))) return { screen: 'publicProfile', params: {}, open: 'openPublicProfile', openArgs: [dec(m[1]).toLowerCase(), 'home'] };
  if ((m = path.match(/^\/org\/([^/]+)$/))) return { screen: 'organizerProfile', params: {}, open: 'openOrganizerProfile', openArgs: [dec(m[1]), 'home'] };
  if ((m = path.match(/^\/org\/([^/]+)\/team$/))) return { screen: 'organizerTeam', params: {}, open: 'openOrganizerTeam', openArgs: [dec(m[1]), 'organizerProfile'] };
  if ((m = path.match(/^\/help\/guides\/([^/]+)$/))) return { screen: 'guide', params: { guideKey: dec(m[1]) } };
  if ((m = path.match(/^\/surveys\/([^/]+)$/))) return { screen: 'surveyPublic', params: {}, open: 'goSurveyPublic', openArgs: [dec(m[1]), 'home'] };
  if ((m = path.match(/^\/documents\/([^/]+)$/))) {
    const id = dec(m[1]);
    return { screen: 'documentView', params: {}, parent: '/documents', needs: (st) => String(st.documentId) === id && (st.documents || []).length > 0 };
  }
  if ((m = path.match(/^\/host\/attendance\/([^/]+)$/))) {
    const key = dec(m[1]);
    return { screen: 'attendance', params: {}, parent: '/host/dashboard', needs: (st) => st.attendanceEventKey === key };
  }
  if ((m = path.match(/^\/payment\/([^/]+)$/))) return { screen: 'paymentDetails', params: { paymentBookingId: dec(m[1]), paymentBack: 'profile', paymentProofError: '' } };
  if (path === '/payment') return { screen: 'profile', params: {} };
  return null;
}
