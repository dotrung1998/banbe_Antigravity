// Payment-QR helpers (web port of apps/ios/BanbeApp/Lib/PaymentQR.swift).
// Decode a QR out of an uploaded image, classify the payload, build a
// payment-app deep link, and prepare a <=1MB JPEG for the `pay-qr` bucket.
import jsQR from 'jsqr';

const MAX_BYTES = 1_000_000;

function loadImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => { URL.revokeObjectURL(url); resolve(img); };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('unreadable')); };
    img.src = url;
  });
}

function drawScaled(img, longestTarget) {
  const longest = Math.max(img.naturalWidth, img.naturalHeight, 1);
  const scale = Math.min(1, longestTarget / longest);
  const w = Math.max(1, Math.round(img.naturalWidth * scale));
  const h = Math.max(1, Math.round(img.naturalHeight * scale));
  const canvas = document.createElement('canvas');
  canvas.width = w; canvas.height = h;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, w, h);
  ctx.drawImage(img, 0, 0, w, h);
  return { canvas, ctx, w, h };
}

// Screenshots are often huge or tiny; try a few sizes before giving up.
export function decodeFromImage(img) {
  for (const size of [1400, 900, 600, 2000]) {
    const { ctx, w, h } = drawScaled(img, size);
    const code = jsQR(ctx.getImageData(0, 0, w, h).data, w, h, { inversionAttempts: 'attemptBoth' });
    if (code?.data) return code.data;
  }
  return null;
}

// -> { blob, payload }. Throws Error('noQR' | 'unreadable' | 'tooBig').
export async function prepareQrUpload(file) {
  let img;
  try { img = await loadImage(file); } catch { throw new Error('unreadable'); }
  const payload = decodeFromImage(img);
  if (!payload) throw new Error('noQR');
  const { canvas } = drawScaled(img, 1400);
  let quality = 0.9;
  let blob = null;
  while (quality > 0.25) {
    blob = await new Promise(r => canvas.toBlob(r, 'image/jpeg', quality));
    if (blob && blob.size <= 900_000) break;
    quality -= 0.15;
  }
  if (!blob || blob.size > MAX_BYTES) throw new Error('tooBig');
  return { blob, payload };
}

// ---- payload classification (EMVCo TLV: 2-char tag, 2-digit len, value) ----
function tlv(s) {
  const out = [];
  let i = 0;
  while (i + 4 <= s.length) {
    const len = parseInt(s.slice(i + 2, i + 4), 10);
    if (!Number.isFinite(len) || len < 0 || i + 4 + len > s.length) break;
    out.push([s.slice(i, i + 2), s.slice(i + 4, i + 4 + len)]);
    i += 4 + len;
  }
  return out;
}
const pick = (list, tag) => list.find(x => x[0] === tag)?.[1];

export function parseVietQR(payload) {
  const top = tlv(payload);
  if (!pick(top, '00')) return null;
  const merchant = pick(top, '38');
  if (!merchant) return null;
  const m = tlv(merchant);
  if ((pick(m, '00') || '').toUpperCase() !== 'A000000727') return null;
  const ben = pick(m, '01');
  if (!ben) return null;
  const b = tlv(ben);
  const bin = pick(b, '00');
  const account = pick(b, '01');
  if (!bin || !account) return null;
  const amountStr = pick(top, '54');
  const amount = amountStr ? parseInt(amountStr.split('.')[0], 10) : null;
  const f62 = pick(top, '62');
  const memo = f62 ? pick(tlv(f62), '08') : null;
  return { bin, account, amountVnd: Number.isFinite(amount) ? amount : null, memo: memo || null };
}

const BIN_TO_CODE = {
  '970436': 'vcb', '970407': 'tcb', '970422': 'mb', '970415': 'ctg',
  '970418': 'bidv', '970405': 'agribank', '970416': 'acb', '970432': 'vpb',
  '970423': 'tpb', '970403': 'stb', '970441': 'vib', '970443': 'shb',
  '970431': 'eib', '970426': 'msb', '970448': 'ocb', '970440': 'seab',
  '970437': 'hdb', '970429': 'scb', '970428': 'nab', '970409': 'bab',
  '970449': 'lpb',
};

export function vietQrLink(info) {
  const code = BIN_TO_CODE[info.bin];
  const p = new URLSearchParams();
  if (code) p.set('app', code);
  p.set('ba', code ? `${info.account}@${code}` : info.account);
  if (info.amountVnd > 0) p.set('am', String(info.amountVnd));
  if (info.memo) p.set('tn', info.memo);
  return `https://dl.vietqr.io/pay?${p.toString()}`;
}

const URL_SCHEMES = ['http:', 'https:', 'momo:', 'zalopay:', 'venmo:', 'cashme:', 'paypal:'];

// -> { kind: 'vietqr', info, link } | { kind: 'url', link, host } | { kind: 'text', text }
export function classifyQr(payload) {
  const text = String(payload || '').trim();
  const info = parseVietQR(text);
  if (info) return { kind: 'vietqr', info, link: vietQrLink(info) };
  try {
    const u = new URL(text);
    if (URL_SCHEMES.includes(u.protocol)) return { kind: 'url', link: text, host: u.host || u.protocol };
  } catch { /* not a URL */ }
  return { kind: 'text', text };
}

export function qrKindLabel(c, T) {
  if (c.kind === 'vietqr') return 'VietQR';
  if (c.kind === 'url') return T('Ví / liên kết thanh toán', 'Wallet / payment link') + (c.host ? ` · ${c.host}` : '');
  return T('Mã QR (văn bản)', 'QR (text)');
}

export function isMobileBrowser() {
  if (typeof navigator === 'undefined') return false;
  return /Android|iPhone|iPad|iPod/i.test(navigator.userAgent)
    || (navigator.maxTouchPoints > 1 && /Macintosh/.test(navigator.userAgent));
}
