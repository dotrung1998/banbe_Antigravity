// Local-only backend for the E2E harness, three loopback servers in one process:
//   :5198  the REAL api/*.js handlers behind a minimal Vercel-style req/res adapter
//   :59010 "media domain": GET/HEAD of the PUBLIC bucket only (models an R2 custom domain; no listing, no staging)
//   :59100 Cloudflare purge-cache mock + request stats (GET /__calls, /__stats; DELETE /__calls, /__stats)
import http from 'node:http';
import { assertIsolated, LOCAL } from './guard.mjs';
assertIsolated();
const { r2Config, signedFetch } = await import('../../api/_lib/r2.js');
const apiRoutes = {
  '/api/media': (await import('../../api/media.js')).default,
  '/api/cron': (await import('../../api/cron.js')).default,
};
const cfg = r2Config(process.env);

function adapt(req, res, body) {
  const u = new URL(req.url, LOCAL.api);
  const query = Object.fromEntries(u.searchParams);
  const vreq = Object.assign(req, { query, body: undefined });
  if (body.length) { try { vreq.body = JSON.parse(body.toString('utf8')); } catch { vreq.body = body.toString('utf8'); } }
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (o) => { if (!res.getHeader('content-type')) res.setHeader('content-type', 'application/json'); res.end(JSON.stringify(o)); return res; };
  return { u, vreq };
}
http.createServer(async (req, res) => {
  const chunks = []; for await (const c of req) chunks.push(c);
  const { u, vreq } = adapt(req, res, Buffer.concat(chunks));
  // Test-only control: flip server feature flags between tests (loopback-only process, allowlisted keys).
  if (u.pathname === '/__env') {
    const ALLOWED = ['MEDIA_R2_UPLOADS', 'MEDIA_R2_UPLOAD_USER_IDS', 'MEDIA_R2_UPLOAD_PERCENT', 'MEDIA_UPLOADS_PER_HOUR', 'MEDIA_MAX_PENDING', 'MEDIA_DEMOTE_LEGACY_INVITE', 'MEDIA_SWEEP_STORIES'];
    const changes = vreq.body && typeof vreq.body === 'object' ? vreq.body : {};
    for (const [k, v] of Object.entries(changes)) { if (!ALLOWED.includes(k)) { res.statusCode = 400; return res.end('{"error":"KEY_NOT_ALLOWED"}'); } if (v === null) delete process.env[k]; else process.env[k] = String(v); }
    return res.status(200).json(Object.fromEntries(ALLOWED.map((k) => [k, process.env[k] ?? null])));
  }
  const handler = apiRoutes[u.pathname];
  if (!handler) { res.statusCode = 404; return res.end('{"error":"NOT_FOUND"}'); }
  try { await handler(vreq, res); } catch (e) { console.error('api error:', e?.message); if (!res.headersSent) { res.statusCode = 500; res.end('{"error":"LOCAL_API_ERROR"}'); } }
}).listen(5198, '127.0.0.1');

const stats = { requests: 0, bytes: 0, byKey: {} };
http.createServer(async (req, res) => {
  res.setHeader('access-control-allow-origin', '*');
  if (!['GET', 'HEAD'].includes(req.method)) { res.statusCode = 405; return res.end(); }
  const key = decodeURIComponent(new URL(req.url, LOCAL.mediaBase).pathname.replace(/^\//, ''));
  if (!cfg.ok || !/^v1\/[A-Za-z0-9_\/.-]+$/.test(key) || key.includes('..')) { res.statusCode = 404; return res.end(); }
  const r = await signedFetch(cfg, { method: 'GET', bucket: cfg.publicBucket, key });
  if (!r.ok) { res.statusCode = r.status === 404 ? 404 : 502; return res.end(); }
  const buf = Buffer.from(await r.arrayBuffer());
  res.setHeader('content-type', r.headers.get('content-type') || 'application/octet-stream');
  if (r.headers.get('cache-control')) res.setHeader('cache-control', r.headers.get('cache-control'));
  res.setHeader('content-length', buf.length);
  stats.requests++; stats.bytes += buf.length; stats.byKey[key] = (stats.byKey[key] || 0) + 1;
  res.end(req.method === 'HEAD' ? undefined : buf);
}).listen(59010, '127.0.0.1');

const calls = [];
http.createServer(async (req, res) => {
  const chunks = []; for await (const c of req) chunks.push(c);
  const u = new URL(req.url, LOCAL.cloudflareMock);
  const json = (c, o) => { res.statusCode = c; res.setHeader('content-type', 'application/json'); res.end(JSON.stringify(o)); };
  if (u.pathname === '/__calls') { if (req.method === 'DELETE') calls.length = 0; return json(200, calls); }
  if (u.pathname === '/__stats') { if (req.method === 'DELETE') { stats.requests = 0; stats.bytes = 0; stats.byKey = {}; } return json(200, stats); }
  const m = /^\/client\/v4\/zones\/([^/]+)\/purge_cache$/.exec(u.pathname);
  if (req.method === 'POST' && m) {
    if (req.headers.authorization !== 'Bearer local-purge-token' || m[1] !== 'local-zone') return json(403, { success: false });
    const body = JSON.parse(Buffer.concat(chunks).toString() || '{}');
    calls.push({ zone: m[1], files: body.files || [] });
    return json(200, { success: true, result: { id: 'mock' } });
  }
  json(404, { success: false });
}).listen(59100, '127.0.0.1');
console.log('local backend ready: api :5198, media :59010, cloudflare-mock :59100');
