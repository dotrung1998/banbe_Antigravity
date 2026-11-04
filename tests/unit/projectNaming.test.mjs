import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Event Project Hub (note 76): the project role is "Manager" / "Quản lý" (identifier `manager`). The policy's
// co-host (Terms A, Privacy B4) is a different thing: the organizer's own second account. So the project code,
// fixtures and note never use that word or its Vietnamese form. Swift files are checked here too, by reading them.
const root = new URL('../../', import.meta.url).pathname;
const FILES = [
  'src/lib/rosLayout.js', 'src/lib/projectPermissions.js', 'src/lib/projectChannels.js', 'src/lib/projectInviteLink.js',
  'src/data/projectLimits.json',
  'tests/fixtures/ros-layout.json', 'tests/fixtures/project-permissions.json', 'tests/fixtures/project-channel-links.json',
  'tests/fixtures/project-invite-links.json',
  'apps/ios/BanbeApp/Lib/RosLayout.swift', 'apps/ios/BanbeApp/Lib/ProjectPermissions.swift', 'apps/ios/BanbeApp/Lib/ProjectChannels.swift',
  'apps/ios/BanbeApp/Lib/ProjectInviteLink.swift', 'apps/ios/BanbeApp/Lib/ProjectLimits.swift',
  'apps/ios/BanbeApp/Lib/ProjectPresentation.swift', 'apps/ios/BanbeApp/State/AppState+Project.swift',
  'apps/ios/BanbeApp/Models/EventProject.swift', 'tests/fixtures/project-snapshot.json', 'tests/fixtures/project-presentation.json',
  'supabase/migrations/20261231000210_210_event_project_core.sql',
];
// Folders later phases add; every file inside is checked once they exist.
const DIRS = ['src/components/project', 'apps/ios/BanbeApp/Views/Project'];
const NOTE_PREFIX = '76-';
const BANNED = /co[-_ ]?host|đồng tổ chức/i;

function walk(dir) {
  const abs = join(root, dir);
  if (!existsSync(abs)) return [];
  return readdirSync(abs).flatMap(n => (statSync(join(abs, n)).isDirectory() ? walk(join(dir, n)) : [join(dir, n)]));
}

test('project code, fixtures and note never call the project role "co-host"', () => {
  const notes = readdirSync(join(root, '.claude/notes')).filter(n => n.startsWith(NOTE_PREFIX)).map(n => `.claude/notes/${n}`);
  const files = [...FILES, ...DIRS.flatMap(walk), ...notes];
  for (const f of files) {
    const text = readFileSync(join(root, f), 'utf8');
    const hit = text.split('\n').findIndex(line => BANNED.test(line));
    assert.equal(hit, -1, `${f}:${hit + 1} uses a banned word for the project role (use "Manager" / "Quản lý")`);
  }
});

test('the banned pattern catches every spelling', () => {
  for (const s of ['Co-host', 'co_host', 'cohost', 'co host', 'Đồng tổ chức', 'CO-HOSTS']) assert.ok(BANNED.test(s), s);
  for (const s of ['Manager', 'Quản lý', 'host', 'localhost']) assert.ok(!BANNED.test(s), s);
});
