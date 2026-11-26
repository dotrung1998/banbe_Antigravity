import test from 'node:test';
import assert from 'node:assert/strict';
import { emailCheckedAfter, showEmailFormatError } from '../../src/lib/emailFieldCheck.js';

test('typing disarms the check, leaving the field or submitting arms it', () => {
  assert.equal(emailCheckedAfter('type'), false);
  assert.equal(emailCheckedAfter('blur'), true);
  assert.equal(emailCheckedAfter('submit'), true);
});

test('no error while typing, even for a malformed address', () => {
  assert.equal(showEmailFormatError({ email: 'ban@', valid: false, checked: false }), false);
});

test('error after leaving the field with a malformed address', () => {
  assert.equal(showEmailFormatError({ email: 'ban@', valid: false, checked: true }), true);
});

test('an empty field is unfinished, not wrong', () => {
  assert.equal(showEmailFormatError({ email: '   ', valid: false, checked: true }), false);
});

test('a valid address never shows the error', () => {
  assert.equal(showEmailFormatError({ email: 'ban@email.com', valid: true, checked: true }), false);
});
