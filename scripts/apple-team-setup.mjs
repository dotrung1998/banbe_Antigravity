#!/usr/bin/env node
// One command after joining the Apple Developer Program (docs/push-setup.md):
//
//   node scripts/apple-team-setup.mjs --team ABCDE12345            # writes the two files below
//   node scripts/apple-team-setup.mjs --team ABCDE12345 --dry-run  # only shows what would change
//
// 1. apps/ios/Config/Team.xcconfig: DEVELOPMENT_TEAM = <team> (Debug and Release sign with it; both already carry
//    the Push entitlement, and the app only registers while the `push_enabled` switch is on).
// 2. public/.well-known/apple-app-site-association: the "TEAMID" placeholder (or an older team id)
//    becomes <team>, so universal links (/u/*) open the app.
// Local files only: no network, no Apple or Supabase calls. Run `cd apps/ios && xcodegen generate` after.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const TEAM_XCCONFIG = path.join(ROOT, 'apps/ios/Config/Team.xcconfig');
const AASA = path.join(ROOT, 'public/.well-known/apple-app-site-association');
const BUNDLE_ID = 'com.banbe.ios';

export function setTeamInXcconfig(text, team) {
  let out = text;
  const set = (key, value) => {
    const re = new RegExp(`^(${key}\\s*=).*$`, 'm');
    out = re.test(out) ? out.replace(re, `$1 ${value}`) : `${out ? out.replace(/\n?$/, '\n') : ''}${key} = ${value}\n`;
  };
  set('DEVELOPMENT_TEAM', team);
  return out;
}

export function setTeamInAasa(text, team) {
  const json = JSON.parse(text);
  for (const d of json.applinks?.details ?? []) {
    if (typeof d.appID === 'string' && d.appID.endsWith(`.${BUNDLE_ID}`)) d.appID = `${team}.${BUNDLE_ID}`;
  }
  return `${JSON.stringify(json, null, 2)}\n`;
}

function main(argv) {
  const i = argv.indexOf('--team');
  const team = i >= 0 ? String(argv[i + 1] || '').trim().toUpperCase() : '';
  const dry = argv.includes('--dry-run');
  if (!/^[A-Z0-9]{10}$/.test(team)) {
    console.error('Usage: node scripts/apple-team-setup.mjs --team <10-character Apple Team ID> [--dry-run]');
    console.error('Find it at developer.apple.com > Account > Membership details.');
    process.exit(2);
  }
  const base = existsSync(TEAM_XCCONFIG) ? readFileSync(TEAM_XCCONFIG, 'utf8') : '';
  const changes = [
    [TEAM_XCCONFIG, base, setTeamInXcconfig(base, team)],
    [AASA, readFileSync(AASA, 'utf8'), setTeamInAasa(readFileSync(AASA, 'utf8'), team)],
  ];
  for (const [file, before, after] of changes) {
    const rel = path.relative(ROOT, file);
    if (before === after) { console.log(`unchanged  ${rel}`); continue; }
    if (!dry) writeFileSync(file, after);
    console.log(`${dry ? 'would set' : 'updated  '} ${rel}`);
  }
  console.log(`
Next (docs/apple-setup-checklist.md):
  1. cd apps/ios && xcodegen generate
  2. Vercel env: APNS_TEAM_ID=${team}, APNS_KEY_ID, APNS_PRIVATE_KEY (the .p8), APNS_BUNDLE_ID, CRON_SECRET
  3. Supabase SQL editor: the two vault.create_secret(...) lines from the checklist
  4. Deploy the web (the AASA file ships with it), install a Debug build on a real iPhone, turn push_enabled on.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
