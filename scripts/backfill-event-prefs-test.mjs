#!/usr/bin/env node
// SEPARATE, test-only backfill for migration 162 (event preferences + reservation
// criteria). See .claude/notes/34-onboarding-for-you-criteria.md.
//
// WHAT IT DOES (and nothing else)
//   1. One-time onboarding PROMPT for the named TEST accounts below: sets
//      profile_event_preferences.prompt_requested_at/prompt_batch. It never writes
//      event_preferences, settings, consents, phone/DOB or any onboarding "done"
//      marker, and it never grants an OS permission.
//   2. A small mix of the TEST organizers' own PUBLIC LIVE events: the first two are
//      left Everyone (no write — listed so the mix is explicit), the next two get an
//      interest / goal requirement. Existing bookings/tickets are untouched (criteria
//      are only checked when a NEW reservation is made).
//   It never touches an event owned by anyone else, never auto-backfills "all live
//   events", never creates users, never edits existing tickets.
//
// SAFE BY DEFAULT — same contract as scripts/grant-phone-test-exemption.mjs:
//   * dry-run unless `--apply --approve <planHash>`; the dry-run prints exact
//     user/event IDs, previous values, proposed writes, counts, the rollback SQL
//     and a plan hash. --apply re-reads everything, recomputes the hash and ABORTS
//     if anything changed, if migration 162 is not applied, or if a previous value
//     differs (compare-and-set writes).
//   * server-only: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY from the shell.
//
// Usage:
//   node --env-file=.env.local scripts/backfill-event-prefs-test.mjs
//   node --env-file=.env.local scripts/backfill-event-prefs-test.mjs --apply --approve <planHash>
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// The ONLY accounts this script will ever touch (same named TEST accounts as note 32).
const TEST_EMAILS = [
  'hannguyenngocbao1211@gmail.com',
  'thuhuongg118@gmail.com',
  'doqanh0906@gmail.com',
  'dotrung1998@gmail.com',
];
const BATCH = 'test-backfill-162-1';
const INTEREST_IDS = ['supper', 'fashion', 'gallery', 'music', 'popup'];
const EVERYONE = { version: 1, mode: 'everyone' };

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const approved = args.includes('--approve') ? args[args.indexOf('--approve') + 1] : null;
const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) { console.error('Need SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (server-only).'); process.exit(2); }
const sb = createClient(url, key, { auth: { persistSession: false } });
const die = (m) => { console.error('ABORT: ' + m); process.exit(1); };
const missing = (e) => e && (e.code === 'PGRST205' || e.code === '42P01' || e.code === '42703' || /does not exist|Could not find/i.test(e.message || ''));

async function snapshot() {
  const migration = { prefs_table: 'ok', criteria_column: 'ok' };
  const users = [];
  for (const email of TEST_EMAILS) {
    const { data: id, error } = await sb.rpc('find_auth_user_by_email', { p_email: email });
    if (error) die(`lookup failed for ${email}: ${error.message}`);
    if (!id) die(`no auth user for ${email} (nothing is ever created)`);
    const { data: prof } = await sb.from('profiles').select('display_name,role,created_at').eq('id', id).maybeSingle();
    const pr = await sb.from('profile_event_preferences')
      .select('prompt_requested_at,prompt_batch,settings_onboarded_version,prefs_onboarded_version,event_preferences').eq('user_id', id).maybeSingle();
    let prompt = null;
    if (pr.error) { if (missing(pr.error)) migration.prefs_table = 'missing'; else die(pr.error.message); }
    else prompt = pr.data ? { ...pr.data, has_answers: pr.data.event_preferences != null, event_preferences: undefined } : null;
    users.push({ email, user_id: id, display_name: prof?.display_name ?? null, role: prof?.role ?? null, prompt });
  }

  // TEST organizers' own PUBLIC LIVE events only.
  const ids = users.map((u) => u.user_id);
  const orgs = new Map();
  for (const col of ['owner_id', 'user_id']) {
    const { data, error } = await sb.from('organizers').select('id,name,owner_id,user_id').in(col, ids);
    if (error) die(error.message);
    for (const o of data) orgs.set(o.id, o);
  }
  const events = [];
  if (orgs.size) {
    const { data, error } = await sb.from('events').select('id,name,organizer_id,cat_key,status,visibility,starts_at')
      .in('organizer_id', [...orgs.keys()]).eq('visibility', 'public').eq('status', 'live').order('id', { ascending: true });
    if (error) die(error.message);
    for (const e of data) {
      const { count } = await sb.from('bookings').select('id', { count: 'exact', head: true }).eq('event_id', e.id);
      const cr = await sb.from('events').select('reservation_criteria').eq('id', e.id).maybeSingle();
      let previous = EVERYONE, implicit = false;
      if (cr.error) { if (missing(cr.error)) { migration.criteria_column = 'missing'; implicit = true; } else die(cr.error.message); }
      else previous = cr.data.reservation_criteria;
      events.push({ ...e, organizer_name: orgs.get(e.organizer_id)?.name ?? null, bookings: count ?? 0, previous, previous_is_implicit_default: implicit });
    }
  }
  return { migration, users, events };
}

function buildPlan(snap) {
  const userWrites = [];
  for (const u of snap.users) {
    if (u.prompt?.prompt_requested_at) userWrites.push({ user_id: u.user_id, email: u.email, op: 'none', note: 'already prompted — no write' });
    else if (u.prompt) userWrites.push({ user_id: u.user_id, email: u.email, op: 'update', set: { prompt_requested_at: '<now>', prompt_batch: BATCH }, note: 'row exists (no prompt yet) — only the two prompt columns are set' });
    else userWrites.push({ user_id: u.user_id, email: u.email, op: 'insert', row: { user_id: u.user_id, prompt_requested_at: '<now>', prompt_batch: BATCH } });
  }
  const eventPlan = snap.events.slice(0, 4).map((e, i) => {
    if (i < 2) return { event_id: e.id, name: e.name, organizer: e.organizer_name, bookings: e.bookings, op: 'none', target: EVERYONE, note: 'stays Everyone (no write)' };
    const target = i === 2 && INTEREST_IDS.includes(e.cat_key)
      ? { version: 1, mode: 'declared', interests: { rule: 'any', values: [e.cat_key] } }
      : { version: 1, mode: 'declared', goals: { rule: 'any', values: ['meet_people', 'experiences'] } };
    const same = JSON.stringify(e.previous) === JSON.stringify(target);
    return { event_id: e.id, name: e.name, organizer: e.organizer_name, bookings: e.bookings, op: same ? 'none' : 'update', previous: e.previous, target,
      note: same ? 'already set' : `existing ${e.bookings} booking(s) are NOT affected` };
  });
  return { userWrites, eventPlan };
}

const hashOf = (snap, plan) => createHash('sha256').update(JSON.stringify({
  m: snap.migration, u: plan.userWrites, e: plan.eventPlan.map((e) => ({ id: e.event_id, op: e.op, p: e.previous, t: e.target })),
})).digest('hex').slice(0, 16);

function undoSql(plan) {
  const out = [];
  for (const w of plan.userWrites) {
    if (w.op === 'insert') out.push(`delete from public.profile_event_preferences where user_id = '${w.user_id}' and prompt_batch = '${BATCH}' and event_preferences is null and settings_onboarded_version = 0 and prefs_onboarded_version = 0;`);
    if (w.op === 'update') out.push(`update public.profile_event_preferences set prompt_requested_at = null, prompt_batch = null where user_id = '${w.user_id}' and prompt_batch = '${BATCH}';`);
  }
  for (const e of plan.eventPlan) if (e.op === 'update')
    out.push(`update public.events set reservation_criteria = '${JSON.stringify(e.previous)}'::jsonb where id = '${e.event_id}' and reservation_criteria = '${JSON.stringify(e.target)}'::jsonb;`);
  return out;
}

const snap = await snapshot();
const plan = buildPlan(snap);
const hash = hashOf(snap, plan);
const counts = {
  test_users_found: snap.users.length,
  prompts_to_set: plan.userWrites.filter((w) => w.op !== 'none').length,
  test_org_public_live_events: snap.events.length,
  events_staying_everyone: plan.eventPlan.filter((e) => e.op === 'none').length,
  events_getting_criteria: plan.eventPlan.filter((e) => e.op === 'update').length,
  existing_bookings_on_changed_events: plan.eventPlan.filter((e) => e.op === 'update').reduce((n, e) => n + e.bookings, 0),
};
console.log(JSON.stringify({ migration_162: snap.migration, counts, users: snap.users, user_writes: plan.userWrites, event_plan: plan.eventPlan }, null, 2));
console.log('\nROLLBACK (run in order to revert these data writes):\n' + (undoSql(plan).join('\n') || '(no writes planned)'));
console.log('\nplan hash:', hash);
if (snap.migration.prefs_table === 'missing' || snap.migration.criteria_column === 'missing') {
  console.log('NOTE: migration 162 is NOT applied on this project — apply it first (supabase db push); --apply refuses until then.');
}
if (!APPLY) { console.log('\nDRY RUN — nothing written. To apply: --apply --approve ' + hash); process.exit(0); }

// ---------------------------- apply ----------------------------
if (approved !== hash) die(`plan changed since approval (approved ${approved || 'none'}, now ${hash}) — re-run the dry-run and re-approve`);
if (snap.migration.prefs_table === 'missing' || snap.migration.criteria_column === 'missing') die('migration 162 not applied');
mkdirSync('.migration-state', { recursive: true });
const undoPath = `.migration-state/event-prefs-test-backfill-undo-${Date.now()}.sql`;
writeFileSync(undoPath, undoSql(plan).join('\n') + '\n');
console.log('undo script saved:', undoPath);
const now = new Date().toISOString();
for (const w of plan.userWrites) {
  if (w.op === 'insert') {
    const { error } = await sb.from('profile_event_preferences').insert({ user_id: w.user_id, prompt_requested_at: now, prompt_batch: BATCH });
    if (error) die(`prompt insert failed for ${w.email}: ${error.message} — run the undo script for earlier writes`);
  } else if (w.op === 'update') {
    const { data, error } = await sb.from('profile_event_preferences').update({ prompt_requested_at: now, prompt_batch: BATCH })
      .eq('user_id', w.user_id).is('prompt_requested_at', null).select('user_id');
    if (error || data?.length !== 1) die(`prompt update failed/changed for ${w.email} — run the undo script for earlier writes`);
  }
  if (w.op !== 'none') console.log('applied prompt', w.email);
}
for (const e of plan.eventPlan) {
  if (e.op !== 'update') continue;
  const { data, error } = await sb.from('events').update({ reservation_criteria: e.target }).eq('id', e.event_id).filter('reservation_criteria', 'eq', JSON.stringify(e.previous)).select('id');
  if (error || data?.length !== 1) die(`criteria update failed/changed for ${e.event_id}: ${error?.message || 'previous value differed'} — run the undo script for earlier writes`);
  console.log('applied criteria', e.event_id);
}
console.log('\nDONE. No settings, consents, preferences, tickets or OS permissions were changed.');
