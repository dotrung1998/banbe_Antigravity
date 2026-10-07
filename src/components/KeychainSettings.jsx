import { useEffect, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { ink, rule, alert, fieldGlass, inkButton } from '../theme.js';
import { KeychainFrame, useKeychainManifest } from './KeychainCharm.jsx';
import {
  ANCHORS, SIZES, DEFAULT_KEYCHAIN, designUrl, fetchMyKeychain, saveMyKeychain, setMine, getMineSnapshot, normalizeKeychain,
} from '../lib/keychain.js';
import { keychainFocus } from '../lib/keychain.js';
import {
  KEYCHAIN_INPUT_ACCEPT, KEYCHAIN_ERRORS, mapKeychainError, prepareCustomArt, uploadAndSaveCustomArt, deleteCustomArt,
} from '../lib/keychainUpload.js';

const ANCHOR_LABEL = {
  top_left: ['Trên trái', 'Top left'], top_right: ['Trên phải', 'Top right'],
  bottom_left: ['Dưới trái', 'Bottom left'], bottom_right: ['Dưới phải', 'Bottom right'],
};
const SIZE_LABEL = { s: 'S', m: 'M', l: 'L' };

function Chip({ on, onClick, children, testId, disabled }) {
  return (
    <button type="button" onClick={onClick} disabled={disabled} data-testid={testId} aria-pressed={on}
      style={{ ...fieldGlass({ padding: '8px 12px', fontSize: 12, color: ink, cursor: disabled ? 'default' : 'pointer', border: on ? `2px solid ${ink}` : `1px solid ${rule}`, opacity: disabled ? 0.5 : 1 }), fontFamily: 'inherit' }}>
      {children}
    </button>
  );
}

export default function KeychainSettings() {
  const { T, state, set: setApp, loadRewardsUnlocked } = useBanBe();
  const lang = state.lang;
  // Reward designs (migration 165) are optional and only offered once rewards are live for this account.
  const rewardsLive = state.rewardsSummaryStatus === 'loaded';
  const unlocked = state.rewardsUnlocked || [];
  useEffect(() => { if (state.user?.id && rewardsLive) loadRewardsUnlocked(); }, [state.user?.id, rewardsLive, loadRewardsUnlocked]);
  const manifest = useKeychainManifest();
  const rootRef = useRef(null);
  useEffect(() => {
    if (!keychainFocus.pending) return;
    keychainFocus.pending = false;
    const t = setTimeout(() => rootRef.current?.scrollIntoView?.({ block: 'start', behavior: 'smooth' }), 150);
    return () => clearTimeout(t);
  }, []);
  const [saved, setSaved] = useState(null);       // server config
  const [draft, setDraft] = useState(null);       // editing copy; nothing persisted until Save
  const [pendingArt, setPendingArt] = useState(null); // {blob,url,width,height,contentType}
  const [removeArt, setRemoveArt] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const [note, setNote] = useState('');
  const [tilt, setTilt] = useState('');
  const ctrlRef = useRef(null);
  const fileRef = useRef(null);
  const msg = (code) => { const e = KEYCHAIN_ERRORS[code] || KEYCHAIN_ERRORS.GENERIC; return lang === 'en' ? e[1] : e[0]; };

  useEffect(() => {
    let on = true;
    const snap = getMineSnapshot();
    if (snap.loaded && snap.value) { setSaved(snap.value); setDraft(snap.value); return undefined; }
    fetchMyKeychain().then(v => { if (on) { const k = v || DEFAULT_KEYCHAIN; setSaved(k); setDraft(k); } });
    return () => { on = false; };
  }, []);
  useEffect(() => () => { if (pendingArt?.url) URL.revokeObjectURL(pendingArt.url); }, [pendingArt]);

  if (!draft) return null;
  const set = (patch) => { setErr(''); setNote(''); setDraft(d => ({ ...d, ...patch })); };
  const dirty = JSON.stringify(draft) !== JSON.stringify(saved) || !!pendingArt || removeArt;
  const isLabel = (o) => (lang === 'en' ? o.en : o.vi);
  const previewCfg = pendingArt ? { ...draft, designId: 'custom' } : (removeArt && draft.designId === 'custom' ? { ...draft, designId: 'sky-star' } : draft);
  const hasCustom = !!(saved?.customAsset) && !removeArt;

  const cancel = () => { setDraft(saved); setPendingArt(null); setRemoveArt(false); setErr(''); setNote(''); };

  const onPick = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setErr(''); setBusy(true);
    try {
      const prepared = await prepareCustomArt(file);
      setPendingArt({ ...prepared, url: URL.createObjectURL(prepared.blob) });
      setRemoveArt(false);
      setDraft(d => ({ ...d, designId: 'custom' }));
    } catch (ex) { setErr(msg(mapKeychainError(ex))); }
    setBusy(false);
  };

  const save = async () => {
    setBusy(true); setErr('');
    try {
      const { data: { session } } = await supabase.auth.getSession();
      const token = session?.access_token;
      let result;
      if (pendingArt) {
        const r = await uploadAndSaveCustomArt({ supabase, accessToken: token }, {
          blob: pendingArt.blob, contentType: pendingArt.contentType, config: draft, oldAssetId: saved?.customAsset?.id,
        });
        result = normalizeKeychain(r.keychain);
      } else if (removeArt) {
        const oldId = saved?.customAsset?.id;
        result = await saveMyKeychain({ ...draft, designId: draft.designId === 'custom' ? 'sky-star' : draft.designId, customAsset: null });
        if (oldId) { try { await deleteCustomArt({ accessToken: token }, oldId); } catch { /* orphan is cleaned server-side */ } }
      } else {
        result = await saveMyKeychain(draft);
      }
      setSaved(result); setDraft(result); setPendingArt(null); setRemoveArt(false); setMine(result);
      setNote(T('Đã lưu.', 'Saved.'));
    } catch (ex) { setErr(msg(mapKeychainError(ex))); }
    setBusy(false);
  };

  const enableTilt = async () => {
    const r = await ctrlRef.current?.enableTilt();
    setTilt(r === 'granted' ? T('Đã bật nghiêng.', 'Tilt on.') : r === 'unsupported' || r === 'insecure'
      ? T('Thiết bị này không hỗ trợ.', 'Not supported on this device.') : T('Chưa được cấp quyền.', 'Permission not granted.'));
  };

  const designsOf = (gid) => manifest.designs.filter(d => d.group === gid);
  const label = { fontSize: 11.5, color: ink };

  return (
    <div ref={rootRef} style={{ display: 'flex', flexDirection: 'column', gap: 10, scrollMarginTop: 12 }} data-testid="keychain-settings">
      <span style={label}>{T('Móc khoá', 'Keychain')}</span>
      <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: ink }}>
        <input type="checkbox" checked={draft.enabled} onChange={e => set({ enabled: e.target.checked })} data-testid="keychain-enabled" />
        {T('Hiện móc khoá trên hồ sơ của tôi', 'Show a keychain on my profile')}
      </label>

      {draft.enabled && (<>
        {/* plain box, NOT cardGlass: its mask-image would clip the hanging charm */}
        <div style={{ padding: 14, borderRadius: 12, border: `1px solid ${rule}` }} data-testid="keychain-preview">
          <span style={{ ...label, opacity: 0.6 }}>{T('Xem trước (chưa lưu)', 'Live preview (not saved)')}</span>
          <KeychainFrame config={{ ...previewCfg, enabled: true }} margin="10px 24px 0" cardHeight={70} srcOverride={pendingArt?.url} onController={(c) => { ctrlRef.current = c; }}>
            <div style={{ ...fieldGlass({ height: 70, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, color: ink, opacity: 0.7 }) }}>
              {T('Thẻ hồ sơ của bạn', 'Your profile card')}
            </div>
          </KeychainFrame>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 10 }}>
            <Chip onClick={() => ctrlRef.current?.swing(1)} testId="keychain-swing">{T('Lắc', 'Swing')}</Chip>
            {typeof window !== 'undefined' && 'DeviceMotionEvent' in window && (
              <Chip onClick={enableTilt} testId="keychain-tilt">{T('Bật nghiêng', 'Enable tilt')}</Chip>
            )}
          </div>
          {tilt && <span role="status" style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{tilt}</span>}
        </div>

        {manifest.groups.filter(g => g.id !== 'rewards' || rewardsLive).map(g => (
          <div key={g.id} style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <span style={{ ...label, opacity: 0.7 }}>{isLabel(g)}</span>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              {designsOf(g.id).map(d => {
                const locked = !!d.reward && !unlocked.includes(d.id);
                return (
                <button key={d.id} type="button"
                  onClick={() => { if (locked) { setApp({ screen: 'rewards' }); return; } setPendingArt(null); set({ designId: d.id }); }}
                  data-testid={`keychain-design-${d.id}`} data-locked={locked ? 'true' : 'false'}
                  aria-label={locked ? T(`${isLabel(d)}, chưa mở khoá. Mở khoá trong Phần thưởng`, `${isLabel(d)}, locked. Unlock in Rewards`) : isLabel(d)}
                  aria-pressed={locked ? undefined : previewCfg.designId === d.id} title={isLabel(d)}
                  style={{ position: 'relative', width: 48, height: 64, padding: 2, borderRadius: 10, background: 'transparent', cursor: 'pointer', border: previewCfg.designId === d.id ? `2px solid ${ink}` : `1px solid ${rule}` }}>
                  <img src={designUrl(manifest, d.id)} alt="" loading="lazy" decoding="async" style={{ width: '100%', height: '100%', objectFit: 'contain', opacity: locked ? 0.4 : 1 }} />
                  {locked && <span aria-hidden="true" style={{ position: 'absolute', right: 3, bottom: 3, fontSize: 12, lineHeight: 1 }}>🔒</span>}
                </button>
                );
              })}
            </div>
          </div>
        ))}

        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <span style={{ ...label, opacity: 0.7 }}>{T('Vị trí', 'Corner')}</span>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {ANCHORS.map(a => <Chip key={a} on={draft.anchor === a} onClick={() => set({ anchor: a })} testId={`keychain-anchor-${a}`}>{T(...ANCHOR_LABEL[a])}</Chip>)}
          </div>
          <span style={{ ...label, opacity: 0.7 }}>{T('Kích thước', 'Size')}</span>
          <div style={{ display: 'flex', gap: 8 }}>
            {SIZES.map(z => <Chip key={z} on={draft.size === z} onClick={() => set({ size: z })} testId={`keychain-size-${z}`}>{SIZE_LABEL[z]}</Chip>)}
          </div>
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: ink }}>
            <input type="checkbox" checked={draft.motionEnabled} onChange={e => set({ motionEnabled: e.target.checked })} data-testid="keychain-motion" />
            {T('Cho phép chuyển động (kéo, lắc)', 'Allow motion (drag, swing)')}
          </label>
        </div>

        <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap', alignItems: 'center' }}>
          {previewCfg.designId !== 'custom' && (
            <a href={designUrl(manifest, previewCfg.designId)} download={`${previewCfg.designId}.png`} data-testid="keychain-download" style={{ fontSize: 12, color: ink, fontWeight: 600 }}>
              {T('Tải ảnh thiết kế', 'Download artwork')}
            </a>
          )}
          <span onClick={() => !busy && fileRef.current?.click()} data-testid="keychain-upload-pick" role="button" tabIndex={0}
            onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') fileRef.current?.click(); }}
            style={{ fontSize: 12, color: ink, fontWeight: 600, cursor: 'pointer' }}>
            {T('Dùng ảnh của tôi', 'Use my own art')}
          </span>
          {(hasCustom || pendingArt) && (
            <span onClick={() => { setPendingArt(null); if (saved?.customAsset) setRemoveArt(true); setDraft(d => ({ ...d, designId: d.designId === 'custom' ? 'sky-star' : d.designId })); }}
              data-testid="keychain-remove-art" role="button" tabIndex={0} style={{ fontSize: 12, color: alert, cursor: 'pointer' }}>
              {T('Xoá ảnh của tôi', 'Remove my art')}
            </span>
          )}
          <input ref={fileRef} type="file" accept={KEYCHAIN_INPUT_ACCEPT} style={{ display: 'none' }} onChange={onPick} data-testid="keychain-upload-input" />
        </div>
        <span style={{ fontSize: 10.5, color: ink, opacity: 0.55 }}>
          {T('PNG/WebP, tối đa 512 px, 256 KB, tối đa 3 ảnh. Ảnh được nén lại và xoá metadata trên thiết bị của bạn.', 'PNG/WebP, up to 512 px and 256 KB, max 3 images. Re-encoded on your device; metadata removed.')}
        </span>
      </>)}

      {err && <p role="alert" data-testid="keychain-error" style={{ fontSize: 12, color: alert, margin: 0 }}>{err}</p>}
      {note && <p role="status" style={{ fontSize: 12, color: ink, margin: 0 }}>{note}</p>}
      <div style={{ display: 'flex', gap: 10 }}>
        <div onClick={() => dirty && !busy && save()} data-testid="keychain-save" style={{ ...inkButton({ padding: '11px 0', flex: 1, opacity: dirty && !busy ? 1 : 0.5, cursor: dirty && !busy ? 'pointer' : 'default' }) }}>
          {busy ? T('Đang lưu…', 'Saving…') : T('Lưu móc khoá', 'Save keychain')}
        </div>
        <div onClick={() => dirty && cancel()} data-testid="keychain-cancel" role="button" style={{ ...fieldGlass({ padding: '11px 18px', fontSize: 13, color: ink, cursor: dirty ? 'pointer' : 'default', opacity: dirty ? 1 : 0.5, textAlign: 'center' }) }}>
          {T('Huỷ', 'Cancel')}
        </div>
      </div>
    </div>
  );
}
