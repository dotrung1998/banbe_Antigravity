import { createClient } from '@supabase/supabase-js';
import { readApnsConfig, sendAlertBatch } from '../apnsAlerts.js';

// POST /api/cron?job=push-drain — woken by the database (migration 194: pg_net from push_kick(),
// plus the per-minute push_drain_tick() retry), never by a Vercel cron (Hobby crons are daily only).
// Claims queued pushes, sends them through APNs, reports back. Fails CLOSED without CRON_SECRET.
// Without APNS_* env it does nothing (rows expire after 15 minutes in the database).
const TIME_BUDGET_MS = 8000;

export default async function handler(req, res) {
  const secret = process.env.CRON_SECRET;
  if (!secret || (req.headers.authorization || '') !== `Bearer ${secret}`) {
    return res.status(401).json({ error: 'UNAUTHORIZED' });
  }
  const cfg = readApnsConfig();
  if (!cfg) return res.status(200).json({ skipped: 'APNS_NOT_CONFIGURED' });
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return res.status(500).json({ error: 'SUPABASE_NOT_CONFIGURED' });
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

  const started = Date.now();
  const totals = { claimed: 0, sent: 0, failed: 0, gone_tokens: 0 };
  while (Date.now() - started < TIME_BUDGET_MS) {
    const { data: items, error } = await db.rpc('push_claim', { p_limit: 50 });
    if (error) { console.error('push-drain: claim failed:', error.message); return res.status(500).json({ error: 'CLAIM_FAILED', ...totals }); }
    if (!Array.isArray(items) || items.length === 0) break;
    totals.claimed += items.length;
    const results = await sendAlertBatch(items, cfg);
    for (const r of results) {
      if (r.status === 'sent') totals.sent += 1; else totals.failed += 1;
      totals.gone_tokens += r.gone_tokens.length;
    }
    const { error: doneErr } = await db.rpc('push_complete', { p_results: results });
    if (doneErr) { console.error('push-drain: complete failed:', doneErr.message); return res.status(500).json({ error: 'COMPLETE_FAILED', ...totals }); }
  }
  return res.status(200).json(totals);
}
