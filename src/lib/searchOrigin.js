// Where Home's search bar was when it was tapped, so the Search screen can start its own field right there and glide
// it up into its header (twin of iOS `AppState.searchEntranceFrom`). Read once, within 1.5s of the tap.
let last = null;

export function setSearchOrigin(rect) {
  last = rect && rect.width > 0 ? { rect: { left: rect.left, top: rect.top, width: rect.width, height: rect.height }, at: performance.now() } : null;
}

export function takeSearchOrigin() {
  const o = last && performance.now() - last.at <= 1500 ? last.rect : null;
  last = null;
  return o;
}
