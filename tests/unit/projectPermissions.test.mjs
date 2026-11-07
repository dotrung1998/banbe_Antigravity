import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { canProject, projectIsHost, organizerAccount, memberCaps, PROJECT_ACTIONS, PROJECT_LIMITS, INVITABLE_ROLES } from '../../src/lib/projectPermissions.js';

// Mirrored by apps/ios/BanbeAppTests/ProjectPermissionsTests.swift through the same fixture.
const fx = JSON.parse(readFileSync(new URL('../fixtures/project-permissions.json', import.meta.url), 'utf8'));
const HOSTS = ['owner_account', 'second_account'];
const ALL = [...HOSTS, ...Object.keys(fx.actors).filter(k => fx.actors[k].member?.status === 'active')];
const expand = list => [...new Set(list.flatMap(x => (x === '@hosts' ? HOSTS : x === '@all' ? ALL : [x])))];

/** owner_only answer: the explicit list, else 'allow' with second_account treated as an outsider. */
const ownerOnlyAllow = row => (row.allowOwnerOnly ? expand(row.allowOwnerOnly) : expand(row.allow).filter(a => a !== 'second_account'));

function ctxFor(row, actorKey, hostDef) {
  const a = fx.actors[actorKey];
  return {
    actor: { userId: a.userId, member: a.member && { ...a.member, grantExpiresAt: fx.defaults.grantExpiresAt } },
    organizer: fx.organizer,
    hostDef,
    flags: row.flags ?? fx.defaults.flags,
    now: row.now ?? fx.defaults.now,
    project: row.project ?? fx.defaults.project,
    target: row.target ?? {},
    disputeGrants: row.disputeGrants ?? [],
  };
}

for (const hostDef of ['either', 'owner_only']) {
  for (const row of fx.rows) {
    test(`[${hostDef}] ${row.case}`, () => {
      const allowed = hostDef === 'either' ? expand(row.allow) : ownerOnlyAllow(row);
      for (const actorKey of Object.keys(fx.actors)) {
        assert.equal(canProject(row.action, ctxFor(row, actorKey, hostDef)), allowed.includes(actorKey), `${actorKey} → ${row.action}`);
      }
    });
  }
}

test('every action is covered by at least one row', () => {
  const covered = new Set(fx.rows.map(r => r.action));
  for (const a of PROJECT_ACTIONS) assert.ok(covered.has(a), a);
});

test('the derived owner_only answer only ever drops second_account from project actions', () => {
  for (const row of fx.rows.filter(r => !r.allowOwnerOnly)) {
    assert.ok(!ownerOnlyAllow(row).includes('second_account'), row.case);
  }
});

test('Host definitions: v1 is either organizer account; owner_only is the one-line alternative', () => {
  const org = fx.organizer;
  assert.equal(projectIsHost('u_owner', org), true);
  assert.equal(projectIsHost('u_second', org), true);
  assert.equal(projectIsHost('u_second', org, 'owner_only'), false);
  assert.equal(projectIsHost('u_owner', org, 'owner_only'), true);
  assert.equal(projectIsHost(null, org), false);
  assert.equal(projectIsHost('u_owner', null), false);
  // The money/door check is the existing RPCs' and does not follow the Host definition.
  assert.equal(organizerAccount('u_second', org), true);
});

test('finance always holds both capabilities; others hold only what was granted', () => {
  assert.deepEqual(memberCaps({ role: 'finance', caps: { money: false, checkin: false } }), { money: true, checkin: true });
  assert.deepEqual(memberCaps({ role: 'helper', caps: { checkin: true } }), { money: false, checkin: true });
  assert.deepEqual(memberCaps({ role: 'manager', caps: { money: 'yes' } }), { money: false, checkin: false });
  assert.deepEqual(memberCaps(null), { money: false, checkin: false });
});

test('a manager can only preset lane lead and helper', () => {
  assert.deepEqual(INVITABLE_ROLES.manager, ['lane_lead', 'helper']);
  assert.ok(!INVITABLE_ROLES.manager.includes('finance'));
});

test('shared limits are the planned numbers', () => {
  assert.equal(PROJECT_LIMITS.lanesMax, 10);
  assert.equal(PROJECT_LIMITS.trashMax, 30);
  assert.equal(PROJECT_LIMITS.trashDays, 7);
  assert.equal(PROJECT_LIMITS.channelsMax, 5);
  assert.equal(PROJECT_LIMITS.inviteMaxUses, 20);
  assert.equal(PROJECT_LIMITS.inviteHours, 48);
  assert.equal(PROJECT_LIMITS.grantDays, 7);
  assert.equal(PROJECT_LIMITS.readOnlyDays, 30);
  assert.equal(PROJECT_LIMITS.purgeDays, 90);
  assert.equal(PROJECT_LIMITS.rosMinMinutes, 10);
  assert.deepEqual([PROJECT_LIMITS.postTitleMax, PROJECT_LIMITS.postBodyMax, PROJECT_LIMITS.replyMax, PROJECT_LIMITS.repliesMax], [80, 280, 140, 10]);
});
