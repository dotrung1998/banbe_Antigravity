// MapKit JS authorization token (Apple Maps on the web). MapKit JS needs a short-lived JWT signed with
// the Maps private key (ES256); the key must never reach the browser, so this signs one per request.
//
//   GET /api/mapkit-token  ->  { token }            when MAPKIT_* env is set
//                          ->  503 MAPKIT_NOT_CONFIGURED  otherwise (the web app then keeps OpenStreetMap)
//
// Env (Vercel): MAPKIT_TEAM_ID (Apple Developer Team ID), MAPKIT_KEY_ID (Maps key id),
// MAPKIT_PRIVATE_KEY (the .p8 file's contents; literal "\n" sequences are accepted).
import { createSign } from 'node:crypto';

const TTL_SECONDS = 60 * 60;
const b64u = (v) => Buffer.from(typeof v === 'string' ? v : JSON.stringify(v)).toString('base64url');

export function signMapKitToken({ teamId, keyId, privateKey, origin, now = Math.floor(Date.now() / 1000) }) {
  const header = { alg: 'ES256', kid: keyId, typ: 'JWT' };
  const payload = { iss: teamId, iat: now, exp: now + TTL_SECONDS, ...(origin ? { origin } : {}) };
  const input = `${b64u(header)}.${b64u(payload)}`;
  const signature = createSign('SHA256').update(input).sign({ key: privateKey.replace(/\\n/g, '\n'), dsaEncoding: 'ieee-p1363' });
  return `${input}.${signature.toString('base64url')}`;
}

/** Origin the page is served from (Apple checks the token's `origin` claim against it). */
export function requestOrigin(req) {
  const host = String(req.headers['x-forwarded-host'] || req.headers.host || '').split(',')[0].trim();
  if (!host) return undefined;
  const local = /^(localhost|127\.0\.0\.1)(:\d+)?$/.test(host);
  return `${local ? 'http' : 'https'}://${host}`;
}

export default async function handler(req, res) {
  if (req.method !== 'GET') { res.setHeader('Allow', 'GET'); return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' }); }
  const { MAPKIT_TEAM_ID: teamId, MAPKIT_KEY_ID: keyId, MAPKIT_PRIVATE_KEY: privateKey } = process.env;
  res.setHeader('Cache-Control', 'no-store');
  if (!teamId || !keyId || !privateKey) return res.status(503).json({ error: 'MAPKIT_NOT_CONFIGURED' });
  try {
    return res.status(200).json({ token: signMapKitToken({ teamId, keyId, privateKey, origin: requestOrigin(req) }) });
  } catch (e) {
    console.error('mapkit-token: signing failed:', e.message);
    return res.status(500).json({ error: 'MAPKIT_SIGN_FAILED' });
  }
}
