import { buildMediaCtx } from '../mediaCtx.js';
import { sweep } from '../media.js';

// Daily: (1) unpublish R2 event media whose event is no longer public
// (invite-only switch, withdrawn, deleted) and purge CDN copies, (2) discard
// stale half-finished uploads, (3) retry any unfinished deletion.
// Fails CLOSED if CRON_SECRET is unset (unlike older jobs).
export default async function handler(req, res) {
  const secret = process.env.CRON_SECRET;
  if (!secret || (req.headers.authorization || '') !== `Bearer ${secret}`) {
    return res.status(401).json({ error: 'UNAUTHORIZED' });
  }
  const ctx = buildMediaCtx();
  if (!ctx.db || !ctx.r2.configured) return res.status(200).json({ skipped: 'MEDIA_NOT_CONFIGURED' });
  return res.status(200).json(await sweep(ctx));
}
