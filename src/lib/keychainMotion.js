// Keychain motion controller. No React. Everything environmental (raf, clock,
// document, window, navigator) is injectable so it can be tested with fakes.
// The frame loop runs ONLY while: state unsettled AND document visible AND
// motion enabled AND not prefers-reduced-motion. Zero idle loops.
import {
  createState, step, isSettled, rest, dragTo, swing as physSwing, sensorImpulse, MAX_DT,
} from './keychainPhysics.js';

function defaultEnv() {
  const w = typeof window !== 'undefined' ? window : undefined;
  return {
    raf: w?.requestAnimationFrame?.bind(w),
    caf: w?.cancelAnimationFrame?.bind(w),
    now: () => (typeof performance !== 'undefined' ? performance.now() : Date.now()),
    document: typeof document !== 'undefined' ? document : undefined,
    window: w,
    navigator: typeof navigator !== 'undefined' ? navigator : undefined,
    DeviceMotionEvent: typeof DeviceMotionEvent !== 'undefined' ? DeviceMotionEvent : undefined,
  };
}

/**
 * opts: { env?, enabled?, lengthPx (number|()=>number), onFrame(state), onHighlight?() }
 */
export function createKeychainController(opts = {}) {
  const env = { ...defaultEnv(), ...(opts.env || {}) };
  const getLength = () => (typeof opts.lengthPx === 'function' ? opts.lengthPx() : (opts.lengthPx || 100));
  const state = createState();
  let enabled = opts.enabled !== false;
  let destroyed = false;
  let rafId = null;
  let lastT = 0;
  let dragging = false;
  let grabX = 0, grabY = 0;
  let vibrated = { grab: false, release: false };
  let tiltGranted = false;
  let motionListener = null;
  let lastSensorAt = null;
  let reduced = false;
  let mql = null;

  const doc = env.document;
  const win = env.window;
  const visible = () => !doc || doc.visibilityState !== 'hidden';
  const canAnimate = () => !destroyed && enabled && visible() && !reduced;

  const emit = () => opts.onFrame && opts.onFrame(state);

  function vibrate() {
    try { env.navigator?.vibrate?.(12); } catch { /* unsupported / blocked: ignore */ }
  }

  function stopLoop() {
    if (rafId != null) { try { env.caf && env.caf(rafId); } catch { /* ignore */ } rafId = null; }
  }

  function tick(t) {
    rafId = null;
    if (!canAnimate() || dragging) return;
    const dt = Math.min(MAX_DT, Math.max(0, (t - lastT) / 1000));
    lastT = t;
    step(state, dt);
    if (isSettled(state)) { rest(state); emit(); return; }
    emit();
    rafId = env.raf(tick);
  }

  function ensureLoop() {
    if (rafId != null || dragging || !env.raf) return;
    if (!canAnimate() || isSettled(state)) return;
    lastT = env.now();
    rafId = env.raf(tick);
  }

  function syncSensors() {
    const want = tiltGranted && canAnimate() && !!win?.addEventListener;
    if (want && !motionListener) {
      motionListener = (e) => {
        const ax = e?.accelerationIncludingGravity?.x;
        if (ax == null) return;
        const r = sensorImpulse(state, ax, env.now(), lastSensorAt);
        lastSensorAt = r.lastAt;
        if (r.applied) ensureLoop();
      };
      win.addEventListener('devicemotion', motionListener);
    } else if (!want && motionListener) {
      win.removeEventListener('devicemotion', motionListener);
      motionListener = null;
    }
  }

  function onVisibility() {
    if (!visible()) stopLoop(); else ensureLoop();
    syncSensors();
  }
  function onReducedChange(e) {
    reduced = !!(e && typeof e.matches === 'boolean' ? e.matches : mql?.matches);
    if (reduced) { stopLoop(); rest(state); emit(); } else ensureLoop();
    syncSensors();
  }

  // Wire environment listeners.
  doc?.addEventListener?.('visibilitychange', onVisibility);
  if (win?.matchMedia) {
    try {
      mql = win.matchMedia('(prefers-reduced-motion: reduce)');
      reduced = !!mql.matches;
      mql.addEventListener ? mql.addEventListener('change', onReducedChange) : mql.addListener?.(onReducedChange);
    } catch { mql = null; }
  }

  const api = {
    state,
    get reducedMotion() { return reduced; },
    get running() { return rafId != null; },
    get tiltActive() { return !!motionListener; },

    setEnabled(v) {
      enabled = !!v;
      if (!enabled) { stopLoop(); rest(state); emit(); } else ensureLoop();
      syncSensors();
    },

    /** Pointer gesture. x/y are client coordinates. */
    grab(x, y) {
      if (destroyed || !enabled || reduced) { if (reduced && opts.onHighlight) opts.onHighlight(); return false; }
      dragging = true; grabX = x; grabY = y;
      stopLoop();
      if (!vibrated.grab) { vibrated.grab = true; vibrate(); }
      return true;
    },
    move(x, y) {
      if (!dragging) return;
      dragTo(state, x - grabX, y - grabY, getLength());
      emit();
    },
    release() {
      if (!dragging) return;
      dragging = false;
      if (!vibrated.release) { vibrated.release = true; vibrate(); }
      vibrated = { grab: false, release: false };
      ensureLoop();
    },
    cancel() { api.release(); },

    /** Keyboard / button swing. Reduced motion: a non-moving highlight only. */
    swing(direction = 1) {
      if (destroyed) return;
      if (reduced || !enabled) { opts.onHighlight && opts.onHighlight(); return; }
      physSwing(state, direction);
      ensureLoop();
    },

    /** Must be called from a user gesture handler (a tap on "Enable tilt"). */
    async enableTilt() {
      const DME = env.DeviceMotionEvent;
      if (!DME) return 'unsupported';
      if (win && win.isSecureContext === false) return 'insecure';
      try {
        if (typeof DME.requestPermission === 'function') {
          const r = await DME.requestPermission();
          if (r !== 'granted') return 'denied';
        }
      } catch { return 'denied'; }
      if (destroyed) return 'denied';
      tiltGranted = true;
      syncSensors();
      return 'granted';
    },
    disableTilt() { tiltGranted = false; syncSensors(); },

    destroy() {
      destroyed = true;
      stopLoop();
      tiltGranted = false;
      syncSensors();
      doc?.removeEventListener?.('visibilitychange', onVisibility);
      if (mql) { mql.removeEventListener ? mql.removeEventListener('change', onReducedChange) : mql.removeListener?.(onReducedChange); }
    },
  };
  return api;
}
