// Minimal Cloudflare R2 client (S3-compatible, AWS SigV4) with no dependencies.
// SERVER ONLY — R2 credentials never leave api/. Never log URLs or headers
// produced here: presigned URLs are bearer tokens until they expire.
import { createHash, createHmac } from 'node:crypto';

const sha256hex = (data) => createHash('sha256').update(data).digest('hex');
const hmac = (key, data) => createHmac('sha256', key).update(data).digest();

// RFC 3986 encoding, keeping '/' in object keys.
export function encodeKey(key) {
  return key.split('/').map((seg) => encodeURIComponent(seg).replace(/[!'()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase())).join('/');
}

export function r2Config(env = process.env) {
  const accountId = env.R2_ACCOUNT_ID;
  const accessKeyId = env.R2_ACCESS_KEY_ID;
  const secretAccessKey = env.R2_SECRET_ACCESS_KEY;
  const publicBucket = env.R2_PUBLIC_BUCKET;
  const stagingBucket = env.R2_STAGING_BUCKET;
  const missing = Object.entries({ R2_ACCOUNT_ID: accountId, R2_ACCESS_KEY_ID: accessKeyId, R2_SECRET_ACCESS_KEY: secretAccessKey, R2_PUBLIC_BUCKET: publicBucket, R2_STAGING_BUCKET: stagingBucket })
    .filter(([, v]) => !v).map(([k]) => k);
  if (missing.length) return { ok: false, missing };
  return {
    ok: true, accountId, accessKeyId, secretAccessKey, publicBucket, stagingBucket,
    endpoint: env.R2_ENDPOINT || `https://${accountId}.r2.cloudflarestorage.com`,
    publicBaseUrl: (env.MEDIA_PUBLIC_BASE_URL || '').replace(/\/$/, ''),
  };
}

function signingKey(secret, date, region, service) {
  return hmac(hmac(hmac(hmac('AWS4' + secret, date), region), service), 'aws4_request');
}

const amzDate = (d) => d.toISOString().replace(/[:-]|\.\d{3}/g, '');

/** Presigned URL (query-string auth). `signedHeaders` are extra headers the
 *  client MUST send verbatim (e.g. content-type, content-length). */
export function presignUrl(cfg, { method, bucket, key, expiresIn = 300, headers = {}, now = new Date(), maxExpires = 900 }) {
  const host = new URL(cfg.endpoint).host;
  const stamp = amzDate(now);
  const date = stamp.slice(0, 8);
  const region = cfg.region || 'auto';
  const scope = `${date}/${region}/s3/aws4_request`;
  const lower = { host, ...Object.fromEntries(Object.entries(headers).map(([k, v]) => [k.toLowerCase(), String(v).trim()])) };
  const names = Object.keys(lower).sort();
  const query = {
    'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
    'X-Amz-Credential': `${cfg.accessKeyId}/${scope}`,
    'X-Amz-Date': stamp,
    'X-Amz-Expires': String(Math.min(Math.max(1, expiresIn), maxExpires)),
    'X-Amz-SignedHeaders': names.join(';'),
  };
  const canonicalQuery = Object.keys(query).sort().map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(query[k])}`).join('&');
  const path = bucket ? `/${bucket}/${encodeKey(key)}` : `/${encodeKey(key)}`;
  const canonicalHeaders = names.map((n) => `${n}:${lower[n]}\n`).join('');
  const canonical = [method, path, canonicalQuery, canonicalHeaders, names.join(';'), 'UNSIGNED-PAYLOAD'].join('\n');
  const toSign = ['AWS4-HMAC-SHA256', stamp, scope, sha256hex(canonical)].join('\n');
  const signature = createHmac('sha256', signingKey(cfg.secretAccessKey, date, region, 's3')).update(toSign).digest('hex');
  return `${cfg.endpoint}${path}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}

/** Header-signed server-side request (GET/HEAD/PUT/DELETE). */
async function signedFetch(cfg, { method, bucket, key, body, headers = {}, fetchImpl = fetch, now = new Date() }) {
  const host = new URL(cfg.endpoint).host;
  const stamp = amzDate(now);
  const date = stamp.slice(0, 8);
  const scope = `${date}/auto/s3/aws4_request`;
  const payload = body ? sha256hex(body) : sha256hex('');
  const hdrs = { host, 'x-amz-content-sha256': payload, 'x-amz-date': stamp, ...Object.fromEntries(Object.entries(headers).map(([k, v]) => [k.toLowerCase(), String(v).trim()])) };
  const names = Object.keys(hdrs).sort();
  const path = `/${bucket}/${encodeKey(key)}`;
  const canonical = [method, path, '', names.map((n) => `${n}:${hdrs[n]}\n`).join(''), names.join(';'), payload].join('\n');
  const toSign = ['AWS4-HMAC-SHA256', stamp, scope, sha256hex(canonical)].join('\n');
  const signature = createHmac('sha256', signingKey(cfg.secretAccessKey, date, 'auto', 's3')).update(toSign).digest('hex');
  const { host: _h, ...sendHeaders } = hdrs;
  sendHeaders.authorization = `AWS4-HMAC-SHA256 Credential=${cfg.accessKeyId}/${scope}, SignedHeaders=${names.join(';')}, Signature=${signature}`;
  return fetchImpl(`${cfg.endpoint}${path}`, { method, headers: sendHeaders, body });
}

export async function getObject(cfg, bucket, key, maxBytes, fetchImpl) {
  const res = await signedFetch(cfg, { method: 'GET', bucket, key, fetchImpl });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`R2_GET_${res.status}`);
  const len = Number(res.headers.get('content-length') || 0);
  if (maxBytes && len > maxBytes) throw new Error('R2_OBJECT_TOO_LARGE');
  const buf = Buffer.from(await res.arrayBuffer());
  if (maxBytes && buf.length > maxBytes) throw new Error('R2_OBJECT_TOO_LARGE');
  return buf;
}

export async function putObject(cfg, bucket, key, body, { contentType, cacheControl } = {}, fetchImpl) {
  const headers = { 'content-type': contentType || 'application/octet-stream' };
  if (cacheControl) headers['cache-control'] = cacheControl;
  const res = await signedFetch(cfg, { method: 'PUT', bucket, key, body, headers, fetchImpl });
  if (!res.ok) throw new Error(`R2_PUT_${res.status}`);
}

export async function deleteObject(cfg, bucket, key, fetchImpl) {
  const res = await signedFetch(cfg, { method: 'DELETE', bucket, key, fetchImpl });
  if (!res.ok && res.status !== 404) throw new Error(`R2_DELETE_${res.status}`);
}

/** Purge CDN copies by URL (Cloudflare API; needs a token scoped to Zone > Cache Purge on this zone only). */
export async function purgeUrls(urls, env = process.env, fetchImpl = fetch) {
  if (!urls.length) return { ok: true, skipped: true };
  const zone = env.CLOUDFLARE_ZONE_ID;
  const token = env.CLOUDFLARE_PURGE_TOKEN;
  if (!zone || !token) return { ok: false, reason: 'PURGE_NOT_CONFIGURED' };
  let ok = true;
  for (let i = 0; i < urls.length; i += 30) { // API limit: 30 files per call
    const res = await fetchImpl(`https://api.cloudflare.com/client/v4/zones/${zone}/purge_cache`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ files: urls.slice(i, i + 30) }),
    });
    if (!res.ok) ok = false;
  }
  return ok ? { ok: true } : { ok: false, reason: 'PURGE_FAILED' };
}
