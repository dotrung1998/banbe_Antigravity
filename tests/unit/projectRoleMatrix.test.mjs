import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { canProject } from '../../src/lib/projectPermissions.js';
import { MATRIX_COLUMNS, MATRIX_ROWS } from '../../src/lib/projectRoleMatrix.js';

// Every cell of "Who can do what" against the rules (same check as apps/ios/BanbeAppTests/ProjectTeamTopicsTests.swift).
const HOST = 'host-1', ME = 'me-2', OWN = 'lane-own', OTHER = 'lane-other';
const DELEGATION = { project_delegate_checkin: true, project_delegate_payments: true, project_delegate_refunds: true };

function ctx(column, { caps = false, flags = {}, target = {} } = {}) {
  const base = { organizer: { ownerId: HOST, userId: null }, flags: { event_project_hub: true, ...flags }, target };
  if (column === 'host') return { ...base, actor: { userId: HOST } };
  return { ...base, actor: { userId: ME, member: { role: column, laneId: column === 'lane_lead' ? OWN : null, caps: { money: caps, checkin: caps }, status: 'active' } } };
}

function target(probe, lane, column) {
  const uid = column === 'host' ? HOST : ME;
  switch (probe) {
    case 'laneScoped': return { laneId: lane };
    case 'ownTask': return { laneId: lane, assigneeId: uid };
    case 'ownQuietPost': return { laneId: lane, authorId: uid, type: 'question', state: 'open', quiet: true };
    case 'roleHelper': return { role: 'helper' };
    default: return {};
  }
}

test('the iOS and web tables have the same rows', () => {
  const swift = readFileSync(new URL('../../apps/ios/BanbeApp/Lib/ProjectRoleMatrix.swift', import.meta.url), 'utf8');
  const ids = [...swift.matchAll(/Row\(id: "([^"]+)"/g)].map(m => m[1]);
  assert.deepEqual(ids, MATRIX_ROWS.map(r => r.id));
});

test('every matrix cell matches canProject', () => {
  for (const row of MATRIX_ROWS) {
    assert.equal(row.cells.length, MATRIX_COLUMNS.length, row.id);
    if (!row.action) continue;
    MATRIX_COLUMNS.forEach((column, i) => {
      const cell = row.cells[i], name = `${row.id} / ${column}`;
      const can = (lane, o = {}) => canProject(row.action, ctx(column, { ...o, target: target(row.probe, lane, column) }));
      if (cell === 'yes') { assert.ok(can(OWN, { flags: DELEGATION }) && can(OTHER, { flags: DELEGATION }), name); }
      if (cell === 'no') { assert.ok(!can(OWN, { flags: DELEGATION }) && !can(OTHER, { flags: DELEGATION }), name); }
      if (cell === 'lane') { assert.ok(can(OWN) && !can(OTHER), name); }
      if (cell === 'grant') { assert.ok(!can(null, { flags: DELEGATION }) && can(null, { caps: true, flags: DELEGATION }), name); }
      if (cell === 'propose') { assert.ok(!can(null) && canProject('change.propose', ctx(column)), name); }
    });
  }
});
