// Admin "Project hub demo" (note 76, migration 216): who sees it, what the sample snapshot looks like per role,
// and that leaving resets everything.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { projectDemoAllowed, buildDemoSnapshot, projectDemoState, PROJECT_DEMO_RESET, DEMO_ROLES, DEMO_PROJECT_FLAGS, DEMO_CLOCK } from '../../src/lib/projectDemo.js';
import { FLAG_KEYS, OFF_UNLESS_SET, flagOn } from '../../src/lib/featureFlags.js';
import { FLAG_CATEGORIES } from '../../src/lib/featureFlagCategories.js';
import { screenToPath, pathToRoute, PROJECT_DEMO_PATH } from '../../src/lib/routes.js';
import { projectCan } from '../../src/lib/projectPresentation.js';

const FX = JSON.parse(readFileSync(new URL('../fixtures/project-snapshot.json', import.meta.url), 'utf8')).snapshot;
const ADMIN = '7a1b2c3d-0000-4000-8000-00000000abcd';

test('gate: admin + switch on only; a missing switch is off', () => {
  assert.equal(projectDemoAllowed({ accountType: 'admin', featureFlags: { project_hub_demo: true } }), true);
  assert.equal(projectDemoAllowed({ accountType: 'admin', featureFlags: { project_hub_demo: false } }), false);
  assert.equal(projectDemoAllowed({ accountType: 'admin', featureFlags: {} }), false);
  assert.equal(projectDemoAllowed({ accountType: 'admin' }), false);
  assert.equal(projectDemoAllowed({ accountType: 'goer', featureFlags: { project_hub_demo: true } }), false);
  assert.equal(projectDemoAllowed({ accountType: null, featureFlags: { project_hub_demo: true } }), false);
  assert.equal(projectDemoAllowed(), false);
});

test('the switch is a known, off-unless-set key in the Event projects category', () => {
  assert.ok(FLAG_KEYS.includes('project_hub_demo'));
  assert.ok(OFF_UNLESS_SET.includes('project_hub_demo'));
  assert.equal(flagOn({}, 'project_hub_demo'), false);
  assert.ok(FLAG_CATEGORIES.find(c => c.key === 'projects').flags.includes('project_hub_demo'));
});

test('Host view: the admin stands in for the Host, no member record', () => {
  const s = buildDemoSnapshot(FX, { as: 'host', userId: ADMIN.toUpperCase() });
  assert.equal(s.is_host, true);
  assert.equal(s.me, null);
  assert.equal(s.hosts[0].user_id, ADMIN);
  assert.ok(!JSON.stringify(s).includes('00000000-0000-4000-8000-00000000f1f0'));
});

test('each member view: the admin holds that role, the real Host is someone else', () => {
  const expected = { manager: 'manager', finance: 'finance', lane_lead: 'lane_lead', helper: 'helper' };
  for (const [as, role] of Object.entries(expected)) {
    const s = buildDemoSnapshot(FX, { as, userId: ADMIN });
    assert.equal(s.is_host, false, as);
    assert.equal(s.me.role, role, as);
    assert.equal(s.members.find(m => m.user_id === ADMIN).role, role, as);
    assert.notEqual(s.hosts[0].user_id, ADMIN, as);
    assert.equal(s.hosts[0].display_name, 'Lan', as);
  }
  const fin = buildDemoSnapshot(FX, { as: 'finance', userId: ADMIN });
  assert.equal(fin.me.cap_money, true);
  assert.equal(fin.me.cap_checkin, true);
});

test('inside the demo the project switches count as on, so Finance can do door and money', () => {
  const s = buildDemoSnapshot(FX, { as: 'finance', userId: ADMIN });
  const ctx = { userId: ADMIN, flags: { ...DEMO_PROJECT_FLAGS }, now: new Date(DEMO_CLOCK.before) };
  assert.equal(projectCan(s, 'checkin', {}, ctx), true);
  assert.equal(projectCan(s, 'money.confirm', {}, ctx), true);
  assert.equal(projectCan(s, 'checkin', {}, { ...ctx, flags: {} }), false);
});

test('open state: demo on, clock pinned, every role is offered, unknown role falls back to Host', () => {
  assert.deepEqual(DEMO_ROLES, ['host', 'manager', 'finance', 'lane_lead', 'helper']);
  const a = projectDemoState(FX, { as: 'helper', eventDay: true, userId: ADMIN });
  assert.equal(a.projectDemo, true);
  assert.equal(a.projectDemoAdmin, true);
  assert.equal(a.projectNow, DEMO_CLOCK.eventDay);
  assert.equal(a.screen, 'eventProject');
  assert.equal(a.projectEventId, FX.event.id);
  assert.equal(projectDemoState(FX, { userId: ADMIN }).projectNow, DEMO_CLOCK.before);
  assert.equal(projectDemoState(FX, { as: 'owner', userId: ADMIN }).projectSnapshot.is_host, true);
});

test('reset clears every demo key', () => {
  const opened = projectDemoState(FX, { as: 'finance', userId: ADMIN });
  for (const k of Object.keys(opened)) if (!['screen', 'projectBack'].includes(k)) assert.ok(k in PROJECT_DEMO_RESET, `reset covers ${k}`);
  assert.equal(PROJECT_DEMO_RESET.projectDemo, false);
  assert.equal(PROJECT_DEMO_RESET.projectSnapshot, null);
  assert.equal(PROJECT_DEMO_RESET.projectEventId, '');
});

test('URL: the demo has its own path and a reload lands on the admin list, not a broken real hub', () => {
  const st = projectDemoState(FX, { userId: ADMIN });
  assert.equal(screenToPath(st), PROJECT_DEMO_PATH);
  assert.deepEqual(pathToRoute(PROJECT_DEMO_PATH), { screen: 'accountGroup', params: { accountGroupKey: 'adminReview' } });
  assert.equal(screenToPath({ screen: 'eventProject', projectEventId: 'abc' }), '/e/abc/project');
});
