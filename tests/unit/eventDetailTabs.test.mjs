import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { visibleTabs, activeTab } from '../../src/lib/eventDetailTabs.js';

// Mirrored by apps/ios/BanbeAppTests/EventDetailTabsTests.swift through tests/fixtures/event-detail-tabs.json (note 75).
const F = JSON.parse(readFileSync(new URL('../fixtures/event-detail-tabs.json', import.meta.url), 'utf8'));

test('tabs only for sections with content', () => {
  for (const c of F.visibleTabs) assert.deepEqual(visibleTabs(c.in), c.out, c.name);
});

test('active tab follows the scroll, and the bottom selects the last tab', () => {
  for (const c of F.activeTab) assert.equal(activeTab(c.tops, c.scrollTop, c.maxScroll, c.lead), c.out, c.name);
});
