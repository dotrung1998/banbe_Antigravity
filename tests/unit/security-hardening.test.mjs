import test from 'node:test';
import assert from 'node:assert/strict';
import { getRedirectUrl } from '../../api/_lib/authLookup.js';
import { requestOrigin } from '../../api/_lib/origin.js';
import { renderEmail } from '../../api/_lib/emailTemplate.js';
import { headerSafe } from '../../api/_lib/email.js';
import { renderPaymentDocument } from '../../src/lib/paymentDocument.js';

function withEnv(key, value, fn) {
  const previous = process.env[key];
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
  try {
    return fn();
  } finally {
    if (previous === undefined) delete process.env[key];
    else process.env[key] = previous;
  }
}

test('getRedirectUrl keeps a configured https path and strips the trailing slash', () => {
  withEnv('AUTH_REDIRECT_URL', 'https://www.banbe.app/auth/callback/', () => {
    assert.equal(getRedirectUrl({ headers: {} }), 'https://www.banbe.app/auth/callback');
  });
});

test('getRedirectUrl accepts a normal forwarded https origin', () => {
  withEnv('AUTH_REDIRECT_URL', undefined, () => {
    const url = getRedirectUrl({
      headers: { 'x-forwarded-proto': 'https', 'x-forwarded-host': 'www.banbe.app' },
    });
    assert.equal(url, 'https://www.banbe.app');
  });
});

test('getRedirectUrl refuses a non-http configured scheme', () => {
  withEnv('AUTH_REDIRECT_URL', 'javascript:alert(1)', () => {
    const url = getRedirectUrl({
      headers: { 'x-forwarded-proto': 'https', 'x-forwarded-host': 'www.banbe.app' },
    });
    assert.equal(url, 'https://www.banbe.app');
  });
});

test('getRedirectUrl refuses an unallowlisted forwarded host', () => {
  withEnv('AUTH_REDIRECT_URL', undefined, () => {
    const url = getRedirectUrl({
      headers: { 'x-forwarded-proto': 'http', 'x-forwarded-host': 'evil.example' },
    });
    assert.equal(url, 'https://www.banbe.app');
  });
});

test('requestOrigin keeps a known production host and fixes the scheme', () => {
  withEnv('PUBLIC_SITE_URL', undefined, () => {
    assert.equal(requestOrigin({ headers: { host: 'www.banbe.app' } }), 'https://www.banbe.app');
    assert.equal(requestOrigin({ headers: { host: 'localhost:5173' } }), 'http://localhost:5173');
  });
});

test('requestOrigin never reflects an unknown or malformed Host', () => {
  withEnv('PUBLIC_SITE_URL', undefined, () => {
    for (const host of ['evil.example', 'www.banbe.app.evil.example', 'www.banbe.app"><script>']) {
      assert.equal(requestOrigin({ headers: { host } }), 'https://www.banbe.app');
    }
    assert.equal(requestOrigin({ headers: { 'x-forwarded-host': 'evil.example', host: 'www.banbe.app' } }), 'https://www.banbe.app');
  });
});

test('requestOrigin honours an explicitly configured canonical host', () => {
  withEnv('PUBLIC_SITE_URL', 'https://staging.banbe.app/some/path', () => {
    assert.equal(requestOrigin({ headers: { host: 'staging.banbe.app' } }), 'https://staging.banbe.app');
    assert.equal(requestOrigin({ headers: { host: 'evil.example' } }), 'https://staging.banbe.app');
  });
});

test('renderPaymentDocument escapes the origin used in the wordmark URL', () => {
  const html = renderPaymentDocument({
    kind: 'receipt', number: 'R-1', seller: { name: 'Seller' }, buyer: { name: 'Buyer' },
    event: { name: 'Event' }, lines: [], total_vnd: 0,
  }, { origin: 'https://www.banbe.app/" onerror="alert(1)' });
  assert.ok(!html.includes('onerror="alert(1)"'));
  assert.ok(html.includes('&quot; onerror=&quot;alert(1)'));
});

test('renderEmail escapes a malicious CTA href', () => {
  const html = renderEmail({
    preheader: 'test',
    heading: 'Test',
    paragraphs: ['Body'],
    cta: { label: 'Open', href: 'https://example.test/?a=" onmouseover="alert(1)' },
  });
  assert.ok(!html.includes('onmouseover="alert(1)"'));
  assert.ok(html.includes('&quot;'));
});

test('headerSafe strips CR/LF from a subject', () => {
  assert.equal(headerSafe('Hello\r\nBcc: victim@example.test'), 'Hello Bcc: victim@example.test');
  assert.equal(headerSafe('  Hello\nWorld  '), 'Hello World');
});
