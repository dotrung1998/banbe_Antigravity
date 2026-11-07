// Keychain charm motion model (pure: no DOM, no React, no timers).
// Shared numbers with iOS — see .claude/notes/35-*.md "Motion model".
// Damped pendulum about a fixed pivot: theta'' = -(g/L) sin(theta) - c theta'
// plus a vertical spring for stretch (fraction of the charm length L).
// Nothing here is ever persisted or sent anywhere.

export const MAX_ANGLE = 0.9;            // rad
export const MIN_STRETCH = -0.12;        // x L (lift)
export const MAX_STRETCH = 0.35;         // x L (pull down)
export const SENSOR_IMPULSE_CAP = 0.35;  // rad/s per sensor event
export const SENSOR_MIN_INTERVAL_MS = 120;
export const SWING_IMPULSE = 3.2;        // rad/s, button / keyboard swing (bounded)
export const MAX_SWING_IMPULSE = 4;      // hard cap for any caller-supplied swing
export const SETTLE = { theta: 0.004, omega: 0.02, stretch: 0.002 };
export const MAX_DT = 1 / 30;            // frames longer than this are clamped

const G_OVER_L = 16;     // 1/s^2
const ANGLE_DAMPING = 1.9; // 1/s
const STRETCH_K = 140;
const STRETCH_DAMPING = 9;
const SUBSTEP = 1 / 240;

export const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
const finite = (v) => (Number.isFinite(v) ? v : 0);

export function createState() {
  return { theta: 0, omega: 0, stretch: 0, stretchVel: 0 };
}

export function isSettled(st) {
  return Math.abs(st.theta) < SETTLE.theta && Math.abs(st.omega) < SETTLE.omega
    && Math.abs(st.stretch) < SETTLE.stretch && Math.abs(st.stretchVel) < SETTLE.omega;
}

/** Zeroes everything (used when a settled state snaps to rest). */
export function rest(st) {
  st.theta = 0; st.omega = 0; st.stretch = 0; st.stretchVel = 0;
  return st;
}

/** Advances the simulation by dt seconds (clamped). Mutates and returns st. */
export function step(st, dtSeconds) {
  let dt = clamp(finite(dtSeconds), 0, MAX_DT);
  while (dt > 1e-9) {
    const h = Math.min(SUBSTEP, dt);
    dt -= h;
    const alpha = -G_OVER_L * Math.sin(st.theta) - ANGLE_DAMPING * st.omega;
    st.omega += alpha * h;
    st.theta += st.omega * h;
    if (st.theta > MAX_ANGLE) { st.theta = MAX_ANGLE; if (st.omega > 0) st.omega = 0; }
    else if (st.theta < -MAX_ANGLE) { st.theta = -MAX_ANGLE; if (st.omega < 0) st.omega = 0; }
    const sa = -STRETCH_K * st.stretch - STRETCH_DAMPING * st.stretchVel;
    st.stretchVel += sa * h;
    st.stretch += st.stretchVel * h;
    if (st.stretch > MAX_STRETCH) { st.stretch = MAX_STRETCH; if (st.stretchVel > 0) st.stretchVel = 0; }
    else if (st.stretch < MIN_STRETCH) { st.stretch = MIN_STRETCH; if (st.stretchVel < 0) st.stretchVel = 0; }
  }
  return st;
}

/** Angular impulse (rad/s) added to omega, clamped to +/-cap. Returns the applied value. */
export function applyImpulse(st, amount, cap = SENSOR_IMPULSE_CAP) {
  const a = clamp(finite(amount), -cap, cap);
  st.omega += a;
  return a;
}

/** The "Swing" button / keyboard impulse: bounded, direction sign only matters. */
export function swing(st, direction = 1) {
  const d = direction < 0 ? -1 : 1;
  return applyImpulse(st, d * SWING_IMPULSE, MAX_SWING_IMPULSE);
}

/**
 * Pin the charm to a drag pose. dx/dy are pointer offsets from the grab point in
 * px, lengthPx the charm length. Vertical -> stretch/lift, horizontal -> angle.
 */
export function dragTo(st, dx, dy, lengthPx) {
  const L = lengthPx > 0 ? lengthPx : 1;
  st.stretch = clamp(finite(dy) / L, MIN_STRETCH, MAX_STRETCH);
  st.theta = clamp(finite(dx) / L * 1.2, -MAX_ANGLE, MAX_ANGLE);
  st.omega = 0; st.stretchVel = 0;
  return st;
}

/** Rate-limited sensor impulse. Returns the new lastAt (unchanged when skipped). */
export function sensorImpulse(st, accelX, nowMs, lastAt) {
  if (lastAt != null && nowMs - lastAt < SENSOR_MIN_INTERVAL_MS) return { lastAt, applied: 0 };
  const applied = applyImpulse(st, -finite(accelX) * 0.04, SENSOR_IMPULSE_CAP);
  return { lastAt: nowMs, applied };
}
