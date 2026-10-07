import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { createKeychainController } from '../lib/keychainMotion.js';
import {
  FALLBACK_MANIFEST, charmLayout, designUrl, loadKeychainManifest, signedCustomUrl, normalizeKeychain,
  fetchMyKeychain, fetchProfileKeychain, getMineSnapshot, setMine, subscribeMine,
} from '../lib/keychain.js';

export function useKeychainManifest() {
  const [m, setM] = useState(FALLBACK_MANIFEST);
  useEffect(() => { let on = true; loadKeychainManifest().then(x => { if (on) setM(x); }); return () => { on = false; }; }, []);
  return m;
}

/** Owner's own keychain (shared store so Edit appearance saves update the profile card live). */
export function useMyKeychain() {
  const { state } = useBanBe();
  const uid = state.user?.id || null;
  const snap = useSyncExternalStore(subscribeMine, getMineSnapshot);
  useEffect(() => {
    if (!uid || (snap.loaded && snap.uid === uid)) return undefined;
    let on = true;
    fetchMyKeychain().then(v => { if (on) setMine(v, uid); });
    return () => { on = false; };
  }, [uid, snap.loaded, snap.uid]);
  return snap.loaded && snap.uid === uid ? snap.value : null;
}

/** A visited profile's keychain (null unless the owner enabled it). */
export function useProfileKeychain(handle) {
  const [k, setK] = useState(null);
  useEffect(() => {
    let on = true; setK(null);
    if (handle) fetchProfileKeychain(handle).then(v => { if (on) setK(v); });
    return () => { on = false; };
  }, [handle]);
  return k;
}

/**
 * Wraps a profile card (card must have margin 0; pass its margin here) and reserves the
 * gutter/bottom space the charm needs so it never covers name, QR or buttons.
 */
export function KeychainFrame({ config, margin, cardHeight = 92, children, testId, label, onController, srcOverride, style }) {
  const manifest = useKeychainManifest();
  const cfg = config && config.enabled ? normalizeKeychain(config) : null;
  const lay = cfg ? charmLayout(cfg, manifest, cardHeight) : null;
  return (
    <div style={{ position: 'relative', margin, paddingLeft: lay?.gutterLeft || 0, paddingRight: lay?.gutterRight || 0, paddingBottom: lay?.extraBottom || 0, ...style }} data-testid={testId}>
      {children}
      {cfg && <KeychainCharm config={cfg} manifest={manifest} layout={lay} label={label} onController={onController} srcOverride={srcOverride} />}
    </div>
  );
}

export default function KeychainCharm({ config, manifest, layout, label, onController, srcOverride }) {
  const { T } = useBanBe();
  const cfg = useMemo(() => normalizeKeychain(config), [config]);
  const lay = layout || charmLayout(cfg, manifest || FALLBACK_MANIFEST);
  const imgWrap = useRef(null);
  const ctrlRef = useRef(null);
  const [src, setSrc] = useState(null);
  const [lit, setLit] = useState(false);

  useEffect(() => {
    let on = true;
    if (srcOverride) { setSrc(srcOverride); return undefined; }
    if (cfg.designId === 'custom') {
      setSrc(null);
      if (cfg.customAsset?.path) signedCustomUrl(cfg.customAsset.path).then(u => { if (on) setSrc(u); });
    } else setSrc(designUrl(manifest || FALLBACK_MANIFEST, cfg.designId));
    return () => { on = false; };
  }, [cfg.designId, cfg.customAsset?.path, manifest, srcOverride]);

  useEffect(() => {
    const ctrl = createKeychainController({
      lengthPx: lay.h,
      enabled: cfg.motionEnabled,
      onFrame: (st) => {
        const el = imgWrap.current;
        if (el) el.style.transform = `translateY(${(st.stretch * lay.h).toFixed(2)}px) rotate(${st.theta.toFixed(4)}rad) scaleY(${(1 + st.stretch * 0.25).toFixed(4)})`;
      },
      onHighlight: () => { setLit(true); setTimeout(() => setLit(false), 450); },
    });
    ctrlRef.current = ctrl;
    onController && onController(ctrl);
    return () => { ctrl.destroy(); ctrlRef.current = null; onController && onController(null); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lay.h]);
  useEffect(() => { ctrlRef.current?.setEnabled(cfg.motionEnabled); }, [cfg.motionEnabled]);

  const aria = label || T('Móc khoá trang trí hồ sơ. Nhấn Enter hoặc Space để lắc.', 'Decorative profile keychain. Press Enter or Space to swing it.');
  const onDown = (e) => {
    if (e.button != null && e.button !== 0) return;
    try { e.currentTarget.setPointerCapture(e.pointerId); } catch { /* ignore */ }
    ctrlRef.current?.grab(e.clientX, e.clientY);
  };
  return (
    <div
      role="button" tabIndex={0} aria-label={aria} data-testid="keychain-charm" data-design={cfg.designId} data-anchor={cfg.anchor}
      onPointerDown={onDown}
      onPointerMove={(e) => ctrlRef.current?.move(e.clientX, e.clientY)}
      onPointerUp={() => ctrlRef.current?.release()}
      onPointerCancel={() => ctrlRef.current?.cancel()}
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); ctrlRef.current?.swing(1); } }}
      style={{
        ...lay.pos, touchAction: 'none', userSelect: 'none', WebkitUserSelect: 'none', cursor: 'grab', zIndex: 3, outline: 'none',
        pointerEvents: 'auto', filter: lit ? 'drop-shadow(0 0 6px rgba(255,255,255,0.9))' : undefined,
      }}
    >
      <div ref={imgWrap} style={{ width: '100%', height: '100%', transformOrigin: `${lay.pivotX}px ${lay.pivotY}px`, willChange: 'transform' }}>
        {src && <img src={src} alt="" draggable={false} loading="lazy" decoding="async" style={{ width: '100%', height: '100%', objectFit: 'contain', pointerEvents: 'none', display: 'block' }} />}
      </div>
    </div>
  );
}
