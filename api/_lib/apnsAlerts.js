import http2 from 'node:http2';
import { createSign } from 'node:crypto';

// User-facing APNs alerts (migration 194, docs/push-setup.md). Token-based auth: ONE .p8 APNs Auth
// Key signs a short-lived ES256 JWT, valid for sandbox AND production. (Wallet pass updates are a
// different thing — certificate-based, see apns.js.)
//
// Env (Vercel): APNS_TEAM_ID, APNS_KEY_ID, APNS_PRIVATE_KEY (.p8 contents; literal "\n" accepted),
// optional APNS_TOPIC (default com.banbe.ios — a token's own app_id wins when present).

export const APNS_HOSTS = {
  production: 'https://api.push.apple.com',
  sandbox: 'https://api.sandbox.push.apple.com',
};

export function readApnsConfig(env = process.env) {
  const teamId = (env.APNS_TEAM_ID || '').trim();
  const keyId = (env.APNS_KEY_ID || '').trim();
  const privateKey = (env.APNS_PRIVATE_KEY || '').replace(/\\n/g, '\n').trim();
  if (!teamId || !keyId || !privateKey) return null;
  return { teamId, keyId, privateKey, topic: (env.APNS_TOPIC || 'com.banbe.ios').trim() };
}

const b64u = (v) => Buffer.from(typeof v === 'string' ? v : JSON.stringify(v)).toString('base64url');

/** Provider token. Apple accepts one for up to an hour and rejects refreshing more than every 20 min. */
export function signApnsToken({ teamId, keyId, privateKey, now = Math.floor(Date.now() / 1000) }) {
  const input = `${b64u({ alg: 'ES256', kid: keyId })}.${b64u({ iss: teamId, iat: now })}`;
  const sig = createSign('SHA256').update(input).sign({ key: privateKey, dsaEncoding: 'ieee-p1363' });
  return `${input}.${sig.toString('base64url')}`;
}

let cachedToken = null;
function providerToken(cfg) {
  const now = Math.floor(Date.now() / 1000);
  if (!cachedToken || cachedToken.keyId !== cfg.keyId || now - cachedToken.iat > 40 * 60) {
    cachedToken = { keyId: cfg.keyId, iat: now, jwt: signApnsToken({ ...cfg, now }) };
  }
  return cachedToken.jwt;
}

const clip = (s, n) => (String(s ?? '').length > n ? String(s).slice(0, n - 1) + '…' : String(s ?? ''));

/** One outbox item (push_claim) -> the APNs JSON body. The app routes taps by nid/kind/data. */
export function buildAlertPayload(item) {
  const payload = {
    aps: {
      alert: { title: clip(item.title, 120), body: clip(item.body, 400) },
      sound: 'default',
      'thread-id': String(item.kind || 'banbe'),
      ...(Number.isInteger(item.badge) && item.badge >= 0 ? { badge: item.badge } : {}),
    },
    nid: item.notification_id,
    kind: item.kind,
    data: item.data && typeof item.data === 'object' ? item.data : {},
  };
  // APNs refuses bodies over 4 KB: drop the routing data before ever dropping the alert itself.
  if (Buffer.byteLength(JSON.stringify(payload)) > 3800) payload.data = {};
  return payload;
}

/** How to treat an APNs answer for one token. */
export function classifyApnsResponse(status, reason) {
  if (status === 200) return 'sent';
  if (status === 410 || reason === 'Unregistered') return 'gone';
  if (reason === 'BadDeviceToken') return 'wrong_environment_or_gone';
  if (reason === 'DeviceTokenNotForTopic' || reason === 'TopicDisallowed') return 'gone';
  if (status === 429 || status >= 500) return 'retry';
  return 'failed';
}

function sendOne(session, { token, topic, jwt, body, collapseId }) {
  return new Promise((resolve) => {
    const req = session.request({
      ':method': 'POST',
      ':path': `/3/device/${token}`,
      authorization: `bearer ${jwt}`,
      'apns-topic': topic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'apns-expiration': String(Math.floor(Date.now() / 1000) + 3600),
      ...(collapseId ? { 'apns-collapse-id': collapseId } : {}),
    });
    let status = 0; let raw = '';
    req.on('response', (h) => { status = h[':status']; });
    req.on('data', (c) => { raw += c; });
    req.on('end', () => {
      let reason = null;
      try { reason = raw ? JSON.parse(raw).reason : null; } catch { /* empty */ }
      resolve({ status, reason });
    });
    req.on('error', (e) => resolve({ status: 0, reason: e.code || 'NETWORK' }));
    req.setTimeout(8000, () => { req.close(); });
    req.end(JSON.stringify(body));
  });
}

/**
 * Sends a batch of claimed items. Returns push_complete() input:
 * [{ id, status: 'sent'|'failed', error?, gone_tokens: [], moved_tokens: [{token, environment}] }].
 * An item counts as sent when at least one of the recipient's devices accepted it.
 */
export async function sendAlertBatch(items, cfg, { connect = (host) => http2.connect(host) } = {}) {
  const jwt = providerToken(cfg);
  const sessions = {};
  const sessionFor = (env) => {
    if (!sessions[env]) { sessions[env] = connect(APNS_HOSTS[env]); sessions[env].on('error', () => {}); }
    return sessions[env];
  };
  const results = [];
  try {
    for (const item of items) {
      const body = buildAlertPayload(item);
      const out = { id: item.id, status: 'failed', gone_tokens: [], moved_tokens: [] };
      const errors = [];
      if (!item.tokens?.length) { out.status = 'sent'; out.error = 'no_tokens'; results.push(out); continue; }
      for (const t of item.tokens) {
        const env = t.environment === 'sandbox' ? 'sandbox' : 'production';
        const topic = t.app_id || cfg.topic;
        let r = await sendOne(sessionFor(env), { token: t.token, topic, jwt, body, collapseId: item.notification_id });
        let verdict = classifyApnsResponse(r.status, r.reason);
        if (verdict === 'wrong_environment_or_gone') {
          // A token is only valid in the environment that issued it: try the other one once.
          const other = env === 'sandbox' ? 'production' : 'sandbox';
          r = await sendOne(sessionFor(other), { token: t.token, topic, jwt, body, collapseId: item.notification_id });
          verdict = classifyApnsResponse(r.status, r.reason);
          if (verdict === 'sent') out.moved_tokens.push({ token: t.token, environment: other });
          else if (verdict === 'wrong_environment_or_gone') verdict = 'gone';
        }
        if (verdict === 'sent') out.status = 'sent';
        else if (verdict === 'gone') out.gone_tokens.push(t.token);
        else errors.push(`${r.status}:${r.reason || ''}`);
      }
      if (out.status !== 'sent' && !errors.length) { out.status = 'sent'; out.error = 'all_tokens_gone'; }
      else if (errors.length) out.error = errors.join(',').slice(0, 300);
      results.push(out);
    }
  } finally {
    for (const s of Object.values(sessions)) { try { s.close(); } catch { /* ignore */ } }
  }
  return results;
}
