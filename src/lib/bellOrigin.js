// Where Home's bell was when it was tapped, so Notifications can burst out of it as a growing circle (and shrink back
// into it on close) — twin of iOS `AppState.homeBellFrame`. Read once, within 1.5s of the tap.
let last = null;

export function setBellOrigin(rect) {
  last = rect && rect.width > 0 ? { rect: { left: rect.left, top: rect.top, width: rect.width, height: rect.height }, at: performance.now() } : null;
}

export function takeBellOrigin() {
  const o = last && performance.now() - last.at <= 1500 ? last.rect : null;
  last = null;
  return o;
}
