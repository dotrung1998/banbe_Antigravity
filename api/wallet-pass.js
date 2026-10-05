import { createClient } from '@supabase/supabase-js';
import {
  readWalletConfig, getWalletAdmin, buildPass, stateHash, isLive, isLiveGift, TICKET_SELECT,
} from './_lib/walletPass.js';

// Issues a signed Apple Wallet pass (.pkpass) for ONE ticket the caller owns.
//
// A pass must be signed with a Pass Type ID certificate from the Apple
// Developer Program, so the private key lives here as Vercel env secrets and
// never in the app. Until they are set this answers 503 WALLET_NOT_CONFIGURED
// and the app says so, instead of handing Wallet a pass it would reject.
//
//   WALLET_PASS_TYPE_ID   pass.com.…
//   WALLET_TEAM_ID        10-char Apple Team ID
//   WALLET_SIGNER_CERT    base64 of the Pass Type ID certificate, PEM
//   WALLET_SIGNER_KEY     base64 of its private key, PEM
//   WALLET_SIGNER_KEY_PASSPHRASE   optional
//   WALLET_WWDR_CERT      base64 of Apple's WWDR intermediate certificate, PEM
//   WALLET_AUTH_SECRET    optional; per-pass update tokens are derived from it
//   SUPABASE_SERVICE_ROLE_KEY      needed for the update service (see api/wallet/)
//
// With the service-role key present the pass is registered for updates, so a
// later gift (or cancellation) voids it in the holder's Wallet. Without it the
// pass is still issued, just without the update service.
//
// Authorization is the caller's own access token + RLS on `bookings` (same
// approach as api/payment-document.js): the pass is only built for a booking
// the caller can already read, and only while it is a live, un-gifted ticket.
//
// POST { bookingId, design?: { background, foreground, label, banner } }
//   colours are "#RRGGBB"; banner is a base64 PNG (the app crops it to 750x246).

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HEX = /^#[0-9a-f]{6}$/i;
const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const MAX_BANNER_BYTES = 1_500_000;

const text = (v) => (typeof v === 'string' ? v.trim() : '');

// GET ?gift=<admission token> — the "Add to Apple Wallet" button inside a gift
// ticket PDF. The recipient may have no banbe account, so there is no login:
// the unguessable admission token (the same secret the PDF's QR already
// carries) is the credential. The pass is the recipient's own, default design,
// and is NOT registered for updates (it has no purchaser-side lifecycle).
async function giftPass(req, res) {
  const cfg = readWalletConfig();
  const admin = getWalletAdmin();
  if (!cfg || !admin) return res.status(503).json({ error: 'WALLET_NOT_CONFIGURED' });
  const token = text(req.query?.gift);
  if (!UUID.test(token)) return res.status(400).json({ error: 'VALID_TICKET_REQUIRED' });
  try {
    const { data: booking, error } = await admin
      .from('bookings').select(TICKET_SELECT).eq('admission_token', token).maybeSingle();
    if (error) throw error;
    if (!booking) return res.status(404).json({ error: 'TICKET_NOT_FOUND' });
    if (!isLiveGift(booking)) return res.status(409).json({ error: 'TICKET_NOT_READY' });
    const origin = `https://${req.headers.host || 'banbe-two.vercel.app'}`;
    const pass = await buildPass({
      booking, cfg, origin, webService: false, gift: true,
      design: { background: '#1C1C1E', foreground: '#FFFFFF', label: '#FFFFFF', banner: null },
    });
    res.setHeader('Content-Type', 'application/vnd.apple.pkpass');
    res.setHeader('Content-Disposition', 'attachment; filename="banbe-ticket.pkpass"');
    res.setHeader('Cache-Control', 'private, no-store');
    return res.status(200).send(pass.getAsBuffer());
  } catch (e) {
    console.warn('wallet gift pass failed:', e);
    return res.status(500).json({ error: 'WALLET_PASS_FAILED' });
  }
}

export default async function handler(req, res) {
  if (req.method === 'GET') return giftPass(req, res);
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }

  const cfg = readWalletConfig();
  if (!cfg) return res.status(503).json({ error: 'WALLET_NOT_CONFIGURED' });

  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL
    || 'https://ukchdgdnwytretvqjjqu.supabase.co';
  const anonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY
    || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVrY2hkZ2Rud3l0cmV0dnFqanF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg3MjMyMjYsImV4cCI6MjEwNDI5OTIyNn0.TgyEJLTXTZgCa6ulsseY3JlrdSmEfOgqVPNh0nSgu90';

  const token = text((req.headers.authorization || '').replace(/^Bearer\s+/i, ''));
  if (!token) return res.status(401).json({ error: 'AUTH_REQUIRED' });

  const body = typeof req.body === 'string' ? safeJson(req.body) : (req.body || {});
  const bookingId = text(body.bookingId);
  if (!UUID.test(bookingId)) return res.status(400).json({ error: 'VALID_BOOKING_REQUIRED' });

  const design = body.design || {};
  const background = HEX.test(text(design.background)) ? text(design.background) : '#1C1C1E';
  const foreground = HEX.test(text(design.foreground)) ? text(design.foreground) : '#FFFFFF';
  const label = HEX.test(text(design.label)) ? text(design.label) : foreground;

  let banner = null;
  if (design.banner) {
    banner = Buffer.from(text(design.banner), 'base64');
    if (!banner.length || banner.length > MAX_BANNER_BYTES || !banner.subarray(0, 8).equals(PNG_MAGIC)) {
      return res.status(400).json({ error: 'BANNER_MUST_BE_PNG_UNDER_1_5MB' });
    }
  }

  const client = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  try {
    const { data: booking, error } = await client
      .from('bookings').select(TICKET_SELECT).eq('id', bookingId).maybeSingle();
    if (error) throw error;
    // Same answer for "not yours" and "doesn't exist".
    if (!booking) return res.status(404).json({ error: 'BOOKING_NOT_FOUND' });
    if (booking.status !== 'confirmed' || booking.payment_state !== 'confirmed') {
      return res.status(409).json({ error: 'TICKET_NOT_READY' });
    }
    // A gifted seat belongs to the recipient; the purchaser gets no QR for it.
    if (!isLive(booking)) return res.status(409).json({ error: 'TICKET_GIFTED' });

    // Remember the design + the state this pass shows, so the update service can
    // rebuild the same-looking pass (or void it) later.
    const admin = getWalletAdmin();
    let webService = false;
    if (admin) {
      const { error: upErr } = await admin.from('wallet_passes').upsert({
        serial_number: booking.id,
        pass_type_id: cfg.passTypeId,
        owner_id: booking.purchaser_id || booking.user_id || null,
        background, foreground, label,
        banner_png_b64: banner ? banner.toString('base64') : null,
        state_hash: stateHash(booking),
        updated_at: new Date().toISOString(),
      });
      webService = !upErr;
      if (upErr) console.warn('wallet_passes upsert failed (migration 140 applied?):', upErr.message);
    }

    const origin = `https://${req.headers.host || 'banbe-two.vercel.app'}`;
    const pass = await buildPass({
      booking, cfg, origin, webService,
      design: { background, foreground, label, banner },
    });

    res.setHeader('Content-Type', 'application/vnd.apple.pkpass');
    res.setHeader('Content-Disposition', 'attachment; filename="banbe-ticket.pkpass"');
    // The admission credential is inside it.
    res.setHeader('Cache-Control', 'private, no-store');
    return res.status(200).send(pass.getAsBuffer());
  } catch (e) {
    console.warn('wallet-pass failed:', e);
    return res.status(500).json({ error: 'WALLET_PASS_FAILED' });
  }
}

function safeJson(s) {
  try { return JSON.parse(s); } catch { return {}; }
}
