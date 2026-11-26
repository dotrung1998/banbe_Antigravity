import test from 'node:test';
import assert from 'node:assert/strict';
import { passwordChangeBlocker, currentPasswordErrorText, passwordUpdateErrorText } from '../../src/lib/passwordChange.js';

const T = (vi, en) => en;
const base = { mode: 'password', current: 'OldPass1', code: '', password: 'NewPass22', confirm: 'NewPass22' };

test('Save needs the proof, the rules, a different password and a matching confirm', () => {
  assert.equal(passwordChangeBlocker(base), null);
  assert.equal(passwordChangeBlocker({ ...base, current: '' }), 'proof');
  assert.equal(passwordChangeBlocker({ ...base, password: 'short', confirm: 'short' }), 'rules');
  assert.equal(passwordChangeBlocker({ ...base, current: 'NewPass22' }), 'same');
  assert.equal(passwordChangeBlocker({ ...base, confirm: 'NewPass2' }), 'confirm');
});

test('code mode needs a 6-digit code instead of the current password', () => {
  const code = { ...base, mode: 'code', current: '' };
  assert.equal(passwordChangeBlocker({ ...code, code: '' }), 'proof');
  assert.equal(passwordChangeBlocker({ ...code, code: '12345' }), 'proof');
  assert.equal(passwordChangeBlocker({ ...code, code: ' 123456 ' }), null);
});

test('a wrong current password says so', () => {
  assert.match(currentPasswordErrorText({ code: 'invalid_credentials', status: 400 }, T), /current password is not correct/);
  assert.match(currentPasswordErrorText({ status: 429 }, T), /Too many attempts/);
  assert.match(currentPasswordErrorText({ name: 'AuthRetryableFetchError', status: 0 }, T), /Could not reach/);
});

test('updateUser errors map to their real reason', () => {
  assert.match(passwordUpdateErrorText({ code: 'same_password', status: 422 }, T), /different from the current/);
  assert.match(passwordUpdateErrorText({ code: 'weak_password', status: 422 }, T), /too weak/);
  assert.match(passwordUpdateErrorText({ code: 'reauthentication_needed', status: 400 }, T), /email code/);
  assert.match(passwordUpdateErrorText({ code: 'reauthentication_not_valid', status: 400 }, T), /wrong or has expired/);
  assert.match(passwordUpdateErrorText({ code: 'over_request_rate_limit', status: 429 }, T), /Too many attempts/);
  assert.match(passwordUpdateErrorText({ name: 'AuthRetryableFetchError', status: 0 }, T), /Could not reach/);
  assert.match(passwordUpdateErrorText({ code: 'something_new', status: 500 }, T), /\(something_new\)$/);
  assert.equal(passwordUpdateErrorText(null, T), '');
});
