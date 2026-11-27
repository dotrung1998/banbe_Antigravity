/**
 * The shot list for the onboarding motion study.
 *
 * Every shot is a REAL screenshot of banbe, saved under `public/screens/`.
 * `ready: false` means "not captured yet": the rig then draws a capture-request
 * tile with the exact instruction, and never a made-up screen. Flip it to true
 * in the same commit that adds the PNG. That rule is the whole reason this rig
 * exists (see ../README.md, docs/prototypes/README.md).
 *
 * Capture recipe (write it in capture.md next to the PNGs):
 *   390x844 / 834x1194 / 1440x900, production data, real live events,
 *   motion frozen, no toast, no cursor, status bar as shipped.
 */
export const SHOTS = [
  {
    id: 'home',
    src: 'screens/01-home.png',
    ready: false,
    label: 'Home · For You',
    capture: '390x844 · production · 3 live events in view',
    move: 'push',
    seconds: 3.2,
  },
  {
    id: 'event',
    src: 'screens/02-event.png',
    ready: false,
    label: 'Event Detail · vé giấy',
    capture: '390x844 · one real event · price + seats left visible',
    move: 'pan-left',
    seconds: 3.2,
  },
  {
    id: 'ticket',
    src: 'screens/03-ticket.png',
    ready: false,
    label: 'Confirmed · ticket',
    capture: '390x844 · a real booking of yours · QR visible',
    move: 'settle',
    seconds: 3.2,
  },
];

/** Frames are derived from `seconds` so the timeline stays readable. */
export const FPS = 30;
export const FRAMES_PER_SHOT = (shot) => Math.round(shot.seconds * FPS);
