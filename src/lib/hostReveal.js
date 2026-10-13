// Pure math for the host-profile reveal: dots leave the setup sheet, swirl into a rotating
// Earth-like sphere, then coalesce into the host card. No DOM here, so it is unit-testable.

export const REVEAL_TIMELINE = {
  gather: 900,     // sheet elements -> loose cloud, swirling
  form: 1700,      // cloud -> sphere
  spin: 1100,      // sphere rotates on its own
  coalesce: 1100,  // sphere -> host card
  flash: 900,      // dots fade out as the finished card lights up
};
export const REVEAL_TOTAL = REVEAL_TIMELINE.gather + REVEAL_TIMELINE.form + REVEAL_TIMELINE.spin + REVEAL_TIMELINE.coalesce + REVEAL_TIMELINE.flash;
export const REVEAL_FLASH_START = REVEAL_TOTAL - REVEAL_TIMELINE.flash;

/** 0..1 brightness of the card bloom at time t (0 outside the flash phase): quick rise, long fall. */
export function flashLevel(t) {
  const u = (t - REVEAL_FLASH_START) / REVEAL_TIMELINE.flash;
  if (u <= 0 || u >= 1) return 0;
  return Math.pow(Math.sin(Math.PI * Math.pow(u, 0.6)), 1.2);
}

export const clamp01 = v => Math.min(1, Math.max(0, v));
export const easeInOut = t => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
export const easeOut = t => 1 - Math.pow(1 - t, 3);
const lerp = (a, b, t) => a + (b - a) * t;

/** Deterministic PRNG so a given reveal looks the same in tests. */
export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** n roughly even points on the unit sphere. */
export function fibonacciSphere(n) {
  const pts = [];
  const golden = Math.PI * (3 - Math.sqrt(5));
  for (let i = 0; i < n; i++) {
    const y = 1 - (i / Math.max(1, n - 1)) * 2;
    const r = Math.sqrt(Math.max(0, 1 - y * y));
    const th = golden * i;
    pts.push({ x: Math.cos(th) * r, y, z: Math.sin(th) * r });
  }
  return pts;
}

/** Cheap continent-ish mask (true = "land", drawn brighter). Deterministic in lat/lon. */
export function isLand(p) {
  const lon = Math.atan2(p.z, p.x);
  const lat = Math.asin(p.y);
  const v = Math.sin(lon * 2 + 0.7) * Math.cos(lat * 3 - 0.4)
    + 0.6 * Math.sin(lon * 5 - lat * 2 + 1.3)
    + 0.35 * Math.cos(lon * 9 + lat * 4);
  return v > 0.25;
}

export function sampleInRect(rect, rand) {
  return { x: rect.left + rand() * rect.width, y: rect.top + rand() * rect.height };
}

export function sampleInRoundedRect(rect, radius, rand) {
  const r = Math.min(radius, rect.width / 2, rect.height / 2);
  for (let i = 0; i < 8; i++) {
    const p = sampleInRect(rect, rand);
    const dx = Math.max(rect.left + r - p.x, 0, p.x - (rect.left + rect.width - r));
    const dy = Math.max(rect.top + r - p.y, 0, p.y - (rect.top + rect.height - r));
    if (dx * dx + dy * dy <= r * r) return p;
  }
  return sampleInRect(rect, rand);
}

/**
 * Build the particle set. `sources`/`target` are rect-likes {left, top, width, height} in canvas
 * coordinates; `cx, cy, radius` the sphere. Particles split across source rects by area.
 */
export function buildParticles({ count, sources, target, cx, cy, radius, seed = 7, targetRadius = 22 }) {
  const rand = mulberry32(seed);
  const sphere = fibonacciSphere(count);
  const totalArea = sources.reduce((a, r) => a + r.width * r.height, 0) || 1;
  const parts = [];
  for (let i = 0; i < count; i++) {
    let pick = rand() * totalArea; let src = sources[0];
    for (const r of sources) { pick -= r.width * r.height; if (pick <= 0) { src = r; break; } }
    const start = src ? sampleInRoundedRect(src, src.radius ?? 14, rand) : { x: cx, y: cy };
    const ang = rand() * Math.PI * 2;
    const dist = radius * (0.9 + rand() * 1.1);
    const dst = target ? sampleInRoundedRect(target, targetRadius, rand) : { x: cx + (rand() - 0.5) * radius, y: cy + (rand() - 0.5) * radius };
    parts.push({
      sx: start.x, sy: start.y,
      cloudX: cx + Math.cos(ang) * dist, cloudY: cy + Math.sin(ang) * dist * 0.8,
      sphere: sphere[i], land: isLand(sphere[i]),
      dx: dst.x, dy: dst.y,
      size: 0.9 + rand() * 1.1,
      swirl: (0.8 + rand() * 0.6) * (rand() < 0.5 ? 1 : 1) , // all dots swirl the same way
      delay: rand() * 0.18,
    });
  }
  return parts;
}

/** Position + draw hints for one particle at time t (ms). */
export function particleState(p, t, { cx, cy, radius, tilt = 0.35, spinRate = 0.0011 }) {
  const { gather, form, spin, coalesce } = REVEAL_TIMELINE;
  const tForm0 = gather, tSpin0 = gather + form, tCoal0 = tSpin0 + spin, tFlash0 = tCoal0 + coalesce;
  const sphereAt = (time) => {
    const rot = time * spinRate;
    const cosR = Math.cos(rot), sinR = Math.sin(rot);
    let x = p.sphere.x * cosR - p.sphere.z * sinR;
    let z = p.sphere.x * sinR + p.sphere.z * cosR;
    const cosT = Math.cos(tilt), sinT = Math.sin(tilt);
    const y = p.sphere.y * cosT - z * sinT;
    z = p.sphere.y * sinT + z * cosT;
    return { x: cx + x * radius, y: cy + y * radius, depth: z };
  };
  const swirlAround = (x, y, turns) => {
    const ox = x - cx, oy = y - cy;
    const a = turns * Math.PI * 2, c = Math.cos(a), s = Math.sin(a);
    return { x: cx + ox * c - oy * s, y: cy + ox * s + oy * c };
  };
  let x, y, depth = 0, alpha = 1;
  let shade = 1; // weight of the sphere look (near dots bigger/brighter, far dim, land brighter)
  if (t < tForm0) {
    // Dots ARE the form's elements: full strength from the first frame, then they peel away.
    const k = easeInOut(clamp01((t / gather - p.delay) / (1 - p.delay)));
    const base = { x: lerp(p.sx, p.cloudX, k), y: lerp(p.sy, p.cloudY, k) };
    const sw = swirlAround(base.x, base.y, 0.25 * p.swirl * k);
    x = sw.x; y = sw.y; alpha = 0.9 + 0.1 * k;
    shade = 0;
  } else if (t < tSpin0) {
    const k = easeInOut(clamp01((t - tForm0) / form));
    const target = sphereAt(t);
    const base = { x: lerp(p.cloudX, target.x, k), y: lerp(p.cloudY, target.y, k) };
    const sw = swirlAround(base.x, base.y, (1 - k) * 1.15 * p.swirl);
    x = sw.x; y = sw.y; depth = target.depth * k;
    shade = k;
  } else if (t < tCoal0) {
    const s = sphereAt(t);
    x = s.x; y = s.y; depth = s.depth;
  } else if (t < tFlash0) {
    const k = easeInOut(clamp01((t - tCoal0) / coalesce));
    const s = sphereAt(t);
    const base = { x: lerp(s.x, p.dx, k), y: lerp(s.y, p.dy, k) };
    const sw = swirlAround(base.x, base.y, (1 - k) * 0.12 * p.swirl);
    x = lerp(sw.x, p.dx, k * k); y = lerp(sw.y, p.dy, k * k);
    depth = s.depth * (1 - k);
    shade = 1 - k;
  } else {
    // The card is assembled: dots settle in place and fade as the real card lights up.
    x = p.dx; y = p.dy; shade = 0;
    alpha = 1 - clamp01((t - tFlash0) / 320);
  }
  const d = (depth + 1) / 2; // 0 far .. 1 near
  const scale = lerp(1, 0.65 + 0.7 * d, shade);
  alpha *= lerp(1, (0.25 + 0.75 * d) * (p.land ? 1 : 0.62), shade);
  return { x, y, r: p.size * scale, alpha: clamp01(alpha), depth };
}
