import test from 'node:test';
import assert from 'node:assert/strict';
import { emailFormatValid, emailIsValid, emailTypoSuggestion } from '../../src/lib/emailRules.js';

test('the reported cases are refused', () => {
  assert.equal(emailIsValid('email@gmail.c'), false);
  assert.equal(emailIsValid('email@gmail.co'), false);
  assert.equal(emailTypoSuggestion('email@gmail.co'), 'email@gmail.com');
  assert.equal(emailTypoSuggestion('email@gmail.c'), 'email@gmail.com');
});

test('a one-letter ending is never a valid format', () => {
  assert.equal(emailFormatValid('ban@example.c'), false);
  assert.equal(emailFormatValid('ban@example'), false);
  assert.equal(emailFormatValid('ban@.com'), false);
  assert.equal(emailFormatValid('ban@exa_mple.com'), false);
  assert.equal(emailFormatValid('.ban@example.com'), false);
  assert.equal(emailFormatValid('ban..x@example.com'), false);
});

test('real addresses pass', () => {
  for (const ok of ['ban@gmail.com', 'Ban.Be+test@Gmail.com', 'a@b.co', 'x@yahoo.co.uk', 'x@hotmail.co.uk', 'x@company.com.vn', 'x@mail.xn--p1ai', 'x@ban-be.app', '  ban@gmail.com  ']) {
    assert.equal(emailIsValid(ok), true, ok);
  }
});

test('provider typos suggest the .com address and keep the local part', () => {
  assert.equal(emailTypoSuggestion('Ban.Be@gmial.com'), 'Ban.Be@gmail.com');
  assert.equal(emailTypoSuggestion('x@gmail.vn'), 'x@gmail.com');
  assert.equal(emailTypoSuggestion('x@yahoo.con'), 'x@yahoo.com');
  assert.equal(emailTypoSuggestion('x@hotmial.cm'), 'x@hotmail.com');
  assert.equal(emailTypoSuggestion('x@yahoo.fr'), null);
  assert.equal(emailTypoSuggestion('x@gmail.com'), null);
  assert.equal(emailTypoSuggestion('x@company.co'), null);
  assert.equal(emailTypoSuggestion('not an email'), null);
});
