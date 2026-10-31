// Dock layout (note 66, Simple Shell Phase 4). Pure, no React; tests/unit/dockLayout.test.mjs.
//
// Switch `simple_shell` OFF: the dock is unchanged (home, map, schedule, inbox, profile; "+" beside it in organizer
// mode only). ON: Map leaves the dock (it is a Home view now) and a "+" sits INSIDE the bar in the centre slot:
// home, schedule, [create], inbox, profile. The "+" is not a tab: it never takes the selected state and the root
// swipe walks dockOrder() only. Scrub-to-select DOES see it (scrubTarget): releasing a drag over "+" opens the "+"
// sheet instead of snapping back or landing on a neighbour (note 66 follow-up).

export const CREATE_SLOT = 'create';

const LEGACY_ORDER = ['home', 'mapExplore', 'schedule', 'inbox', 'profile'];
const SIMPLE_ORDER = ['home', 'schedule', 'inbox', 'profile'];

/** Root tabs in swipe / scrub order (no "+"). */
export function dockOrder(simpleShell) {
  return simpleShell ? SIMPLE_ORDER : LEGACY_ORDER;
}

/** Every slot the bar lays out left to right, the "+" included when it lives inside the bar. */
export function dockSlots(simpleShell) {
  return simpleShell ? ['home', 'schedule', CREATE_SLOT, 'inbox', 'profile'] : LEGACY_ORDER;
}

/** Which tab looks selected on `screen`; Map highlights Home when it is a Home view. null = none. */
export function dockHighlightFor(screen, simpleShell) {
  if (simpleShell && screen === 'mapExplore') return 'home';
  return dockOrder(simpleShell).includes(screen) ? screen : null;
}

/** The root tab a swipe from `screen` lands on (dir +1 = next, -1 = previous), or null at an end / off the dock. */
export function dockNeighbor(screen, dir, simpleShell) {
  const order = dockOrder(simpleShell);
  const i = order.indexOf(screen);
  if (i === -1) return null;
  return order[i + dir] || null;
}

/**
 * What a dock drag is over. `fraction` = finger x across the bar's slots (0 = left edge of the first slot, 1 = right
 * edge of the last), clamped. Each slot is an equal share: { kind: 'tab', id } for a tab, { kind: 'create' } for the
 * centre "+". Shared fixture: tests/fixtures/dock-scrub.json (iOS DockLayout.scrubTarget).
 */
export function scrubTarget(fraction, simpleShell) {
  const slots = dockSlots(simpleShell);
  const f = Number.isFinite(fraction) ? Math.max(0, Math.min(1, fraction)) : 0;
  const i = Math.min(slots.length - 1, Math.floor(f * slots.length));
  return slots[i] === CREATE_SLOT ? { kind: 'create' } : { kind: 'tab', id: slots[i] };
}
