// Keychain appearance: defaults, manifest, layout math, RPC + signed-URL helpers.
// Layout/validation functions are pure (unit-testable); the rest touches supabase.
import { supabase } from './supabase.js';
import { KEYCHAIN_BUCKET } from './keychainUpload.js';

export const ANCHORS = ['top_left', 'top_right', 'bottom_left', 'bottom_right'];
export const SIZES = ['s', 'm', 'l'];
export const DEFAULT_KEYCHAIN = {
  enabled: false, designId: 'sky-star', anchor: 'top_right', size: 'm', motionEnabled: true, customAsset: null,
};

export const FALLBACK_MANIFEST = {
  version: 1, pivot: { x: 0.5, y: 0.045 }, imageSize: { width: 256, height: 384 }, anchors: ANCHORS,
  sizes: { s: 0.7, m: 1, l: 1.35 }, baseWidth: 64, groups: [], designs: [],
};

/** Coerces any server/user value into a safe config (unknown values -> defaults). */
export function normalizeKeychain(k) {
  const o = { ...DEFAULT_KEYCHAIN };
  if (!k || typeof k !== 'object') return o;
  o.enabled = k.enabled === true;
  if (typeof k.designId === 'string' && /^[a-z0-9-]{1,40}$/.test(k.designId)) o.designId = k.designId;
  if (ANCHORS.includes(k.anchor)) o.anchor = k.anchor;
  if (SIZES.includes(k.size)) o.size = k.size;
  o.motionEnabled = k.motionEnabled !== false;
  if (k.customAsset && typeof k.customAsset.path === 'string' && k.customAsset.id) {
    o.customAsset = { id: String(k.customAsset.id), path: k.customAsset.path, width: k.customAsset.width, height: k.customAsset.height };
  }
  return o;
}

/**
 * Geometry of the charm relative to a "frame" wrapping a profile card.
 * Anchors are PHYSICAL (left/right of the screen, not start/end), so a charm never
 * jumps to the other side under dir=rtl. Top anchors hang in a side gutter OUTSIDE the
 * card (the frame pads the card narrower by `gutter`, the charm may use 16px of the
 * screen margin); bottom anchors hang below the card (the frame reserves bottom space).
 * Gravity is always down, so nothing is mirrored; the pivot is the attach point.
 */
export function charmLayout(cfg, manifest = FALLBACK_MANIFEST, cardHeight = 92) {
  const scale = manifest.sizes?.[cfg.size] ?? 1;
  const w = Math.round((manifest.baseWidth || 64) * scale);
  const h = Math.round(w * (manifest.imageSize.height / manifest.imageSize.width));
  const pivotX = w * (manifest.pivot?.x ?? 0.5);
  const pivotY = h * (manifest.pivot?.y ?? 0.045);
  const bottom = cfg.anchor.startsWith('bottom');
  const left = cfg.anchor.endsWith('left');
  const gutter = bottom ? 0 : Math.max(0, w - 16);
  const pos = { position: 'absolute', width: w, height: h };
  if (bottom) { pos.bottom = 6; pos[left ? 'left' : 'right'] = 12; } else { pos.top = -pivotY; pos[left ? 'left' : 'right'] = -16; }
  const extraBottom = bottom ? Math.round(h - pivotY + 6) : Math.max(0, Math.round(h - pivotY - cardHeight + 4));
  return { w, h, pivotX, pivotY, gutterLeft: !bottom && left ? gutter : 0, gutterRight: !bottom && !left ? gutter : 0, extraBottom, pos };
}

// ---- manifest (static bundled asset, same origin) ----
let manifestPromise = null;
export function loadKeychainManifest() {
  if (!manifestPromise) {
    manifestPromise = fetch('/keychains/manifest.json')
      .then(r => (r.ok ? r.json() : FALLBACK_MANIFEST))
      .then(m => (m && Array.isArray(m.designs) ? m : FALLBACK_MANIFEST))
      .catch(() => FALLBACK_MANIFEST);
  }
  return manifestPromise;
}
export const designFile = (manifest, id) => manifest.designs.find(d => d.id === id)?.file || `${id}.png`;
export const designUrl = (manifest, id) => `/keychains/${designFile(manifest, id)}`;

// ---- signed URLs for custom art (cached per session) ----
const urlCache = new Map();
export async function signedCustomUrl(path) {
  const hit = urlCache.get(path);
  if (hit && hit.exp > Date.now() + 60_000) return hit.url;
  const { data, error } = await supabase.storage.from(KEYCHAIN_BUCKET).createSignedUrl(path, 3600);
  if (error || !data?.signedUrl) return null;
  urlCache.set(path, { url: data.signedUrl, exp: Date.now() + 3600_000 });
  return data.signedUrl;
}

// ---- RPCs ----
export async function fetchMyKeychain() {
  const { data, error } = await supabase.rpc('get_my_keychain');
  if (error || !data?.success) return null;
  return normalizeKeychain(data.keychain);
}
export async function fetchProfileKeychain(handle) {
  if (!handle) return null;
  const { data, error } = await supabase.rpc('get_profile_keychain', { p_handle: handle });
  if (error || !data?.success || !data.keychain) return null;
  const k = normalizeKeychain(data.keychain);
  return k.enabled ? k : null;
}
export async function saveMyKeychain(cfg) {
  const payload = {
    enabled: !!cfg.enabled, designId: cfg.designId, anchor: cfg.anchor, size: cfg.size, motionEnabled: !!cfg.motionEnabled,
    customAssetId: cfg.designId === 'custom' ? (cfg.customAsset?.id || null) : null,
  };
  const { data, error } = await supabase.rpc('save_my_keychain', { p_config: payload });
  if (error || !data?.success) throw new Error(error?.message || data?.error || 'GENERIC');
  return normalizeKeychain(data.keychain);
}

// ---- tiny shared store for the owner's own config ----
let mine = { loaded: false, value: null, uid: null };
const subs = new Set();
export const getMineSnapshot = () => mine;
export function setMine(value, uid) { mine = { loaded: true, value, uid: uid ?? mine.uid }; subs.forEach(f => f()); }
export function subscribeMine(f) { subs.add(f); return () => subs.delete(f); }
export function resetMine() { mine = { loaded: false, value: null, uid: null }; subs.forEach(f => f()); }
