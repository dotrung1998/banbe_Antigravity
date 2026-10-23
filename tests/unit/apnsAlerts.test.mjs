import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import {
  buildAlertPayload, classifyApnsResponse, readApnsConfig, sendAlertBatch, signApnsToken, APNS_HOSTS,
} from '../../api/_lib/apnsAlerts.js';

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

test('config needs team, key id and key; topic defaults to the app bundle id', () => {
  assert.equal(readApnsConfig({}), null);
  assert.equal(readApnsConfig({ APNS_TEAM_ID: 'T', APNS_KEY_ID: 'K' }), null);
  const c = readApnsConfig({ APNS_TEAM_ID: 'T', APNS_KEY_ID: 'K', APNS_PRIVATE_KEY: 'a\\nb' });
  assert.equal(c.privateKey, 'a\nb');
  assert.equal(c.topic, 'com.banbe.ios');
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
