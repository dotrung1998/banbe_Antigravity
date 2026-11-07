// Public-media gateway for the Cloudflare R2 hybrid (see
// .claude/notes/28-r2-hybrid-media.md). Single function (Hobby plan cap = 12).
// With no MEDIA_* / R2_* env set, `init` answers {provider:'supabase'} and
// clients keep using the legacy Supabase Storage path.
import { handleMediaRequest } from './_lib/media.js';
import { buildMediaCtx } from './_lib/mediaCtx.js';

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  const ctx = buildMediaCtx();
  if (!ctx.admin || !ctx.db) {
    // Feature is optional: tell callers to use the legacy path rather than failing uploads.
    if (req.method === 'POST' && req.body?.op === 'init') return res.status(200).json({ provider: 'supabase' });
    return res.status(503).json({ error: 'MEDIA_NOT_CONFIGURED' });
  }
  const { status, json } = await handleMediaRequest(ctx, { method: req.method, headers: req.headers, body: req.body });
  return res.status(status).json(json);
}
