import { createClient } from '@supabase/supabase-js';
import { readApnsConfig, sendAlertBatch, missingApnsSettings, dryRunSummary } from '../apnsAlerts.js';

// POST /api/cron?job=push-drain — woken by the database (migration 194: pg_net from push_kick(), plus the per-minute
// push_drain_tick()), never by a Vercel cron (Hobby crons are daily only). Fails CLOSED without CRON_SECRET.
//   * switch `push_enabled` off  → push_claim returns nothing, so this does nothing.
//   * switch on, APNs credentials missing → DRY RUN: logs counts only (kind, devices; never content, tokens or ids)
//     and closes the rows as `skipped_no_credentials`.
//   * switch on + credentials → sends through APNs and reports back with push_complete.
const TIME_BUDGET_MS = 8000;

export default async function handler(req, res) {
  const secret = process.env.CRON_SECRET;
  if (!secret || (req.headers.authorization || '') !== `Bearer ${secret}`) {
    return res.status(401).json({ error: 'UNAUTHORIZED' });
  }
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return res.status(500).json({ error: 'SUPABASE_NOT_CONFIGURED' });
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return res.status(200).json(await drain(db, readApnsConfig(), { missing: missingApnsSettings() }));
}

/** One drain pass. Exported for tests (db = anything with rpc(name, args) → {data, error}). */
export async function drain(db, cfg, { missing = [], send = sendAlertBatch, log = console.log, budgetMs = TIME_BUDGET_MS } = {}) {
  const started = Date.now();
  const totals = { claimed: 0, sent: 0, failed: 0, gone_tokens: 0, dry_run: !cfg };
  while (Date.now() - started < budgetMs) {
    const { data: items, error } = await db.rpc('push_claim', { p_limit: 50 });
    if (error) { console.error('push-drain: claim failed:', error.message); return { error: 'CLAIM_FAILED', ...totals }; }
    if (!Array.isArray(items) || items.length === 0) break;
    totals.claimed += items.length;
    let results;
    if (!cfg) {
      log('push-drain DRY RUN (missing ' + missing.join(', ') + '): would send', JSON.stringify(dryRunSummary(items)));
      results = items.map((it) => ({ id: it.id, status: 'skipped_no_credentials', error: 'dry_run', gone_tokens: [], moved_tokens: [] }));
    } else {
      results = await send(items, cfg);
    }
    for (const r of results) {
      if (r.status === 'sent') totals.sent += 1; else if (r.status !== 'skipped_no_credentials') totals.failed += 1;
      totals.gone_tokens += r.gone_tokens.length;
    }
    const { error: doneErr } = await db.rpc('push_complete', { p_results: results });
    if (doneErr) { console.error('push-drain: complete failed:', doneErr.message); return { error: 'COMPLETE_FAILED', ...totals }; }
  }
  return totals;
}
