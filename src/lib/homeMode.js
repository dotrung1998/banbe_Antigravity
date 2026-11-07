// Home view (Simple Shell follow-up, note 66). Pure, no React; tests/unit/homeMode.test.mjs, shared fixture
// tests/fixtures/home-mode.json (also read by apps/ios BanbeAppTests/HomeModeTests.swift against Lib/HomeMode.swift).
//
// The Home "Going out | Hosting" switch is a VIEW, not organizer mode. `homeView` ('goer' | 'host') is session-only
// state: never stored on the device, never read from a route. Host content renders only when organizer mode is on AND
// the view is 'host', so organizer mode off always means Going out, whatever the restored or deep-linked state.

export const HOME_VIEWS = ['goer', 'host'];

/** What Home actually shows. */
export function effectiveHomeView(organizerMode, homeView) {
  return organizerMode && homeView === 'host' ? 'host' : 'goer';
}

/**
 * `homeView` after a profile sync or an organizer-mode change. Organizer mode coming on (off before) opens Hosting;
 * staying on keeps what the person picked; off is always Going out.
 */
export function homeViewAfterSync(prevOrganizerMode, prevHomeView, organizerMode, stored = null) {
  if (!organizerMode) return 'goer';
  if (!prevOrganizerMode) return stored === 'goer' ? 'goer' : 'host';
  return prevHomeView === 'host' ? 'host' : 'goer';
}

// The last view the person picked on this device (iOS twin: HomeMode.stored). Written only on an explicit pick, read
// at session restore (`stored` above) so a reload reopens Going out if that is where they left Home; cleared on sign-out.
const HOME_VIEW_KEY = 'banbe.homeView';
export function readStoredHomeView() {
  try { const v = localStorage.getItem(HOME_VIEW_KEY); return HOME_VIEWS.includes(v) ? v : null; } catch { return null; }
}
export function storeHomeView(view) {
  try { if (view) localStorage.setItem(HOME_VIEW_KEY, view); else localStorage.removeItem(HOME_VIEW_KEY); } catch { /* private browsing */ }
}

/** The Hosting segment is locked (lock glyph, opens the Start hosting invitation) while organizer mode is off. */
export function hostSegmentLocked(organizerMode) {
  return !organizerMode;
}

/** What "Start hosting" does first: 'signIn' (guest), 'invite' (organizer mode off) or 'land' (already on). */
export function startHostingStep({ signedIn, organizerMode }) {
  if (!signedIn) return 'signIn';
  return organizerMode ? 'land' : 'invite';
}
