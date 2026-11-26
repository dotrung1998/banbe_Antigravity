import test from 'node:test';
import assert from 'node:assert/strict';
import { passwordChecks, passwordMeetsRules } from '../../src/lib/passwordRules.js';

const okIds = (pw) => passwordChecks(pw).filter((c) => c.ok).map((c) => c.id);

test('checklist items come in display order with both languages', () => {
  assert.deepEqual(passwordChecks('').map((c) => c.id), ['length', 'lower', 'upper', 'number']);
  for (const c of passwordChecks('')) assert.ok(c.vi && c.en && c.ok === false);
});

test('each rule turns on by itself', () => {
  assert.deepEqual(okIds('abcdefgh'), ['length', 'lower']);
  assert.deepEqual(okIds('A'), ['upper']);
  assert.deepEqual(okIds('7'), ['number']);
  assert.deepEqual(okIds('Đường1'), ['lower', 'upper', 'number']);
});

test('only a password meeting every rule passes', () => {
  assert.equal(passwordMeetsRules('Banbe2026'), true);
  assert.equal(passwordMeetsRules('banbe2026'), false);
  assert.equal(passwordMeetsRules('Banbe202'), true);
  assert.equal(passwordMeetsRules('Bb1'), false);
  assert.equal(passwordMeetsRules(undefined), false);
});
