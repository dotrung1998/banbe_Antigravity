import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { detectChannelPlatform, validateChannel, sanitizeChannels, orderedChannels, CHANNEL_PLATFORMS, CHANNEL_NAMES } from '../../src/lib/projectChannels.js';

// Mirrored by apps/ios/BanbeAppTests/ProjectChannelsTests.swift through the same fixture.
const fx = JSON.parse(readFileSync(new URL('../fixtures/project-channel-links.json', import.meta.url), 'utf8'));

test('platform detection', () => {
  for (const c of fx.detect) assert.equal(detectChannelPlatform(c.url), c.platform, c.url);
});

for (const c of fx.channels) {
  test(`channel: ${c.case}`, () => {
    const r = validateChannel(c.in);
    assert.equal(r.ok, c.ok);
    if (c.ok) assert.deepEqual(r.channel, c.out);
    else assert.equal(r.error, c.error);
  });
}

for (const c of fx.lists) {
  test(`channel list: ${c.case}`, () => {
    const r = sanitizeChannels(c.in);
    assert.equal(r.ok, c.ok);
    if (!c.ok) {
      assert.equal(r.error, c.error);
      if ('index' in c) assert.equal(r.index, c.index);
    }
  });
}

test('the over-long URL vector really is over 300 characters', () => {
  const long = fx.channels.find(c => c.case.startsWith('URL over')).in.url;
  assert.ok(long.length > 300);
});

test('every platform has a display name entry; only link is left to the caller', () => {
  assert.deepEqual(Object.keys(CHANNEL_NAMES).sort(), Object.keys(CHANNEL_PLATFORMS).sort());
  for (const [p, name] of Object.entries(CHANNEL_NAMES)) assert.equal(name === null, p === 'link', p);
});

test('the starred channel is listed first, others keep their order', () => {
  const list = [{ url: 'a' }, { url: 'b', primary: true }, { url: 'c' }];
  assert.deepEqual(orderedChannels(list).map(c => c.url), ['b', 'a', 'c']);
  assert.deepEqual(orderedChannels(null), []);
});
