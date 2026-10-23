import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import {
  buildAlertPayload, classifyApnsResponse, readApnsConfig, sendAlertBatch, signApnsToken, APNS_HOSTS,
  missingApnsSettings, dryRunSummary,
} from '../../api/_lib/apnsAlerts.js';
import { drain } from '../../api/_lib/handlers/cronPushDrain.js';
import http2 from 'node:http2';

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const PEM = privateKey.export({ type: 'pkcs8', format: 'pem' });
const CFG = { teamId: 'TEAM123456', keyId: 'KEY1234567', privateKey: PEM, topic: 'com.banbe.ios' };

// Fake http2: answers per (host, token) from a table; records every request.
function fakeConnect(table, log) {
  return (host) => {
    const s = new EventEmitter();
    s.close = () => {};
    s.request = (headers) => {
      const req = new EventEmitter();
      const token = headers[':path'].split('/').pop();
      req.setTimeout = () => {};
      req.close = () => {};
      req.end = (body) => {
        log.push({ host, token, headers, body: JSON.parse(body) });
        const [status, reason] = table[`${host}|${token}`] || [200, null];
        setImmediate(() => {
          req.emit('response', { ':status': status });
          if (reason) req.emit('data', JSON.stringify({ reason }));
          req.emit('end');
        });
      };
      return req;
    };
    return s;
  };
}

const item = (over = {}) => ({
  id: 1, notification_id: '11111111-1111-4111-8111-111111111111', kind: 'payment_confirmed',
  title: 'Payment confirmed', body: 'Your ticket is ready', data: { booking_id: 'b1' }, badge: 3,
  tokens: [{ token: 'aa', environment: 'production', app_id: null }], ...over,
});

test('config needs team, key id and key; bundle id defaults to the app; APNS_ENV can force a gateway', () => {
  assert.equal(readApnsConfig({}), null);
  assert.equal(readApnsConfig({ APNS_TEAM_ID: 'T', APNS_KEY_ID: 'K' }), null);
  assert.deepEqual(missingApnsSettings({ APNS_TEAM_ID: 'T' }), ['APNS_KEY_ID', 'APNS_PRIVATE_KEY']);
  const c = readApnsConfig({ APNS_TEAM_ID: 'T', APNS_KEY_ID: 'K', APNS_PRIVATE_KEY: 'a\\nb' });
  assert.equal(c.privateKey, 'a\nb');
  assert.equal(c.topic, 'com.banbe.ios');
  assert.equal(c.forceEnvironment, null);
  const d = readApnsConfig({ APNS_TEAM_ID: 'T', APNS_KEY_ID: 'K', APNS_PRIVATE_KEY: 'x', APNS_BUNDLE_ID: 'com.x', APNS_TOPIC: 'com.y', APNS_ENV: 'Sandbox' });
  assert.equal(d.topic, 'com.x');
  assert.equal(d.forceEnvironment, 'sandbox');
  assert.equal(readApnsConfig({ APNS_TEAM_ID: 'T', APNS_KEY_ID: 'K', APNS_PRIVATE_KEY: 'x', APNS_ENV: 'staging' }).forceEnvironment, null);
});

test('provider token is a verifiable ES256 JWT with iss = team id', () => {
  const jwt = signApnsToken({ ...CFG, now: 1700000000 });
  const [h, p, s] = jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(h, 'base64url')), { alg: 'ES256', kid: CFG.keyId });
  assert.deepEqual(JSON.parse(Buffer.from(p, 'base64url')), { iss: CFG.teamId, iat: 1700000000 });
  const ok = createVerify('SHA256').update(`${h}.${p}`).verify({ key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(s, 'base64url'));
  assert.ok(ok);
});

test('payload carries alert, badge, thread and the routing fields the app reads', () => {
  const p = buildAlertPayload(item());
  assert.deepEqual(p.aps.alert, { title: 'Payment confirmed', body: 'Your ticket is ready' });
  assert.equal(p.aps.badge, 3);
  assert.equal(p.aps['thread-id'], 'payment_confirmed');
  assert.equal(p.nid, item().notification_id);
  assert.deepEqual(p.data, { booking_id: 'b1' });
  const big = buildAlertPayload(item({ data: { blob: 'x'.repeat(5000) } }));
  assert.deepEqual(big.data, {});
  assert.ok(Buffer.byteLength(JSON.stringify(big)) < 4096);
});

test('APNs answers are classified', () => {
  assert.equal(classifyApnsResponse(200), 'sent');
  assert.equal(classifyApnsResponse(410, 'Unregistered'), 'gone');
  assert.equal(classifyApnsResponse(400, 'BadDeviceToken'), 'wrong_environment_or_gone');
  assert.equal(classifyApnsResponse(400, 'DeviceTokenNotForTopic'), 'gone');
  assert.equal(classifyApnsResponse(429, 'TooManyRequests'), 'retry');
  assert.equal(classifyApnsResponse(503), 'retry');
  assert.equal(classifyApnsResponse(403, 'InvalidProviderToken'), 'failed');
});

test('sends to the token environment with alert headers', async () => {
  const log = [];
  const [r] = await sendAlertBatch([item({ tokens: [{ token: 'aa', environment: 'sandbox', app_id: 'com.banbe.ios' }] })], CFG, { connect: fakeConnect({}, log) });
  assert.equal(r.status, 'sent');
  assert.equal(log.length, 1);
  assert.equal(log[0].host, APNS_HOSTS.sandbox);
  assert.equal(log[0].headers['apns-push-type'], 'alert');
  assert.equal(log[0].headers['apns-topic'], 'com.banbe.ios');
  assert.match(log[0].headers.authorization, /^bearer /);
});

test('BadDeviceToken retries the other environment once and reports the move', async () => {
  const log = [];
  const table = { [`${APNS_HOSTS.production}|aa`]: [400, 'BadDeviceToken'] };
  const [r] = await sendAlertBatch([item()], CFG, { connect: fakeConnect(table, log) });
  assert.equal(r.status, 'sent');
  assert.deepEqual(r.moved_tokens, [{ token: 'aa', environment: 'sandbox' }]);
  assert.deepEqual(log.map((x) => x.host), [APNS_HOSTS.production, APNS_HOSTS.sandbox]);
});

test('gone tokens are reported; an item with only gone tokens is done, not retried', async () => {
  const table = { [`${APNS_HOSTS.production}|aa`]: [410, 'Unregistered'] };
  const [r] = await sendAlertBatch([item()], CFG, { connect: fakeConnect(table, []) });
  assert.equal(r.status, 'sent');
  assert.equal(r.error, 'all_tokens_gone');
  assert.deepEqual(r.gone_tokens, ['aa']);
});

test('a server error leaves the item failed (retried later); one good device is enough', async () => {
  const table = { [`${APNS_HOSTS.production}|aa`]: [503, 'ServiceUnavailable'] };
  const [bad] = await sendAlertBatch([item()], CFG, { connect: fakeConnect(table, []) });
  assert.equal(bad.status, 'failed');
  assert.match(bad.error, /503/);
  const [ok] = await sendAlertBatch([item({ tokens: [{ token: 'aa', environment: 'production' }, { token: 'bb', environment: 'production' }] })], CFG, { connect: fakeConnect(table, []) });
  assert.equal(ok.status, 'sent');
});

test('APNS_ENV forces one gateway and never deletes a token over BadDeviceToken there', async () => {
  const log = [];
  const table = { [`${APNS_HOSTS.sandbox}|aa`]: [400, 'BadDeviceToken'] };
  const [r] = await sendAlertBatch([item()], { ...CFG, forceEnvironment: 'sandbox' }, { connect: fakeConnect(table, log) });
  assert.deepEqual(log.map((x) => x.host), [APNS_HOSTS.sandbox]);
  assert.equal(r.status, 'failed');
  assert.deepEqual(r.gone_tokens, []);
});

// A fake database for the drain: hands out `batches` from push_claim, records push_complete.
function fakeDb(batches) {
  const completed = [];
  return {
    completed,
    rpc: async (name, args) => {
      if (name === 'push_claim') return { data: batches.shift() || [], error: null };
      if (name === 'push_complete') { completed.push(...args.p_results); return { data: { success: true }, error: null }; }
      return { data: null, error: { message: 'unexpected ' + name } };
    },
  };
}

test('dry run without credentials: logs counts only and closes rows as skipped_no_credentials', async () => {
  const db = fakeDb([[item({ id: 7 }), item({ id: 8, kind: 'new_message', tokens: [] })]]);
  const lines = [];
  let sent = 0;
  const totals = await drain(db, null, { missing: ['APNS_KEY_ID'], log: (...a) => lines.push(a.join(' ')), send: async () => { sent += 1; return []; } });
  assert.equal(sent, 0, 'never contacts APNs');
  assert.equal(totals.dry_run, true);
  assert.equal(totals.claimed, 2);
  assert.deepEqual(db.completed.map((r) => [r.id, r.status]), [[7, 'skipped_no_credentials'], [8, 'skipped_no_credentials']]);
  const logged = lines.join('\n');
  assert.match(logged, /DRY RUN \(missing APNS_KEY_ID\)/);
  assert.match(logged, /"payment_confirmed":1/);
  for (const secret of ['Payment confirmed', 'Your ticket is ready', 'booking_id', 'aa', '11111111-1111']) {
    assert.ok(!logged.includes(secret), `dry-run log must not contain ${secret}`);
  }
  assert.deepEqual(dryRunSummary([item(), item({ tokens: [] })]), { pushes: 2, devices: 1, byKind: { payment_confirmed: 2 } });
});

test('switch off: push_claim returns nothing, so the drain does nothing', async () => {
  const db = fakeDb([]);
  const totals = await drain(db, CFG, { send: async () => { throw new Error('must not send'); } });
  assert.equal(totals.claimed, 0);
  assert.equal(db.completed.length, 0);
});

test('mock APNs endpoint (real local HTTP/2 server): payload, headers, cleanup of gone tokens', async () => {
  const seen = [];
  const server = http2.createServer();
  server.on('stream', (stream, headers) => {
    let body = '';
    stream.on('data', (c) => { body += c; });
    stream.on('end', () => {
      const token = headers[':path'].split('/').pop();
      seen.push({ token, headers, body: JSON.parse(body) });
      if (token === 'gone') { stream.respond({ ':status': 410 }); stream.end(JSON.stringify({ reason: 'Unregistered' })); return; }
      stream.respond({ ':status': 200 }); stream.end();
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    const db = fakeDb([[item({ id: 1, tokens: [{ token: 'live', environment: 'production' }, { token: 'gone', environment: 'production' }] })]]);
    const totals = await drain(db, CFG, { send: (items, cfg) => sendAlertBatch(items, cfg, { connect: () => http2.connect(base) }) });
    assert.equal(totals.sent, 1);
    assert.equal(totals.gone_tokens, 1);
    assert.deepEqual(db.completed[0].gone_tokens, ['gone']);
    assert.equal(seen.length, 2);
    const live = seen.find((x) => x.token === 'live');
    assert.equal(live.headers['apns-push-type'], 'alert');
    assert.equal(live.headers['apns-topic'], 'com.banbe.ios');
    assert.equal(live.headers['apns-collapse-id'], item().notification_id);
    assert.deepEqual(live.body.aps.alert, { title: 'Payment confirmed', body: 'Your ticket is ready' });
    assert.equal(live.body.kind, 'payment_confirmed');
  } finally {
    await new Promise((r) => server.close(r));
  }
});
