import test from 'node:test';
import assert from 'node:assert/strict';
import { signReauthProof, verifyReauthProof, REAUTH_PROOF_TTL_MS } from '../../api/_lib/reauthProof.js';

const KEY = 'service-role-secret';
const UID = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

test('a fresh proof verifies for its own user', () => {
  assert.equal(verifyReauthProof(signReauthProof(UID, KEY, 1000), UID, KEY, 1000 + 5000), true);
});

test('a proof for another user, a wrong key, or a tampered signature is rejected', () => {
  const p = signReauthProof(UID, KEY, 1000);
  assert.equal(verifyReauthProof(p, '00000000-0000-0000-0000-000000000000', KEY, 2000), false);
  assert.equal(verifyReauthProof(p, UID, 'other-key', 2000), false);
  assert.equal(verifyReauthProof(p.slice(0, -2) + '00', UID, KEY, 2000), false);
});

test('an expired proof is rejected', () => {
  const p = signReauthProof(UID, KEY, 1000);
  assert.equal(verifyReauthProof(p, UID, KEY, 1000 + REAUTH_PROOF_TTL_MS + 1), false);
});

test('missing or malformed proofs are rejected', () => {
  for (const bad of [undefined, null, '', 'a.b', 'a.b.c.d', 42]) assert.equal(verifyReauthProof(bad, UID, KEY), false);
  assert.equal(signReauthProof('', KEY), '');
  assert.equal(signReauthProof(UID, ''), '');
});
