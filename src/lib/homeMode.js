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
export function homeViewAfterSync(prevOrganizerMode, prevHomeView, organizerMode) {
  if (!organizerMode) return 'goer';
  if (!prevOrganizerMode) return 'host';
  return prevHomeView === 'host' ? 'host' : 'goer';
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
