import { useEffect, useRef, useState } from 'react';
import QRCode from 'qrcode';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { paper, ink, rule, display, alert, inkButton } from '../../theme.js';

// Web port of apps/ios/BanbeApp/Views/ProfileShareCardView.swift. The card is
// drawn with canvas 2D by ONE function (drawCard) used both for the on-screen
// preview and the downloaded/shared PNG, so the two can't drift (same idea as
// iOS using one SwiftUI view for preview + ImageRenderer). Style is kept on
// this device only (localStorage), like iOS's UserDefaults ShareCardStyle.

const CARD_W = 340;
const CARD_H = 520;
const STORAGE_KEY = 'shareCardStyle.v1'; // same key name as iOS

export const SHARE_CARD_PRESETS = [
  { name: 'Hoàng hôn', nameEN: 'Sunset', topHex: '#FF7E5F', bottomHex: '#C2185B', textHex: '#FFFFFF' },
  { name: 'Đại dương', nameEN: 'Ocean', topHex: '#2B86C5', bottomHex: '#1B2A6B', textHex: '#FFFFFF' },
  { name: 'Rừng', nameEN: 'Forest', topHex: '#56AB91', bottomHex: '#1F4D3F', textHex: '#FFFFFF' },
  { name: 'Tím mộng', nameEN: 'Violet', topHex: '#8E54E9', bottomHex: '#3B1F7A', textHex: '#FFFFFF' },
  { name: 'Mực', nameEN: 'Ink', topHex: '#3A3A3C', bottomHex: '#0E0E10', textHex: '#FFFFFF' },
  { name: 'Giấy', nameEN: 'Paper', topHex: '#FBF8F1', bottomHex: '#E9E2D2', textHex: '#1C1C1E' },
];
const DEFAULT_STYLE = { topHex: SHARE_CARD_PRESETS[0].topHex, bottomHex: SHARE_CARD_PRESETS[0].bottomHex, textHex: SHARE_CARD_PRESETS[0].textHex, photo: null };
const HEX = /^#[0-9a-fA-F]{6}$/;

function loadStyle() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_STYLE;
    const o = JSON.parse(raw);
    return {
      topHex: HEX.test(o.topHex) ? o.topHex : DEFAULT_STYLE.topHex,
      bottomHex: HEX.test(o.bottomHex) ? o.bottomHex : DEFAULT_STYLE.bottomHex,
      textHex: HEX.test(o.textHex) ? o.textHex : DEFAULT_STYLE.textHex,
      photo: typeof o.photo === 'string' && o.photo.startsWith('data:image/') ? o.photo : null,
    };
  } catch { return DEFAULT_STYLE; }
}
function saveStyle(st) {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(st)); } catch { /* quota / private mode: style just won't persist */ }
}

export function profileShareLinks() {
  const origin = typeof location !== 'undefined' ? location.origin : 'https://banbe.app';
  return {
    member: (handle) => `${origin}/u/${handle}`,
    host: (organizerId) => `${origin}/org/${organizerId}`,
  };
}

function loadImage(src, cors) {
  return new Promise((resolve) => {
    const img = new Image();
    if (cors) img.crossOrigin = 'anonymous';
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = src;
  });
}

// Avatar from another origin: ask for CORS so the canvas stays exportable;
// if the host refuses, fall back to the monogram rather than a tainted canvas.
async function loadAvatar(url) {
  if (!url) return null;
  return loadImage(url, true);
}

function rrect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function drawCover(ctx, img, x, y, w, h) {
  const s = Math.max(w / img.width, h / img.height);
  const dw = img.width * s, dh = img.height * s;
  ctx.drawImage(img, x + (w - dw) / 2, y + (h - dh) / 2, dw, dh);
}

function hexRgba(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}

// Greedy word wrap, hard-breaks over-long words, ellipsis past maxLines.
function wrapLines(ctx, text, maxW, maxLines) {
  const words = String(text || '').split(/\s+/).filter(Boolean);
  const lines = [];
  let cur = '';
  const push = (l) => lines.push(l);
  for (const w of words) {
    const test = cur ? `${cur} ${w}` : w;
    if (ctx.measureText(test).width <= maxW) { cur = test; continue; }
    if (cur) push(cur);
    cur = w;
    while (ctx.measureText(cur).width > maxW && cur.length > 1) {
      let i = cur.length - 1;
      while (i > 1 && ctx.measureText(cur.slice(0, i)).width > maxW) i--;
      push(cur.slice(0, i));
      cur = cur.slice(i);
    }
  }
  if (cur) push(cur);
  if (lines.length > maxLines) {
    lines.length = maxLines;
    let last = lines[maxLines - 1];
    while (last.length > 1 && ctx.measureText(`${last}…`).width > maxW) last = last.slice(0, -1);
    lines[maxLines - 1] = `${last}…`;
  }
  return lines;
}

function setTracking(ctx, px) {
  if ('letterSpacing' in ctx) ctx.letterSpacing = `${px}px`;
}

const FONT = "'Be Vietnam Pro', system-ui, sans-serif";

function drawCard(canvas, scale, d) {
  const { style, kindLabel, name, subtitle, detail, avatarImg, roundAvatar, qrImg, footnote, photoImg } = d;
  canvas.width = CARD_W * scale;
  canvas.height = CARD_H * scale;
  const ctx = canvas.getContext('2d');
  ctx.setTransform(scale, 0, 0, scale, 0, 0);
  ctx.clearRect(0, 0, CARD_W, CARD_H);
  ctx.textBaseline = 'alphabetic';

  ctx.save();
  rrect(ctx, 0, 0, CARD_W, CARD_H, 28);
  ctx.clip();

  const g = ctx.createLinearGradient(0, 0, CARD_W, CARD_H);
  g.addColorStop(0, style.topHex); g.addColorStop(1, style.bottomHex);
  ctx.fillStyle = g; ctx.fillRect(0, 0, CARD_W, CARD_H);
  if (photoImg) {
    drawCover(ctx, photoImg, 0, 0, CARD_W, CARD_H);
    const sc = ctx.createLinearGradient(0, 0, 0, CARD_H);
    sc.addColorStop(0, 'rgba(0,0,0,0.25)'); sc.addColorStop(1, 'rgba(0,0,0,0.6)');
    ctx.fillStyle = sc; ctx.fillRect(0, 0, CARD_W, CARD_H);
  }
  // Soft decorative glows.
  const glow = (cx, cy, r, color) => {
    const rg = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
    rg.addColorStop(0, color); rg.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = rg; ctx.fillRect(0, 0, CARD_W, CARD_H);
  };
  glow(60, 70, 150, 'rgba(255,255,255,0.18)');
  glow(300, 490, 160, 'rgba(0,0,0,0.16)');

  const fg = style.textHex;
  const cx = CARD_W / 2;
  const pad = 24;

  // Header: wordmark + kind pill.
  ctx.fillStyle = fg; ctx.textAlign = 'left';
  ctx.font = `700 16px ${FONT}`; setTracking(ctx, -0.3);
  ctx.fillText('banbe', pad, 38);
  ctx.font = `600 10px ${FONT}`; setTracking(ctx, 1.2);
  const label = String(kindLabel || '').toUpperCase();
  const pw = ctx.measureText(label).width + 20;
  rrect(ctx, CARD_W - pad - pw, 25, pw, 22, 11);
  ctx.strokeStyle = hexRgba(fg, 0.55); ctx.lineWidth = 1; ctx.stroke();
  ctx.textAlign = 'center';
  ctx.fillText(label, CARD_W - pad - pw / 2 + 0.6, 40);
  setTracking(ctx, 0);

  // Avatar.
  const aS = 92, aX = cx - aS / 2, aY = 82, aR = roundAvatar ? 46 : 24;
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.25)'; ctx.shadowBlur = 10; ctx.shadowOffsetY = 4;
  rrect(ctx, aX, aY, aS, aS, aR); ctx.fillStyle = 'rgba(0,0,0,0.01)'; ctx.fill();
  ctx.restore();
  ctx.save();
  rrect(ctx, aX, aY, aS, aS, aR); ctx.clip();
  if (avatarImg) {
    drawCover(ctx, avatarImg, aX, aY, aS, aS);
  } else {
    ctx.fillStyle = hexRgba(fg, 0.18); ctx.fillRect(aX, aY, aS, aS);
    ctx.fillStyle = fg; ctx.textAlign = 'center'; ctx.font = `600 38px ${FONT}`;
    ctx.fillText((String(name || '?').trim()[0] || '?').toUpperCase(), cx, aY + aS / 2 + 13);
  }
  ctx.restore();
  rrect(ctx, aX + 1.5, aY + 1.5, aS - 3, aS - 3, Math.max(aR - 1.5, 0));
  ctx.strokeStyle = hexRgba(fg, 0.8); ctx.lineWidth = 3; ctx.stroke();

  // Text block.
  const maxW = CARD_W - pad * 2;
  ctx.fillStyle = fg; ctx.textAlign = 'center';
  let y = aY + aS + 14 + 22;
  ctx.font = `700 26px ${FONT}`;
  for (const l of wrapLines(ctx, name, maxW, 2)) { ctx.fillText(l, cx, y); y += 31; }
  y -= 31;
  if (subtitle) {
    y += 22;
    ctx.globalAlpha = 0.85; ctx.font = `500 14px ${FONT}`;
    ctx.fillText(wrapLines(ctx, subtitle, maxW, 1)[0] || '', cx, y);
    ctx.globalAlpha = 1;
  }
  if (detail) {
    y += 22;
    ctx.globalAlpha = 0.8; ctx.font = `400 12.5px ${FONT}`;
    for (const l of wrapLines(ctx, detail, maxW, 2)) { ctx.fillText(l, cx, y); y += 16; }
    ctx.globalAlpha = 1;
  }

  // Footnote (bottom-anchored), then QR above it.
  ctx.font = `500 11px ${FONT}`;
  const fLines = wrapLines(ctx, footnote, maxW, 2);
  const fTop = CARD_H - 22 - fLines.length * 14;
  ctx.globalAlpha = 0.85; ctx.fillStyle = fg; ctx.textAlign = 'center';
  fLines.forEach((l, i) => ctx.fillText(l, cx, fTop + 11 + i * 14));
  ctx.globalAlpha = 1;
  const qS = 132, qX = cx - qS / 2, qY = fTop - 10 - qS;
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.25)'; ctx.shadowBlur = 10; ctx.shadowOffsetY = 4;
  rrect(ctx, qX, qY, qS, qS, 14); ctx.fillStyle = '#FFFFFF'; ctx.fill();
  ctx.restore();
  if (qrImg) { ctx.imageSmoothingEnabled = false; ctx.drawImage(qrImg, qX + 6, qY + 6, qS - 12, qS - 12); }

  ctx.restore();
}

// Re-renders `canvasRef` whenever its inputs change; returns nothing.
function useCardRender(canvasRef, scale, input, ready) {
  const { style, kindLabel, name, subtitle, detail, avatarImg, roundAvatar, qrImg, footnote } = input;
  useEffect(() => {
    let live = true;
    (async () => {
      try {
        if (document.fonts?.load) {
          const sample = `${name} ${subtitle} ${detail} ${footnote}`;
          await Promise.all(['400', '500', '600', '700'].map(w => document.fonts.load(`${w} 16px "Be Vietnam Pro"`, sample)));
        }
      } catch { /* draw with fallback face */ }
      const photoImg = style.photo ? await loadImage(style.photo, false) : null;
      if (!live || !canvasRef.current) return;
      drawCard(canvasRef.current, scale, { style, kindLabel, name, subtitle, detail, avatarImg, roundAvatar, qrImg, footnote, photoImg });
    })();
    return () => { live = false; };
  }, [canvasRef, scale, style, kindLabel, name, subtitle, detail, avatarImg, roundAvatar, qrImg, footnote, ready]);
}

const SHEET_CSS = `
@keyframes bbShareSheetOut { from { opacity: 1; transform: translateY(0); } to { opacity: 0; transform: translateY(40px); } }
@keyframes bbShareScrimOut { from { opacity: 1; } to { opacity: 0; } }
`;

export default function ProfileShareSheet({ open, onClose, kindLabel, name, subtitle = '', detail = '', avatarUrl = '', roundAvatar = true, link, idPrefix = 'share-card' }) {
  const { T } = useBanBe();
  const [closing, setClosing] = useState(false);
  const [style, setStyle] = useState(loadStyle);
  const [avatarImg, setAvatarImg] = useState(null);
  const [qrImg, setQrImg] = useState(null);
  const [flash, setFlash] = useState('');
  const [busy, setBusy] = useState(false);
  const canvasRef = useRef(null);
  const fileRef = useRef(null);
  const footnote = T('Quét mã QR bằng camera điện thoại để mở trong ứng dụng banbe', 'Scan with your phone camera to open this in the banbe app');

  useEffect(() => { if (open) setClosing(false); }, [open]);
  useEffect(() => { saveStyle(style); }, [style]);

  useEffect(() => {
    if (!open) return;
    let live = true;
    setAvatarImg(null);
    loadAvatar(avatarUrl).then(img => { if (live) setAvatarImg(img); });
    return () => { live = false; };
  }, [open, avatarUrl]);

  useEffect(() => {
    if (!open || !link) return;
    let live = true;
    QRCode.toDataURL(link, { margin: 1, width: 264, errorCorrectionLevel: 'M', color: { dark: '#000000', light: '#FFFFFF' } })
      .then(url => loadImage(url, false))
      .then(img => { if (live) setQrImg(img); })
      .catch(() => {});
    return () => { live = false; };
  }, [open, link]);

  const input = { style, kindLabel, name, subtitle, detail, avatarImg, roundAvatar, qrImg, footnote };
  useCardRender(canvasRef, 2, input, open);

  useEffect(() => {
    if (!open) return;
    const onKey = (e) => { if (e.key === 'Escape') requestClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  if (!open) return null;

  function requestClose() {
    if (closing) return;
    setClosing(true);
    setTimeout(() => { setClosing(false); onClose?.(); }, 220);
  }
  const say = (msg) => { setFlash(msg); setTimeout(() => setFlash(''), 2200); };

  async function renderBlob() {
    const c = document.createElement('canvas');
    let photoImg = null;
    if (style.photo) photoImg = await loadImage(style.photo, false);
    drawCard(c, 3, { ...input, photoImg });
    return new Promise((res) => { try { c.toBlob(b => res(b), 'image/png'); } catch { res(null); } });
  }

  async function downloadImage() {
    if (busy) return;
    setBusy(true);
    try {
      const blob = await renderBlob();
      if (!blob) { say(T('Không thể tạo ảnh', 'Could not create the image')); return; }
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      const slug = String(name || 'banbe').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'banbe';
      a.href = url; a.download = `banbe-${slug}.png`;
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 4000);
    } catch {
      say(T('Không thể tải ảnh', 'Could not download the image'));
    } finally { setBusy(false); }
  }

  async function copyLink() {
    try {
      await navigator.clipboard.writeText(link);
      say(T('Đã sao chép link', 'Link copied'));
    } catch {
      say(T('Không thể sao chép link', 'Could not copy the link'));
    }
  }

  async function nativeShare() {
    if (busy) return;
    setBusy(true);
    try {
      const blob = await renderBlob();
      const file = blob ? new File([blob], 'banbe-card.png', { type: 'image/png' }) : null;
      if (file && navigator.canShare?.({ files: [file] })) await navigator.share({ files: [file], title: name, url: link });
      else await navigator.share({ title: name, text: name, url: link });
    } catch (e) {
      if (e?.name !== 'AbortError') say(T('Không thể chia sẻ', 'Could not share'));
    } finally { setBusy(false); }
  }

  function pickPreset(p) {
    setStyle({ topHex: p.topHex, bottomHex: p.bottomHex, textHex: p.textHex, photo: null });
  }

  async function onPickPhoto(e) {
    const f = e.target.files?.[0];
    e.target.value = '';
    if (!f) return;
    const src = URL.createObjectURL(f);
    const img = await loadImage(src, false);
    URL.revokeObjectURL(src);
    if (!img) { say(T('Không đọc được ảnh', 'Could not read that image')); return; }
    const c = document.createElement('canvas');
    c.width = 680; c.height = 1040;
    drawCover(c.getContext('2d'), img, 0, 0, 680, 1040);
    setStyle(st => ({ ...st, photo: c.toDataURL('image/jpeg', 0.8) }));
  }

  const presetActive = (p) => !style.photo && style.topHex.toLowerCase() === p.topHex.toLowerCase() && style.bottomHex.toLowerCase() === p.bottomHex.toLowerCase();
  const colorRow = (label, key, tid) => (
    <label style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: 13, color: ink, padding: '4px 0' }}>
      {label}
      <input type="color" value={style[key]} data-testid={`${idPrefix}-${tid}`} onChange={(e) => setStyle(st => ({ ...st, [key]: e.target.value.toUpperCase() }))}
        style={{ width: 38, height: 28, border: `1px solid ${rule}`, borderRadius: 8, padding: 0, background: 'none', cursor: 'pointer' }} />
    </label>
  );
  const pill = { fontSize: 13, fontWeight: 600, color: ink, padding: '10px 14px', border: `1px solid ${rule}`, borderRadius: 999, cursor: 'pointer', background: 'transparent', fontFamily: 'inherit' };
  const canNativeShare = typeof navigator !== 'undefined' && typeof navigator.share === 'function';

  return (
    <div
      onClick={requestClose}
      data-testid={`${idPrefix}-sheet`}
      style={{ position: 'fixed', inset: 0, zIndex: 70, background: 'rgba(27,25,22,0.5)', display: 'flex', alignItems: 'flex-end', animation: closing ? 'bbShareScrimOut 0.22s ease both' : 'banbeFade 0.22s ease both' }}
    >
      <style>{SHEET_CSS}</style>
      <div
        onClick={(e) => e.stopPropagation()}
        role="dialog" aria-modal="true" aria-label={T('Thẻ chia sẻ', 'Share card')}
        style={{
          background: paper, width: '100%', maxHeight: '94%', overflowY: 'auto', borderRadius: '18px 18px 0 0', padding: '10px 20px 28px', boxSizing: 'border-box',
          animation: closing ? 'bbShareSheetOut 0.22s cubic-bezier(.22,.61,.36,1) both' : 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both',
        }}
      >
        <div style={{ width: 36, height: 4, background: rule, borderRadius: 2, margin: '6px auto 12px' }} />
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ ...display(17) }}>{T('Thẻ chia sẻ', 'Share card')}</span>
          <span onClick={requestClose} role="button" data-testid={`${idPrefix}-close`} style={{ fontSize: 13, color: ink, cursor: 'pointer', padding: '6px 0 6px 12px' }}>{T('Đóng', 'Close')}</span>
        </div>

        <div style={{ display: 'flex', justifyContent: 'center', margin: '14px 0 10px' }}>
          <canvas
            ref={canvasRef}
            data-testid={`${idPrefix}-canvas`}
            style={{ width: CARD_W * 0.92, height: CARD_H * 0.92, borderRadius: 26, boxShadow: '0 6px 14px rgba(0,0,0,0.18)', display: 'block' }}
          />
        </div>
        <p style={{ fontSize: 11, color: ink, opacity: 0.65, lineHeight: 1.5, margin: '0 0 14px' }}>
          {T('Người nhận quét mã QR bằng camera điện thoại để mở trong ứng dụng banbe (cần cài sẵn ứng dụng).', 'Recipients scan the QR with their phone camera to open it in the banbe app (the app must be installed).')}
        </p>

        <div style={{ fontSize: 11.5, fontWeight: 600, color: ink, marginBottom: 8 }}>{T('Phong cách', 'Style')}</div>
        <div style={{ display: 'flex', gap: 12, overflowX: 'auto', padding: '4px 4px 8px' }}>
          {SHARE_CARD_PRESETS.map(p => (
            <button key={p.nameEN} onClick={() => pickPreset(p)} data-testid={`${idPrefix}-preset-${p.nameEN}`}
              style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5, color: ink, fontFamily: 'inherit', flex: 'none' }}>
              <span style={{
                width: 38, height: 38, borderRadius: '50%', display: 'block',
                background: `linear-gradient(135deg, ${p.topHex}, ${p.bottomHex})`,
                boxShadow: `0 0 0 1px ${rule}${presetActive(p) ? `, 0 0 0 3px ${paper}, 0 0 0 5.5px ${ink}` : ''}`,
              }} />
              <span style={{ fontSize: 10.5 }}>{T(p.name, p.nameEN)}</span>
            </button>
          ))}
        </div>

        <div style={{ margin: '6px 0 10px' }}>
          {colorRow(T('Màu nền phía trên', 'Background top'), 'topHex', 'color-top')}
          {colorRow(T('Màu nền phía dưới', 'Background bottom'), 'bottomHex', 'color-bottom')}
          {colorRow(T('Màu chữ', 'Text colour'), 'textHex', 'color-text')}
        </div>

        <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginBottom: 16 }}>
          <button onClick={() => fileRef.current?.click()} data-testid={`${idPrefix}-pick-photo`} style={pill}>
            {style.photo ? T('Đổi ảnh nền', 'Change photo') : T('Ảnh nền', 'Background photo')}
          </button>
          {style.photo && (
            <span onClick={() => setStyle(st => ({ ...st, photo: null }))} style={{ fontSize: 13, color: ink, cursor: 'pointer' }}>{T('Bỏ ảnh', 'Remove')}</span>
          )}
          <input ref={fileRef} type="file" accept="image/*" style={{ display: 'none' }} onChange={onPickPhoto} data-testid={`${idPrefix}-photo-input`} />
        </div>

        <div onClick={downloadImage} role="button" data-testid={`${idPrefix}-download`}
          style={{ ...inkButton({ padding: '15px 0', opacity: busy ? 0.6 : 1 }) }}>
          {T('Tải ảnh xuống', 'Download image')}
        </div>
        <div style={{ display: 'flex', gap: 10, marginTop: 10 }}>
          <button onClick={copyLink} data-testid={`${idPrefix}-copy-link`} style={{ ...pill, flex: 1, borderRadius: 14, padding: '13px 0' }}>{T('Sao chép link', 'Copy link')}</button>
          {canNativeShare && (
            <button onClick={nativeShare} data-testid={`${idPrefix}-native-share`} style={{ ...pill, flex: 1, borderRadius: 14, padding: '13px 0' }}>{T('Chia sẻ…', 'Share…')}</button>
          )}
        </div>
        <p aria-live="polite" style={{ minHeight: 16, textAlign: 'center', fontSize: 11.5, color: flash.startsWith(T('Không', 'Could not')) ? alert : ink, opacity: 0.8, margin: '10px 0 0' }}>{flash}</p>
      </div>
    </div>
  );
}

// The "Share your profile card" / "Share your host card" entry row (iOS
// `shareCardCTA`), shared by the Account screen's personal + host tabs.
export function ShareCardRow({ host = false, onClick, testId, marginTop = 14 }) {
  const { T } = useBanBe();
  return (
    <div
      onClick={onClick} role="button" data-testid={testId}
      style={{
        display: 'flex', alignItems: 'center', gap: 12, margin: `${marginTop}px 20px 0`, padding: '14px 16px', borderRadius: 18, cursor: 'pointer',
        background: 'var(--bb-honey-bg)', border: '1px solid rgba(140,96,20,0.45)', color: ink,
      }}
    >
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="var(--bb-honey)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden style={{ flex: 'none' }}>
        <rect x="3" y="3" width="7" height="7" rx="1" /><rect x="14" y="3" width="7" height="7" rx="1" /><rect x="3" y="14" width="7" height="7" rx="1" />
        <path d="M14 14h3v3h-3zM20 14v.01M14 20h.01M17 20h4v-3" />
      </svg>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2, flex: 1, minWidth: 0 }}>
        <span style={{ fontSize: 15, fontWeight: 600 }}>
          {host ? T('Chia sẻ thẻ tổ chức của bạn', 'Share your host card') : T('Chia sẻ thẻ hồ sơ của bạn', 'Share your profile card')}
        </span>
        <span style={{ fontSize: 11.5, opacity: 0.8 }}>{T('Thẻ có mã QR, tuỳ chỉnh màu và ảnh nền', 'A card with a QR code — pick your colours and background')}</span>
      </div>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--bb-honey)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden style={{ flex: 'none' }}>
        <path d="M12 3v12M7 8l5-5 5 5M5 14v6h14v-6" />
      </svg>
    </div>
  );
}
