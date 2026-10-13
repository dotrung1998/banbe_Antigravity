import { useEffect, useMemo, useRef, useState } from 'react';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { paper, ink, alert, display } from '../../theme.js';
import { fieldGlass, inkButton, insetField } from '../hostStyle.js';
import { HOST_STOCK_COVERS, stockCoverDataUrl, stockCoverFile } from '../../lib/hostStockCovers.js';
import { deriveDefaultOrganizerName } from '../../lib/ensureOrganizer.js';
import { REVEAL_TOTAL } from '../../lib/hostReveal.js';
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
.bb-host-sheet-in { animation: bbHostIn 520ms cubic-bezier(.2,.8,.2,1) both; }
.bb-host-tile { transition: transform 180ms ease, box-shadow 180ms ease; }
.bb-host-tile:active { transform: scale(.94); }
`;

export default function HostSetupSheet() {
  const { state: s, T, set, saveOrganizerProfile, retryEnsureOrganizer, closeHostSetup } = useBanBe();
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

  // The organizer row is created by ensure_my_organizer once the mode change settles; wait for it
  // here (retrying quietly) instead of surfacing a "retry" card on the Account screen.
  const waitForOrganizer = async () => {
    const deadline = Date.now() + 15000;
    let kicked = 0;
    while (Date.now() < deadline) {
      const cur = stateRef.current;
      if (cur.myOrganizerId) return cur.myOrganizerId;
      if (cur.ensureOrganizerStatus === 'error' && kicked < 3) { kicked += 1; retryEnsureOrganizer(); }
      await sleep(250);
    }
    return stateRef.current.myOrganizerId || null;
  };

  const finish = async () => {
    if (!canSubmit) return;
    setPhase('saving'); setError('');
    try {
      const file = upload ? upload.file : await stockCoverFile(HOST_STOCK_COVERS.find(c => c.id === coverId) || HOST_STOCK_COVERS[0]);
      const organizerId = await waitForOrganizer();
      if (!organizerId) throw new Error('NO_ORGANIZER');
      const res = await saveOrganizerProfile(file, { organizerId, name: name.trim(), intro: intro.trim() });
      if (!res?.ok) throw new Error(res?.error || 'SAVE_FAILED');
    } catch (e) {
      setPhase('form');
      setError(e.message === 'NO_ORGANIZER'
        ? T('Chưa tạo được hồ sơ lúc này. Kiểm tra kết nối rồi nhấn Tạo hồ sơ lại.', "We couldn't create your profile just now. Check your connection and tap Create again.")
        : (e.message && e.message !== 'SAVE_FAILED' ? e.message : T('Không thể lưu. Vui lòng thử lại.', 'Could not save. Please try again.')));
      return;
    }
    // Land on the host card the dots will assemble into.
    set({ screen: 'profile', accountTab: 'host' });
    setPhase('reveal');
    setFade({ dark: true, out: false });
    if (reduceMotion()) {
      setTimeout(() => setFade({ dark: true, out: true }), 150);
      setTimeout(() => closeHostSetup('done'), 700);
    } else {
      setTimeout(() => setFade({ dark: true, out: true }), REVEAL_TOTAL - 650);
    }
  };

  const revealing = phase === 'reveal';
  const label = { fontSize: 11, fontWeight: 600, letterSpacing: 0.6, textTransform: 'uppercase', color: ink, opacity: 0.55, margin: '26px 0 10px' };
  const input = insetField({ width: '100%', boxSizing: 'border-box', border: 'none', outline: 'none', padding: '14px 16px', fontSize: 15, color: ink, fontFamily: 'inherit' });

  return (
    <div
      ref={rootRef}
      data-testid="host-setup-sheet"
      style={{
        position: 'fixed', inset: 0, zIndex: 95, display: 'flex', flexDirection: 'column', overflow: 'hidden',
        background: fade.dark ? 'rgba(14,12,9,0.94)' : paper,
        opacity: fade.out ? 0 : 1,
        transition: `background 600ms ease, opacity ${fade.out ? 650 : 300}ms ease`,
      }}
    >
      <style>{CSS}</style>
      <div
        className="bb-host-sheet-in"
        style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', opacity: revealing ? 0 : 1, transition: 'opacity 520ms ease', pointerEvents: revealing ? 'none' : 'auto' }}
      >
        <div style={{ flex: 'none', display: 'flex', justifyContent: 'flex-end', padding: 'calc(env(safe-area-inset-top, 0px) + 16px) 22px 0' }}>
          <span
            role="button" data-testid="host-setup-skip" onClick={phase === 'form' ? () => closeHostSetup('skipped') : undefined}
            style={{ fontSize: 13.5, fontWeight: 600, color: ink, opacity: phase === 'form' ? 0.6 : 0.25, cursor: 'pointer' }}
          >{T('Để sau', 'Not now')}</span>
        </div>

        <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '8px 22px 24px' }}>
          <h1 style={{ ...display(30, { margin: '6px 0 8px', lineHeight: 1.15 }) }}>{T('Tạo hồ sơ tổ chức', 'Set up your host profile')}</h1>
          <p style={{ fontSize: 14, lineHeight: 1.5, color: ink, opacity: 0.68, margin: 0 }}>
            {T('Đây là diện mạo khách sẽ thấy. Bạn có thể đổi bất cứ lúc nào.', "This is how guests will see you. You can change it any time.")}
          </p>

          <div data-reveal-src data-radius="24" style={fieldGlass({ marginTop: 22, padding: '26px 20px 22px', borderRadius: 24, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, textAlign: 'center' })}>
            <div data-reveal-src data-radius="30" style={{ width: 104, height: 104, borderRadius: 30, overflow: 'hidden', background: ink, boxShadow: '0 10px 30px rgba(0,0,0,0.16)' }}>
              {previewUrl && <img src={previewUrl} alt="" data-testid="host-setup-preview" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />}
            </div>
            <div style={{ ...display(22, { marginTop: 12, lineHeight: 1.2 }), wordBreak: 'break-word' }}>{name.trim() || T('Tên của bạn', 'Your name')}</div>
            <div style={{ fontSize: 13, lineHeight: 1.5, color: ink, opacity: intro.trim() ? 0.75 : 0.4, maxWidth: 300, wordBreak: 'break-word' }}>
              {intro.trim() || T('Giới thiệu ngắn về bạn', 'A short line about you')}
            </div>
          </div>

          <div style={label}>{T('Ảnh bìa', 'Cover')}</div>
          <div data-hscroll style={{ display: 'flex', gap: 12, overflowX: 'auto', padding: '4px 2px 8px', margin: '0 -2px' }}>
            <div
              className="bb-host-tile" role="button" data-testid="host-setup-upload" onClick={() => fileInputRef.current?.click()}
              style={{
                flex: 'none', width: 64, height: 64, borderRadius: 18, boxSizing: 'border-box', cursor: 'pointer', position: 'relative', overflow: 'hidden',
                border: upload ? 'none' : `1.5px dashed ${ink}55`, display: 'flex', alignItems: 'center', justifyContent: 'center',
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
            value={name} maxLength={NAME_MAX} onChange={e => setName(e.target.value)} data-testid="host-setup-name"
            placeholder={T('Tên tổ chức của bạn', 'Your host name')} style={input}
          />

          <div style={{ ...label, display: 'flex', justifyContent: 'space-between' }}>
            <span>{T('Giới thiệu', 'About')}</span>
            <span style={{ letterSpacing: 0, textTransform: 'none', fontWeight: 500 }}>{intro.length}/{INTRO_MAX}</span>
          </div>
          <textarea
            value={intro} maxLength={INTRO_MAX} rows={4} onChange={e => setIntro(e.target.value)} data-testid="host-setup-intro"
            placeholder={T('Bạn tổ chức những gì? Vì sao khách nên đến?', 'What do you host? Why should guests come?')}
            style={{ ...input, resize: 'none', lineHeight: 1.5 }}
          />

          {error && <p data-testid="host-setup-error" style={{ fontSize: 12.5, lineHeight: 1.5, color: alert, margin: '14px 0 0' }}>{error}</p>}
        </div>

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
        <HostReveal sourceRoot={rootRef.current} targetSelector='[data-testid="org-profile-card"]' onDone={() => closeHostSetup('done')} />
      )}
    </div>
  );
}
