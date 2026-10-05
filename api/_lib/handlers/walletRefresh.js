import { createClient } from '@supabase/supabase-js';
import { readWalletConfig, getWalletAdmin, TICKET_SELECT } from '../walletPass.js';
import { refreshWalletPass } from '../walletRefresh.js';

// "This ticket just changed — update its Wallet pass now." The app calls it
// right after a successful gift so the purchaser's pass is voided straight away
// instead of waiting for the daily sweep. The caller must be able to read the
// booking (RLS, as in api/wallet-pass.js); the push itself uses the service role.
//
// POST { bookingId }  →  { changed, pushed }
// Always 200 for a booking the caller can read, even when Wallet isn't set up:
// failing here must never look like the gift failed.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const text = (v) => (typeof v === 'string' ? v.trim() : '');

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }
  const token = text((req.headers.authorization || '').replace(/^Bearer\s+/i, ''));
  if (!token) return res.status(401).json({ error: 'AUTH_REQUIRED' });
  const body = typeof req.body === 'string' ? safeJson(req.body) : (req.body || {});
  const bookingId = text(body.bookingId);
  if (!UUID.test(bookingId)) return res.status(400).json({ error: 'VALID_BOOKING_REQUIRED' });

  const cfg = readWalletConfig();
  const admin = getWalletAdmin();
  if (!cfg || !admin) return res.status(200).json({ changed: false, pushed: 0, skipped: 'WALLET_NOT_CONFIGURED' });

  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL
    || 'https://ukchdgdnwytretvqjjqu.supabase.co';
  const anonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY
    || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVrY2hkZ2Rud3l0cmV0dnFqanF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg3MjMyMjYsImV4cCI6MjEwNDI5OTIyNn0.TgyEJLTXTZgCa6ulsseY3JlrdSmEfOgqVPNh0nSgu90';
  const client = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  try {
    const { data: booking } = await client.from('bookings').select(TICKET_SELECT).eq('id', bookingId).maybeSingle();
    if (!booking) return res.status(404).json({ error: 'BOOKING_NOT_FOUND' });
    return res.status(200).json(await refreshWalletPass(admin, bookingId, cfg));
  } catch (e) {
    console.warn('wallet-refresh failed:', e);
    return res.status(200).json({ changed: false, pushed: 0, skipped: 'REFRESH_FAILED' });
  }
}

function safeJson(s) {
  try { return JSON.parse(s); } catch { return {}; }
}
