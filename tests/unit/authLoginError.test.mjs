import test from 'node:test';
import assert from 'node:assert/strict';
import { passwordLoginErrorKind, passwordLoginErrorText } from '../../src/lib/authLoginError.js';

const EN = (_vi, en) => en;

test('each Supabase error code maps to its own reason', () => {
  assert.equal(passwordLoginErrorKind({ code: 'invalid_credentials', status: 400 }), 'credentials');
  assert.equal(passwordLoginErrorKind({ code: 'email_not_confirmed', status: 400 }), 'email_not_confirmed');
  assert.equal(passwordLoginErrorKind({ code: 'captcha_failed', status: 400 }), 'captcha');
  assert.equal(passwordLoginErrorKind({ code: 'user_banned', status: 400 }), 'banned');
  assert.equal(passwordLoginErrorKind({ code: 'over_request_rate_limit', status: 429 }), 'rate_limit');
  assert.equal(passwordLoginErrorKind({ status: 429 }), 'rate_limit');
  assert.equal(passwordLoginErrorKind({ name: 'AuthRetryableFetchError', status: 0 }), 'network');
  assert.equal(passwordLoginErrorKind({ status: 400 }), 'credentials');
  assert.equal(passwordLoginErrorKind({ code: 'unexpected_failure', status: 500 }), 'other');
  assert.equal(passwordLoginErrorKind(null), null);
});

test('a captcha block no longer reads as a wrong password', () => {
  const text = passwordLoginErrorText({ code: 'captcha_failed', status: 400 }, EN);
  assert.notEqual(text, 'Wrong email or password.');
  assert.match(text, /security check/);
});

test('an unknown failure names its code so it can be traced', () => {
  assert.match(passwordLoginErrorText({ code: 'unexpected_failure', status: 500 }, EN), /\(unexpected_failure\)$/);
  assert.match(passwordLoginErrorText({ status: 503 }, EN), /\(HTTP 503\)$/);
});
