import { useEffect, useRef } from 'react';
import { screenToPath, pathToRoute, TRANSIENT_SCREENS } from './routes.js';

// Deep link the visitor opened the app on (read once, before React mounts).
// Paths already handled by BanBeContext's own shared-link boot code (/u/<handle>,
// /org/<id>, /surveys/<id>, ?org=) are skipped: that code opens the screen
// itself, so the URL already matches the state.
function readBootRoute() {
  if (typeof window === 'undefined') return null;
  const { pathname, search } = window.location;
  if (pathname === '/' || new URLSearchParams(search).has('org')) return null;
  if (/^\/(u\/[^/]+|org\/[^/]+|surveys\/[^/]+)\/?$/.test(pathname)) return null;
  const route = pathToRoute(pathname);
  if (!route || TRANSIENT_SCREENS.has(route.screen)) return null;
  return route;
}
const bootRoute = readBootRoute();

// Keeps the browser URL and `state.screen` in step, both ways:
//  - screen change in the app  -> pushState (or replaceState while onboarding)
//  - back / forward            -> popstate -> open the screen for that path
//  - cold load on a deep link  -> held until the user is through splash and
//                                 sign-in, then applied once (never fought by
//                                 the URL writer in the meantime).
export default function useUrlSync(goc) {
  const { state, set } = goc;
  const banbeRef = useRef(goc);
  banbeRef.current = goc;
  const pending = useRef(bootRoute);
  const prevScreen = useRef(state.screen);

  const applyRoute = (route) => {
    const g = banbeRef.current;
    let target = route;
    if (target.needs && !target.needs(g.state)) {
      target = pathToRoute(target.parent || '/') || { screen: 'home', params: {} };
    }
    if (target.open && typeof g[target.open] === 'function') g[target.open](...(target.openArgs || []));
    else g.set({ screen: target.screen, ...(target.params || {}) });
  };

  // state -> URL
  useEffect(() => {
    const { screen } = state;
    const wasScreen = prevScreen.current;
    prevScreen.current = screen;

    if (pending.current) {
      const waiting = TRANSIENT_SCREENS.has(screen) || screen === 'home';
      if (waiting) {
        // Through onboarding/sign-in and sitting on Home with a session: go
        // to the linked screen. Otherwise leave the URL as the visitor typed it.
        const guestOk = pending.current.screen === 'policy' && screen === 'login' && state.sessionChecked && !state.user;
        if ((screen === 'home' && state.user) || guestOk) {
          const route = pending.current;
          pending.current = null;
          applyRoute(route);
        }
        return;
      }
      pending.current = null; // the user went somewhere else on their own
    }

    const path = screenToPath(state);
    if (path == null || window.location.pathname === path) return;
    const replace = TRANSIENT_SCREENS.has(wasScreen) || (screen === 'login' && !state.user);
    window.history[replace ? 'replaceState' : 'pushState']({ screen }, '', path);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    state.screen, state.user, state.eventKey, state.accountGroupKey, state.eventListMode, state.publicProfileHandle,
    state.organizerProfileId, state.organizerTeamOrganizerId, state.surveyPublicId, state.documentId,
    state.attendanceEventKey, state.paymentBookingId, state.sessionChecked,
  ]);

  // URL -> state (browser back / forward)
  useEffect(() => {
    const onPop = () => {
      pending.current = null;
      const route = pathToRoute(window.location.pathname);
      if (route) applyRoute(route);
      else banbeRef.current.set({ screen: 'home' });
    };
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  void set;
}
