import crypto from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { PKPass } from 'passkit-generator';
import { PNG } from 'pngjs';

// Shared by api/wallet-pass.js (issue), api/wallet/[...path].js (Apple's pass
// update web service), api/wallet-refresh.js and the sweep cron, so a pass
// looks and behaves the same whichever of them produced it.

const text = (v) => (typeof v === 'string' ? v.trim() : '');
const b64 = (v) => (v ? Buffer.from(v, 'base64') : null);

export const TICKET_SELECT =
  'id, code, qty, status, payment_state, admission_token, gifted_at, user_id, purchaser_id, recipient_name, '
  + 'events(name, starts_at, area, address_line)';

export function readWalletConfig() {
  const cfg = {
    passTypeId: text(process.env.WALLET_PASS_TYPE_ID),
    teamId: text(process.env.WALLET_TEAM_ID),
    signerCert: b64(process.env.WALLET_SIGNER_CERT),
    signerKey: b64(process.env.WALLET_SIGNER_KEY),
    wwdr: b64(process.env.WALLET_WWDR_CERT),
    passphrase: text(process.env.WALLET_SIGNER_KEY_PASSPHRASE) || undefined,
    authSecret: text(process.env.WALLET_AUTH_SECRET),
  };
  if (!(cfg.passTypeId && cfg.teamId && cfg.signerCert && cfg.signerKey && cfg.wwdr)) return null;
  // Without a dedicated secret, derive one from the signing key: still secret,
  // still stable across deploys.
  if (!cfg.authSecret) cfg.authSecret = crypto.createHash('sha256').update(cfg.signerKey).digest('hex');
  return cfg;
}

/** Per-pass token Wallet echoes back as `Authorization: ApplePass <token>`. */
export function authTokenFor(serial, cfg) {
  return crypto.createHmac('sha256', cfg.authSecret).update(String(serial)).digest('hex');
}

export function tokenMatches(header, serial, cfg) {
  const given = text(String(header || '').replace(/^ApplePass\s+/i, ''));
  const want = authTokenFor(serial, cfg);
  const a = Buffer.from(given);
  const b = Buffer.from(want);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** A ticket is a live admission credential only while all of this holds. */
export function isLive(booking) {
  return booking.status === 'confirmed' && booking.payment_state === 'confirmed' && !booking.gifted_at;
}

/** A GIFTED seat is the recipient's live admission, so for their pass "gifted" is not a reason to void. */
export function isLiveGift(booking) {
  return !!booking.gifted_at && booking.status === 'confirmed' && booking.payment_state === 'confirmed';
}

/** Everything the pass shows that can change; a different hash means "re-issue". */
export function stateHash(booking) {
  const ev = booking.events || {};
  return crypto.createHash('sha256').update(JSON.stringify([
    isLive(booking), booking.admission_token || booking.id, booking.code, booking.qty,
    ev.name, ev.starts_at, ev.area, ev.address_line,
  ])).digest('hex');
}

const rgb = (hex) => {
  const n = Number.parseInt(hex.slice(1), 16);
  return `rgb(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255})`;
};

function when(startsAt) {
  if (!startsAt) return '';
  return new Intl.DateTimeFormat('vi-VN', {
    timeZone: 'Asia/Ho_Chi_Minh', weekday: 'short', day: '2-digit', month: '2-digit',
    year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false,
  }).format(new Date(startsAt)) + ' (GMT+7)';
}

let iconCache = null;
async function loadIcon(origin) {
  if (iconCache) return iconCache;
  const resp = await fetch(`${origin}/banbe-mark.png`);
  if (!resp.ok) throw new Error('icon fetch failed');
  iconCache = Buffer.from(await resp.arrayBuffer());
  return iconCache;
}

const wordmarkCache = new Map();

/**
 * The home-screen wordmark (public/banbe-wordmark.png, the same artwork
 * BanbeLogo draws in the app), recoloured to the card's text colour so it stays
 * readable on any background the holder picks, cropped to its visible ink and
 * scaled to Wallet's logo box (at most 160x50pt). Returns { x1, x2 } PNG buffers.
 */
async function loadWordmark(origin, colorHex) {
  const hit = wordmarkCache.get(colorHex);
  if (hit) return hit;
  const resp = await fetch(`${origin}/banbe-wordmark.png`);
  if (!resp.ok) throw new Error('wordmark fetch failed');
  const src = PNG.sync.read(Buffer.from(await resp.arrayBuffer()));

  const n = Number.parseInt(colorHex.slice(1), 16);
  const [cr, cg, cb] = [(n >> 16) & 255, (n >> 8) & 255, n & 255];

  // Bounding box of the visible pixels.
  let x0 = src.width, y0 = src.height, x1 = -1, y1 = -1;
  for (let y = 0; y < src.height; y += 1) {
    for (let x = 0; x < src.width; x += 1) {
      if (src.data[(y * src.width + x) * 4 + 3] > 16) {
        if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) throw new Error('wordmark is empty');
  const cw = x1 - x0 + 1;
  const ch = y1 - y0 + 1;

  const render = (targetH) => {
    const targetW = Math.max(1, Math.round(cw * targetH / ch));
    const out = new PNG({ width: targetW, height: targetH });
    // Box-filter downscale, alpha-weighted, painted in the card's text colour.
    for (let ty = 0; ty < targetH; ty += 1) {
      const sy0 = y0 + Math.floor(ty * ch / targetH);
      const sy1 = Math.max(sy0 + 1, y0 + Math.floor((ty + 1) * ch / targetH));
      for (let tx = 0; tx < targetW; tx += 1) {
        const sx0 = x0 + Math.floor(tx * cw / targetW);
        const sx1 = Math.max(sx0 + 1, x0 + Math.floor((tx + 1) * cw / targetW));
        let a = 0; let count = 0;
        for (let sy = sy0; sy < sy1; sy += 1) {
          for (let sx = sx0; sx < sx1; sx += 1) {
            a += src.data[(sy * src.width + sx) * 4 + 3];
            count += 1;
          }
        }
        const o = (ty * targetW + tx) * 4;
        out.data[o] = cr; out.data[o + 1] = cg; out.data[o + 2] = cb;
        out.data[o + 3] = Math.round(a / count);
      }
    }
    return PNG.sync.write(out);
  };

  const result = { x1: render(50), x2: render(100) };
  wordmarkCache.set(colorHex, result);
  return result;
}

/**
 * Builds the .pkpass. `design` = { background, foreground, label, banner(Buffer|null) }.
 * A ticket that is no longer live is built as a VOIDED pass with no barcode, so
 * the old QR disappears from the holder's Wallet instead of just failing at the door.
 */
export async function buildPass({ booking, design, cfg, origin, webService = true, gift = false }) {
  const ev = booking.events || {};
  const live = gift ? isLiveGift(booking) : isLive(booking);
  const icon = await loadIcon(origin);
  const wordmark = await loadWordmark(origin, design.foreground);

  const files = { 'icon.png': icon, 'icon@2x.png': icon, 'logo.png': wordmark.x1, 'logo@2x.png': wordmark.x2 };
  if (design.banner) files['strip@2x.png'] = design.banner;

  const props = {
    formatVersion: 1,
    passTypeIdentifier: cfg.passTypeId,
    teamIdentifier: cfg.teamId,
    // A recipient's pass gets its own serial so it never collides with the
    // purchaser's pass for the same booking row (which is voided on gift).
    serialNumber: gift ? `gift-${booking.admission_token || booking.id}` : String(booking.id),
    organizationName: 'banbe',
    description: `banbe ticket · ${ev.name || ''}`,
    backgroundColor: rgb(design.background),
    foregroundColor: rgb(design.foreground),
    labelColor: rgb(design.label),
    voided: !live,
  };
  if (webService) {
    props.webServiceURL = `${origin}/api/wallet`;
    props.authenticationToken = authTokenFor(booking.id, cfg);
  }

  const pass = new PKPass(files, {
    wwdr: cfg.wwdr, signerCert: cfg.signerCert, signerKey: cfg.signerKey, signerKeyPassphrase: cfg.passphrase,
  }, props);
  pass.type = 'eventTicket';

  pass.primaryFields.push({ key: 'event', label: 'EVENT', value: ev.name || 'banbe' });
  if (!live) {
    pass.secondaryFields.push({
      key: 'status', label: 'STATUS',
      value: booking.gifted_at ? 'Gifted · no longer valid for entry' : 'No longer valid for entry',
    });
    return pass;
  }

  if (gift && booking.recipient_name) {
    pass.headerFields.push({ key: 'to', label: 'GIFTED TO', value: booking.recipient_name });
  }
  const startsText = when(ev.starts_at);
  if (startsText) pass.secondaryFields.push({ key: 'when', label: 'DATE & TIME', value: startsText });
  const place = text(ev.address_line) || text(ev.area);
  if (place) pass.secondaryFields.push({ key: 'where', label: 'VENUE', value: place });
  if (booking.code) pass.auxiliaryFields.push({ key: 'code', label: 'ENTRY CODE', value: booking.code });
  if (booking.qty > 1) pass.auxiliaryFields.push({ key: 'qty', label: 'ADMITS', value: String(booking.qty) });
  pass.setBarcodes({
    message: String(booking.admission_token || booking.id),
    format: 'PKBarcodeFormatQR',
    messageEncoding: 'iso-8859-1',
    altText: booking.code || undefined,
  });
  if (ev.starts_at) pass.setRelevantDate(new Date(ev.starts_at));
  return pass;
}

export function designFromRow(row) {
  return {
    background: row?.background || '#1C1C1E',
    foreground: row?.foreground || '#FFFFFF',
    label: row?.label || row?.foreground || '#FFFFFF',
    banner: row?.banner_png_b64 ? Buffer.from(row.banner_png_b64, 'base64') : null,
  };
}

const SUPABASE_URL = () => process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
  || process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://ukchdgdnwytretvqjjqu.supabase.co';

/** Service-role client for the wallet tables, or null when the key isn't set. */
export function getWalletAdmin() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  return createClient(SUPABASE_URL(), key, { auth: { persistSession: false, autoRefreshToken: false } });
}
