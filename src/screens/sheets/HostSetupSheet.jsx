import { useEffect, useMemo, useRef, useState } from 'react';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { paper, ink, rule, alert, display } from '../../theme.js';
import { fieldGlass, inkButton } from '../hostStyle.js';
import { HOST_STOCK_COVERS, stockCoverDataUrl, stockCoverFile } from '../../lib/hostStockCovers.js';
import { deriveDefaultOrganizerName } from '../../lib/ensureOrganizer.js';
import { REVEAL_FLASH_START } from '../../lib/hostReveal.js';
import HostReveal from './HostReveal.jsx';

// First-time host setup (replaces the old "retry" card on Account > Host): choose a cover from the
// built-in set or upload a photo, name the host profile, write a short intro. Finishing plays the
// reveal: the sheet's elements dissolve into dots, swirl into a rotating sphere, then assemble
// into the host card. Skippable; never shown again once finished or skipped (hostSetupFlag).

const NAME_MAX = 80;
const INTRO_MAX = 280;
const MAX_PHOTO = 5 * 1024 * 1024;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const reduceMotion = () => typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

const CSS = `
@keyframes bbHostIn { from { opacity: 0; transform: translateY(26px); } to { opacity: 1; transform: none; } }
@keyframes bbHostUp { from { transform: translateY(100%); } to { transform: none; } }
.bb-host-sheet-in { animation: bbHostUp 420ms cubic-bezier(.2,.8,.2,1) both; }
.bb-host-tile { transition: transform 180ms ease, box-shadow 180ms ease; }
.bb-host-tile:active { transform: scale(.94); }
`;

export default function HostSetupSheet() {
  const { state: s, T, set, saveOrganizerProfile, ensureOrganizerNow, closeHostSetup } = useBanBe();
  const lang = s.lang === 'en' ? 'en' : 'vi';
  const stateRef = useRef(s);
  stateRef.current = s;
  const rootRef = useRef(null);
  const fileInputRef = useRef(null);

  const swatches = useMemo(() => HOST_STOCK_COVERS.map(c => ({ ...c, url: stockCoverDataUrl(c) })), []);
  const [coverId, setCoverId] = useState(HOST_STOCK_COVERS[0].id);
  const [upload, setUpload] = useState(null); // { file, url }
  const [name, setName] = useState(() => deriveDefaultOrganizerName(s.user?.name, lang));
  const [intro, setIntro] = useState('');
  const [phase, setPhase] = useState('form'); // form | saving | reveal
  const [error, setError] = useState('');
  const [fade, setFade] = useState({ dark: false, out: false });
  // Where the finished host card sits (root-relative px), once the reveal reaches it: a window opens in the black there.
  const [hole, setHole] = useState(null);
  const [typing, setTyping] = useState(false);
  // On phones the on-screen keyboard shrinks only the visual viewport; lift the panel's bottom edge by the
  // covered height so it (and the Done bar) stay above the keyboard. 0 on desktop, where nothing covers it.
  const [kb, setKb] = useState(0);
  useEffect(() => {
    const vv = typeof window !== 'undefined' ? window.visualViewport : null;
    if (!vv) return undefined;
    const on = () => setKb(Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop)));
    on();
    vv.addEventListener('resize', on);
    return () => vv.removeEventListener('resize', on);
  }, []);
  const hideKeyboard = () => { document.activeElement?.blur?.(); setTyping(false); };
  const kbProps = { onFocus: () => setTyping(true), onBlur: () => setTyping(false) };

  useEffect(() => () => { if (upload?.url) URL.revokeObjectURL(upload.url); }, [upload]);

  const previewUrl = upload ? upload.url : swatches.find(c => c.id === coverId)?.url;
  const canSubmit = phase === 'form' && name.trim().length > 0;

  const onPick = (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) { setError(T('Ảnh phải là JPEG, PNG hoặc WebP.', 'Photo must be JPEG, PNG, or WebP.')); return; }
    if (file.size > MAX_PHOTO) { setError(T('Ảnh tối đa 5MB.', 'Photo must be under 5MB.')); return; }
    setError('');
    setUpload({ file, url: URL.createObjectURL(file) });
    setCoverId('');
  };

  // The organizer row is created by ensure_my_organizer. Call it directly (with a few quiet retries)
  // instead of waiting on the background hook, whose gating can keep it from ever running.
  const obtainOrganizer = async () => {
    if (stateRef.current.myOrganizerId) return { id: stateRef.current.myOrganizerId };
    let last = '';
    for (let i = 0; i < 3; i++) {
      const r = await ensureOrganizerNow();
      if (r?.ok) return { id: r.organizerId };
      last = r?.error || 'UNKNOWN';
      if (stateRef.current.myOrganizerId) return { id: stateRef.current.myOrganizerId };
      await sleep(700 * (i + 1));
    }
    return { error: last };
  };

  const finish = async () => {
    if (!canSubmit) return;
    setPhase('saving'); setError('');
    try {
      const file = upload ? upload.file : await stockCoverFile(HOST_STOCK_COVERS.find(c => c.id === coverId) || HOST_STOCK_COVERS[0]);
      const got = await obtainOrganizer();
      if (!got.id) throw Object.assign(new Error('NO_ORGANIZER'), { code: got.error });
      const organizerId = got.id;
      const res = await saveOrganizerProfile(file, { organizerId, name: name.trim(), intro: intro.trim() });
      if (!res?.ok) throw new Error(res?.error || 'SAVE_FAILED');
    } catch (e) {
      setPhase('form');
      setError(e.message === 'NO_ORGANIZER'
        ? T('Chưa tạo được hồ sơ lúc này. Kiểm tra kết nối rồi nhấn Tạo hồ sơ lại.', "We couldn't create your profile just now. Check your connection and tap Create again.") + (e.code ? ` (${e.code})` : '')
        : (e.message && e.message !== 'SAVE_FAILED' ? e.message : T('Không thể lưu. Vui lòng thử lại.', 'Could not save. Please try again.')));
      return;
    }
    // Land on the host card the dots will assemble into.
    set({ screen: 'profile', accountTab: 'host' });
    // The Host tab may be scrolled (screens keep their scroll position); the dots assemble into the card, so
    // bring the whole card into view. The reveal re-aims at the card's real position late in the animation.
    setTimeout(() => document.querySelector('[data-testid="app-scroll-viewport"]')?.scrollTo({ top: 0, behavior: 'smooth' }), 350);
    setPhase('reveal');
    setFade({ dark: true, out: false });
    if (reduceMotion()) {
      setTimeout(() => setFade({ dark: true, out: true }), 150);
      setTimeout(() => closeHostSetup('done'), 700);
    } else {
      // The screen is fully black during the reveal. When the dots have formed the card, the card appears in
      // the black first; then the black fades out to show the whole Account screen.
      setTimeout(() => {
        const card = document.querySelector('[data-testid="org-profile-card"]')?.getBoundingClientRect();
        const root = rootRef.current?.getBoundingClientRect();
        if (card && root) setHole({ left: card.left - root.left, top: card.top - root.top, width: card.width, height: card.height });
      }, REVEAL_FLASH_START);
      setTimeout(() => setFade({ dark: true, out: true }), REVEAL_FLASH_START + 700);
    }
  };

  const revealing = phase === 'reveal';
  const label = { fontSize: 11, fontWeight: 600, letterSpacing: 0.6, textTransform: 'uppercase', color: ink, opacity: 0.55, margin: '26px 0 10px' };
  const input = fieldGlass({ borderRadius: 12, width: '100%', boxSizing: 'border-box', border: 'none', outline: 'none', padding: '14px 16px', fontSize: 15, color: ink, fontFamily: 'inherit' });

  return (
    <div
      ref={rootRef}
      data-testid="host-setup-sheet"
      style={{
        position: 'fixed', top: 0, left: 0, right: 0, bottom: kb, zIndex: 95, display: 'flex', flexDirection: 'column', overflow: 'hidden',
        // Same look as the share-card sheet: dimmed screen behind, a panel sliding up from the bottom.
        background: hole ? 'transparent' : (fade.dark ? '#000' : 'rgba(0,0,0,0.3)'),
        opacity: fade.out ? 0 : 1,
        transition: `background ${hole ? 500 : 600}ms ease, opacity ${fade.out ? 800 : 300}ms ease`,
      }}
    >
      <style>{CSS}</style>
      {hole && (
        // The window onto the finished card: transparent inside, black everywhere else (the huge shadow). The
        // opaque black root background fades to transparent so only this black remains. Under the dot canvas.
        <div
          aria-hidden
          style={{ position: 'absolute', left: hole.left, top: hole.top, width: hole.width, height: hole.height, borderRadius: 22, boxShadow: '0 0 0 4000px #000', pointerEvents: 'none' }}
        />
      )}
      <div
        className="bb-host-sheet-in"
        style={{ flex: 1, minHeight: 0, marginTop: 'calc(env(safe-area-inset-top, 0px) + 12px)', background: paper, borderRadius: '38px 38px 0 0', display: 'flex', flexDirection: 'column', opacity: revealing ? 0 : 1, transition: 'opacity 320ms ease', pointerEvents: revealing ? 'none' : 'auto' }}
      >
        <div aria-hidden style={{ flex: 'none', width: 36, height: 5, borderRadius: 3, background: ink, opacity: 0.22, margin: '8px auto 0' }} />
        <div style={{ flex: 'none', position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '10px 18px 6px', minHeight: 40 }}>
          <div style={{ fontSize: 17, fontWeight: 600, color: ink }}>{T('Hồ sơ tổ chức', 'Host profile')}</div>
          <button
            type="button" aria-label={T('Đóng', 'Close')} data-testid="host-setup-skip" onClick={phase === 'form' ? () => closeHostSetup('cancelled') : undefined}
            style={{ position: 'absolute', right: 18, top: 8, width: 44, height: 44, borderRadius: 22, background: 'color-mix(in srgb, var(--bb-field) 55%, transparent)', backdropFilter: 'blur(14px) saturate(1.6)', WebkitBackdropFilter: 'blur(14px) saturate(1.6)', border: `0.5px solid ${rule}`, boxShadow: '0 2px 10px rgba(0,0,0,0.08)', color: ink, fontSize: 22, fontWeight: 400, lineHeight: 1, padding: 0, opacity: phase === 'form' ? 1 : 0.3, cursor: 'pointer' }}
          >✕</button>
        </div>

        <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '8px 22px 24px' }}>
          <p data-reveal-src data-radius="8" style={{ fontSize: 14, lineHeight: 1.5, color: ink, opacity: 0.68, margin: '10px 0 0' }}>
            {T('Đây là diện mạo khách sẽ thấy. Bạn có thể đổi bất cứ lúc nào.', "This is how guests will see you. You can change it any time.")}
          </p>

          <div style={{ marginTop: 22, padding: '8px 0 4px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, textAlign: 'center' }}>
            <div data-reveal-src data-radius="30" style={{ width: 104, height: 104, borderRadius: 30, overflow: 'hidden', background: ink, boxShadow: '0 10px 30px rgba(0,0,0,0.16)' }}>
              {previewUrl && <img src={previewUrl} alt="" data-testid="host-setup-preview" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />}
            </div>
            <div style={{ ...display(22, { marginTop: 12, lineHeight: 1.2 }), wordBreak: 'break-word' }}>{name.trim() || T('Tên của bạn', 'Your name')}</div>
            <div style={{ fontSize: 13, lineHeight: 1.5, color: ink, opacity: intro.trim() ? 0.75 : 0.4, maxWidth: 300, wordBreak: 'break-word' }}>
              {intro.trim() || T('Giới thiệu ngắn về bạn', 'A short line about you')}
            </div>
          </div>

          <div style={label}>{T('Ảnh bìa', 'Cover')}</div>
          <div data-reveal-src data-radius="18" data-hscroll style={{ display: 'flex', gap: 12, overflowX: 'auto', padding: '6px 6px 10px', margin: '0 -6px' }}>
            <div
              className="bb-host-tile" role="button" data-testid="host-setup-upload" onClick={() => fileInputRef.current?.click()}
              style={{
                flex: 'none', width: 64, height: 64, borderRadius: 18, boxSizing: 'border-box', cursor: 'pointer', position: 'relative', overflow: 'hidden',
                border: upload ? 'none' : '1.5px dashed color-mix(in srgb, var(--bb-fg) 35%, transparent)', display: 'flex', alignItems: 'center', justifyContent: 'center',
                boxShadow: upload ? `0 0 0 2px ${paper}, 0 0 0 4px ${ink}` : 'none',
              }}
            >
              {upload ? <img src={upload.url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : (
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={ink} strokeWidth="1.6" strokeLinecap="round" style={{ opacity: 0.7 }}><path d="M12 5v14M5 12h14" /></svg>
              )}
            </div>
            {swatches.map(c => {
              const on = !upload && coverId === c.id;
              return (
                <div
                  key={c.id} className="bb-host-tile" role="button" aria-label={lang === 'vi' ? c.vi : c.en} data-testid={`host-setup-cover-${c.id}`}
                  onClick={() => { setUpload(null); setCoverId(c.id); setError(''); }}
                  style={{
                    flex: 'none', width: 64, height: 64, borderRadius: 18, cursor: 'pointer',
                    background: c.url ? `url(${c.url}) center/cover` : c.a,
                    boxShadow: on ? `0 0 0 2px ${paper}, 0 0 0 4px ${ink}` : 'inset 0 0 0 1px rgba(0,0,0,0.06)',
                  }}
                />
              );
            })}
          </div>
          <input ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp" style={{ display: 'none' }} onChange={onPick} data-testid="host-setup-file" />

          <div style={label}>{T('Tên', 'Name')}</div>
          <input
            data-reveal-src data-radius="12" {...kbProps} value={name} maxLength={NAME_MAX} onChange={e => setName(e.target.value)} data-testid="host-setup-name"
            placeholder={T('Tên tổ chức của bạn', 'Your host name')} style={input}
          />

          <div style={{ ...label, display: 'flex', justifyContent: 'space-between' }}>
            <span>{T('Giới thiệu', 'About')}</span>
            <span style={{ letterSpacing: 0, textTransform: 'none', fontWeight: 500 }}>{intro.length}/{INTRO_MAX}</span>
          </div>
          <textarea
            data-reveal-src data-radius="12" {...kbProps} value={intro} maxLength={INTRO_MAX} rows={4} onChange={e => setIntro(e.target.value)} data-testid="host-setup-intro"
            placeholder={T('Bạn tổ chức những gì? Vì sao khách nên đến?', 'What do you host? Why should guests come?')}
            style={{ ...input, resize: 'none', lineHeight: 1.5 }}
          />

          {error && <p data-testid="host-setup-error" style={{ fontSize: 12.5, lineHeight: 1.5, color: alert, margin: '14px 0 0' }}>{error}</p>}
        </div>

        {typing && (
          <div style={{ flex: 'none', display: 'flex', justifyContent: 'flex-end', padding: '4px 22px' }}>
            <button
              type="button" data-testid="host-setup-keyboard-done"
              onPointerDown={e => e.preventDefault()} onClick={hideKeyboard}
              style={{ background: 'none', border: 'none', color: ink, fontSize: 15, fontWeight: 600, padding: '8px 4px', cursor: 'pointer' }}
            >{T('Xong', 'Done')}</button>
          </div>
        )}
        <div data-reveal-src data-radius="18" style={{ flex: 'none', margin: '0 22px calc(env(safe-area-inset-bottom, 0px) + 16px)' }}>
          <div
            role="button" aria-disabled={!canSubmit} data-testid="host-setup-submit" onClick={canSubmit ? finish : undefined}
            style={inkButton({ opacity: canSubmit || phase !== 'form' ? 1 : 0.4, cursor: canSubmit ? 'pointer' : 'default' })}
          >
            {phase === 'form' ? T('Tạo hồ sơ', 'Create host profile') : T('Đang chuẩn bị…', 'Setting things up…')}
          </div>
        </div>
      </div>

      {revealing && !reduceMotion() && (
        <HostReveal sourceRoot={rootRef.current} targetSelector='[data-testid="org-profile-card"]' onDone={() => setTimeout(() => closeHostSetup('done'), 700) /* let the black finish fading out first */} />
      )}
    </div>
  );
}
