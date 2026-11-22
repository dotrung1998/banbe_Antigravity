import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {
  normalise,
  sepaySignatureValid,
  sepayApiKeyValid,
} from '../../api/payment-webhook.js';

// Real shape from docs.sepay.vn/tich-hop-webhooks.html
const payload = {
  id: 92704,
  gateway: 'Vietcombank',
  transactionDate: '2024-07-02 11:08:33',
  accountNumber: '1017588888',
  subAccount: '',
  code: 'SEVN63DC8E5C',
  content: 'ART1234 chuyen tien',
  transferType: 'in',
  description: 'NGUYEN VAN A chuyen tien',
  transferAmount: 5000000,
  accumulated: 105000000,
  referenceCode: 'FT24012345678',
};

test('sepay: money in maps to the shared transaction shape', () => {
  const [txn] = normalise('sepay', payload);
  assert.equal(txn.externalId, '92704');
  assert.equal(txn.amountVnd, 5000000);
  // The matcher looks for ART#### in the memo; content is where it lives.
  assert.match(txn.memo, /ART1234/);
  assert.deepEqual(txn.raw, payload);
});

test('sepay: money out is negative so the shared guard ignores it', () => {
  const [txn] = normalise('sepay', { ...payload, transferType: 'out' });
  assert.equal(txn.amountVnd, -5000000);
});

test('sepay: missing id falls back to referenceCode', () => {
  const [txn] = normalise('sepay', { ...payload, id: null });
  assert.equal(txn.externalId, 'FT24012345678');
});

test('sepay: talks about the right field when both texts exist', () => {
  const [txn] = normalise('sepay', { ...payload, content: 'ART9999', description: 'bank text' });
  assert.match(txn.memo, /ART9999/);
  assert.match(txn.memo, /bank text/);
});

test('sepay: HMAC-SHA256 over `${timestamp}.${rawBody}` is accepted', () => {
  const secret = 'whsec_test';
  const rawBody = JSON.stringify(payload);
  const timestamp = 1750000000;
  const signature = `sha256=${crypto.createHmac('sha256', secret)
    .update(`${timestamp}.${rawBody}`)
    .digest('hex')}`;

  assert.equal(sepaySignatureValid({
    signature, timestamp, rawBody, secret, now: timestamp,
  }), true);

  // Same body, signed by the wrong secret.
  assert.equal(sepaySignatureValid({
    signature, timestamp, rawBody, secret: 'other', now: timestamp,
  }), false);

  // Tampered body.
  assert.equal(sepaySignatureValid({
    signature, timestamp, rawBody: rawBody.replace('5000000', '1'), secret, now: timestamp,
  }), false);
});

test('sepay: HMAC rejects stale timestamps (replay window 5 minutes)', () => {
  const secret = 'whsec_test';
  const rawBody = '{}';
  const timestamp = 1750000000;
  const signature = `sha256=${crypto.createHmac('sha256', secret)
    .update(`${timestamp}.${rawBody}`)
    .digest('hex')}`;

  assert.equal(sepaySignatureValid({
    signature, timestamp, rawBody, secret, now: timestamp + 301,
  }), false);
  assert.equal(sepaySignatureValid({
    signature, timestamp, rawBody, secret, now: timestamp + 300,
  }), true);
});

test('sepay: HMAC fails closed without a configured secret', () => {
  assert.equal(sepaySignatureValid({
    signature: 'sha256=abc', timestamp: 1, rawBody: '{}', secret: '',
  }), false);
});

test('sepay: API Key accepts `Authorization: Apikey <key>`', () => {
  assert.equal(sepayApiKeyValid('Apikey sk_live_123', 'sk_live_123'), true);
  assert.equal(sepayApiKeyValid('apikey sk_live_123', 'sk_live_123'), true);
  assert.equal(sepayApiKeyValid('Apikey wrong', 'sk_live_123'), false);
  assert.equal(sepayApiKeyValid('Bearer sk_live_123', 'sk_live_123'), false);
  assert.equal(sepayApiKeyValid('', 'sk_live_123'), false);
  assert.equal(sepayApiKeyValid('Apikey sk_live_123', ''), false);
});
