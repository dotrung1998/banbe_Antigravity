import test from 'node:test';
import assert from 'node:assert/strict';
import { accountTabs, resolveAccountTab } from '../../src/lib/accountTabs.js';

// Same table as apps/ios/BanbeAppTests/AccountTabsTests.swift.
test('hosting off, not admin: no tabs', () => assert.deepEqual(accountTabs({ isAdmin: false, hostMode: false }), []));
test('hosting off, admin: Personal + Admin', () => assert.deepEqual(accountTabs({ isAdmin: true, hostMode: false }), ['personal', 'admin']));
test('hosting on: Host first', () => assert.deepEqual(accountTabs({ isAdmin: false, hostMode: true }), ['host', 'personal']));
test('hosting on, admin: Admin last', () => assert.deepEqual(accountTabs({ isAdmin: true, hostMode: true }), ['host', 'personal', 'admin']));
test('resolve falls back to the first tab', () => {
  assert.equal(resolveAccountTab('admin', ['host', 'personal']), 'host');
  assert.equal(resolveAccountTab('host', ['personal', 'admin']), 'personal');
  assert.equal(resolveAccountTab('host', []), 'personal');
  assert.equal(resolveAccountTab('personal', ['host', 'personal']), 'personal');
});
