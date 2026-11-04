import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseInvite, parseJoinLink, normalizeInviteCode, joinUrl, INVITE_CODE_ALPHABET } from '../../src/lib/projectInviteLink.js';

// Mirrored by apps/ios/BanbeAppTests/ProjectInviteLinkTests.swift through the same fixture.
const fx = JSON.parse(readFileSync(new URL('../fixtures/project-invite-links.json', import.meta.url), 'utf8'));

test('parse join links, tokens and typed codes', () => {
  for (const c of fx.parse) assert.deepEqual(parseInvite(c.in), c.expect, JSON.stringify(c.in));
});

test('the code alphabet has 31 symbols and none that read alike', () => {
  assert.equal(INVITE_CODE_ALPHABET.length, 31);
  assert.equal(new Set(INVITE_CODE_ALPHABET).size, 31);
  for (const ch of '0O1IL') assert.ok(!INVITE_CODE_ALPHABET.includes(ch), ch);
});

test('parseJoinLink only accepts the link forms', () => {
  for (const c of fx.joinLink) assert.deepEqual(parseJoinLink(c.in), c.expect, JSON.stringify(c.in));
});

test('joinUrl builds the shareable link and refuses anything that is not a token', () => {
  assert.equal(joinUrl(fx.joinUrl.token), fx.joinUrl.url);
  assert.deepEqual(parseInvite(joinUrl(fx.joinUrl.token)), { kind: 'token', token: fx.joinUrl.token });
  assert.throws(() => joinUrl('BB-H3QD'));
  assert.throws(() => joinUrl(null));
});

test('normalizeInviteCode rejects non-strings and empty input', () => {
  assert.equal(normalizeInviteCode(null), null);
  assert.equal(normalizeInviteCode(''), null);
  assert.equal(normalizeInviteCode(1234), null);
});
