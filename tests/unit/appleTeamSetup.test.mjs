import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setTeamInXcconfig, setTeamInAasa } from '../../scripts/apple-team-setup.mjs';

test('xcconfig: sets the team, keeping comments', () => {
  const before = '// set after buying\nDEVELOPMENT_TEAM =\n';
  const after = setTeamInXcconfig(before, 'ABCDE12345');
  assert.match(after, /^\/\/ set after buying$/m);
  assert.match(after, /^DEVELOPMENT_TEAM = ABCDE12345$/m);
  assert.equal(setTeamInXcconfig(after, 'ABCDE12345'), after, 'idempotent');
  assert.equal(setTeamInXcconfig('', 'ABCDE12345'), 'DEVELOPMENT_TEAM = ABCDE12345\n');
});

test('AASA: replaces the placeholder (or an old team) for com.banbe.ios only', () => {
  const aasa = JSON.stringify({ applinks: { apps: [], details: [{ appID: 'TEAMID.com.banbe.ios', paths: ['/u/*'] }, { appID: 'X.other.app', paths: [] }] } });
  const out = JSON.parse(setTeamInAasa(aasa, 'ABCDE12345'));
  assert.equal(out.applinks.details[0].appID, 'ABCDE12345.com.banbe.ios');
  assert.deepEqual(out.applinks.details[0].paths, ['/u/*']);
  assert.equal(out.applinks.details[1].appID, 'X.other.app');
  assert.equal(JSON.parse(setTeamInAasa(JSON.stringify(out), 'ZZZZZ99999')).applinks.details[0].appID, 'ZZZZZ99999.com.banbe.ios');
});
