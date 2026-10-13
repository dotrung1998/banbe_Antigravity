#!/usr/bin/env node
// Finds and (optionally) removes data left behind by deleted accounts. Deleting an auth user cascades
// database rows but never Storage objects, and leaves the user's organizer row with no owner but still
// carrying its name, intro, photo, bank/MoMo details and contact info. See api/_lib/organizerCleanup.js
// (the same rules account deletion now applies at delete time).
//
// What it looks at
//   1. `avatars/<userId>/` and `keychain-art/<userId>/` folders whose user no longer has a profile.
//   2. Organizers with NO owner (owner_id and user_id both null) whose id looks generated
//      (`org_` + 8 hex, from ensure_my_organizer / create_event_draft). Seeded demo organizers have
//      readable ids and are never touched. Each gets the same plan as at delete time:
//        delete     nothing references it: remove its files and its row
//        anonymize  events/threads/surveys reference it: remove files, scrub personal/payment fields
//        skip       other accepted team members exist
//
// SAFE BY DEFAULT
//   * dry-run unless `--apply --approve <planHash>` is passed. The dry-run prints every item and a plan
//     hash; --apply recomputes the plan and ABORTS if it differs from the approved one.
//   * server-only: needs SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY. Nothing here ships to a client.
//   * never touches auth.users, bookings, events, chat or payment files.
//   * NOT covered (needs a decision, not a sweep): event photos, chat attachments, payment proofs and
//     documents, stories, and Cloudflare R2 copies of host photos (avatar_r2_ref).
//
// Usage:
//   node --env-file=.env --env-file=.env.local scripts/cleanup-orphaned-media.mjs
//   node --env-file=.env --env-file=.env.local scripts/cleanup-orphaned-media.mjs --apply --approve <planHash>
import { createHash } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import {
  ORGANIZER_BUCKETS, ANONYMIZED_NAME, gatherOrganizerFacts, planOrganizerCleanup, applyOrganizerCleanup, removeStoragePrefix,
} from '../api/_lib/organizerCleanup.js';

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const approved = args.includes('--approve') ? args[args.indexOf('--approve') + 1] : null;
const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) { console.error('Need SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (server-only).'); process.exit(2); }
const sb = createClient(url, key, { auth: { persistSession: false } });
const die = (m) => { console.error('ABORT: ' + m); process.exit(1); };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const GENERATED_ORG_ID = /^org_[0-9a-f]{8}$/;
const USER_BUCKETS = ['avatars', 'keychain-art'];

async function allProfileIds() {
  const ids = new Set();
  for (let from = 0; ; from += 1000) {
    const { data, error } = await sb.from('profiles').select('id').range(from, from + 999);
    if (error) die(`profiles read failed: ${error.message}`);
    for (const r of data) ids.add(r.id);
    if (data.length < 1000) break;
  }
  return ids;
}

async function topLevelFolders(bucket) {
  const names = [];
  for (let offset = 0; ; offset += 100) {
    const { data, error } = await sb.storage.from(bucket).list('', { limit: 100, offset });
    if (error) return { error };
    for (const item of data) if (!item.id) names.push(item.name);
    if (data.length < 100) break;
  }
  return { names };
}

async function countFiles(bucket, prefix) {
  const { data, error } = await sb.storage.from(bucket).list(prefix, { limit: 100 });
  return error ? null : data.length;
}

async function buildPlan() {
  const items = [];
  const profiles = await allProfileIds();

  for (const bucket of USER_BUCKETS) {
    const { names, error } = await topLevelFolders(bucket);
    if (error) { items.push({ kind: 'note', text: `${bucket}: could not list (${error.message})` }); continue; }
    for (const name of names) {
      if (!UUID.test(name) || profiles.has(name)) continue;
      items.push({ kind: 'user-folder', bucket, prefix: name, files: await countFiles(bucket, name) });
    }
  }

  const { data: orgs, error } = await sb.from('organizers').select('id, name, created_at, owner_id, user_id').is('owner_id', null).is('user_id', null);
  if (error) die(`organizers read failed: ${error.message}`);
  for (const org of orgs.filter(o => GENERATED_ORG_ID.test(o.id)).sort((a, b) => a.id.localeCompare(b.id))) {
    const facts = await gatherOrganizerFacts(sb, org.id, null);
    const action = planOrganizerCleanup(facts);
    let files = 0;
    for (const bucket of ORGANIZER_BUCKETS) files += (await countFiles(bucket, org.id)) || 0;
    const alreadyClean = action === 'anonymize' && org.name === ANONYMIZED_NAME && files === 0;
    items.push({ kind: 'organizer', id: org.id, name: org.name, created: org.created_at?.slice(0, 10), facts, action: alreadyClean ? 'already-clean' : action, files });
  }
  return items;
}

const describe = (i) => {
  if (i.kind === 'note') return `NOTE      ${i.text}`;
  if (i.kind === 'user-folder') return `REMOVE    ${i.bucket}/${i.prefix}/  (${i.files ?? '?'} file(s), no matching profile)`;
  const f = i.facts;
  return `${i.action.toUpperCase().padEnd(9)} organizer ${i.id} "${i.name}" created ${i.created}  events=${f.events} threads=${f.threads} surveys=${f.surveys} otherMembers=${f.otherMembers} files=${i.files}`;
};
const actionable = (i) => i.kind === 'user-folder' || (i.kind === 'organizer' && (i.action === 'delete' || i.action === 'anonymize'));
const hashOf = (items) => createHash('sha256').update(JSON.stringify(items.filter(i => i.kind !== 'note').map(i => [i.kind, i.bucket, i.prefix, i.id, i.action]))).digest('hex').slice(0, 16);

const items = await buildPlan();
const hash = hashOf(items);
console.log(`\nOrphaned-media plan (${APPLY ? 'APPLY' : 'dry-run'}) — ${items.filter(actionable).length} actionable item(s)\n`);
for (const i of items) console.log('  ' + describe(i));
console.log(`\nplanHash: ${hash}`);

if (!APPLY) {
  console.log('\nDry run only; nothing was changed. To apply exactly this plan:');
  console.log(`  node --env-file=.env --env-file=.env.local scripts/cleanup-orphaned-media.mjs --apply --approve ${hash}`);
  process.exit(0);
}
if (approved !== hash) die(`--approve ${approved || '(missing)'} does not match the current plan hash ${hash}. Re-run the dry run and approve that.`);

let failures = 0;
for (const i of items.filter(actionable)) {
  try {
    if (i.kind === 'user-folder') {
      const n = await removeStoragePrefix(sb, i.bucket, i.prefix);
      console.log(`  done  ${i.bucket}/${i.prefix}/  removed ${n} file(s)`);
    } else {
      const r = await applyOrganizerCleanup(sb, i.id, i.action);
      console.log(`  done  organizer ${i.id}  ${r.action}, ${r.filesRemoved} file(s)${r.notes.length ? '  NOTES: ' + r.notes.join('; ') : ''}`);
    }
  } catch (error) {
    failures += 1;
    console.error(`  FAIL  ${i.kind} ${i.id || `${i.bucket}/${i.prefix}`}: ${error?.message || error}`);
  }
}
console.log(failures ? `\nFinished with ${failures} failure(s).` : '\nFinished.');
process.exit(failures ? 1 : 0);
