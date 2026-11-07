#!/usr/bin/env node
// Grants the phone-OTP TEST exemption (migration 159) to explicitly named
// accounts, stores their contact phone in profiles.phone, and (for named
// accounts) seeds a missing date of birth. See .claude/notes/32-phone-test-exemption.md.
//
// SAFE BY DEFAULT
//   * dry-run unless `--apply --approve <planHash>` is passed. The dry-run prints
//     exact user IDs, PREVIOUS values, proposed writes and the undo steps, plus a
//     plan hash. --apply re-reads every previous value, recomputes the hash and
//     ABORTS if anything changed since the approved dry-run.
//   * server-only: needs SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in the shell
//     environment. Nothing here ships to a client.
//   * never creates a user, never sends SMS, never touches auth.users, never sets
//     profiles.phone_verified or phone_confirmed_at, never edits the legacy
//     account_phone_grandfathered cohort, never overwrites an existing DOB.
//   * writes are compare-and-set against the recorded previous value.
//
// Usage:
//   node --env-file=.env.local scripts/grant-phone-test-exemption.mjs
//   node --env-file=.env.local scripts/grant-phone-test-exemption.mjs --apply --approve <planHash>
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// The ONLY accounts this script will ever touch. `exempt: false` = no exemption
// is wanted (already grandfathered) — only the other fields apply.
const PLAN = [
  { email: 'hannguyenngocbao1211@gmail.com', phone: '+16467212169', exempt: true },
  { email: 'thuhuongg118@gmail.com', phone: '+4917656035288', dob: '1999-08-11', exempt: true },
  { email: 'doqanh0906@gmail.com', dob: '2006-09-16', exempt: false, note: 'legacy-grandfathered; DOB seed only' },
];

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const approved = args.includes('--approve') ? args[args.indexOf('--approve') + 1] : null;

const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) { console.error('Need SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (server-only).'); process.exit(2); }
const sb = createClient(url, key, { auth: { persistSession: false } });
const die = (m) => { console.error('ABORT: ' + m); process.exit(1); };

// ---- E.164 validation (strict; country rules for the two regions in use) ----
function normalizeE164(raw) {
  const s = String(raw).trim();
  if (!/^\+[1-9]\d{7,14}$/.test(s)) return null;
  const d = s.slice(1);
  if (d.startsWith('1')) return /^1[2-9]\d{2}[2-9]\d{6}$/.test(d) ? s : null;      // NANP: 10 digits, area/exchange start 2-9
  if (d.startsWith('49')) return /^49[1-9]\d{9,10}$/.test(d) ? s : null;             // Germany: 10-11 national digits
  return s;
}

async function snapshot(entry) {
  const email = entry.email.toLowerCase();
  const { data: id, error } = await sb.rpc('find_auth_user_by_email', { p_email: email });
  if (error) die(`lookup failed for ${email}: ${error.message}`);
  if (!id) die(`no auth user for ${email} (nothing is ever created)`);
  const { data: au, error: ae } = await sb.auth.admin.getUserById(id);
  if (ae || !au?.user) die(`getUserById failed for ${email}: ${ae?.message}`);
  const [prof, gf, dob, ex] = await Promise.all([
    sb.from('profiles').select('phone,phone_verified,role').eq('id', id).maybeSingle(),
    sb.from('account_phone_grandfathered').select('cohort').eq('user_id', id).maybeSingle(),
    sb.from('user_private_dob').select('date_of_birth,source').eq('user_id', id).maybeSingle(),
    sb.from('account_phone_test_exempt').select('reason').eq('user_id', id).maybeSingle(),
  ]);
  if (!prof.data) die(`no profiles row for ${email}`);
  const exemptTable = ex.error ? (ex.error.code === 'PGRST205' || ex.error.code === '42P01' ? 'missing' : die(ex.error.message)) : 'ok';
  return {
    email, user_id: id,
    auth_phone: au.user.phone || '', auth_phone_confirmed: !!au.user.phone_confirmed_at,
    profile_phone: prof.data.phone || '', profile_phone_verified: prof.data.phone_verified, role: prof.data.role,
    grandfathered: gf.data?.cohort || null,
    dob: dob.data ? { present: true, equals_planned: entry.dob ? dob.data.date_of_birth === entry.dob : null, source: dob.data.source } : { present: false },
    exempt_table: exemptTable, exempt_row: ex.data ? ex.data.reason : null,
  };
}

async function buildPlan() {
  const emails = new Set();
  const rows = [];
  for (const entry of PLAN) {
    if (emails.has(entry.email)) die(`duplicate email in plan: ${entry.email}`);
    emails.add(entry.email);
    const e164 = entry.phone ? normalizeE164(entry.phone) : null;
    if (entry.phone && !e164) die(`invalid E.164 number for ${entry.email}`);
    const prev = await snapshot(entry);
    const writes = [];
    const notes = [];
    if (e164) {
      for (const p of [e164, e164.slice(1)]) {
        const { data } = await sb.from('profiles').select('id').eq('phone', p).neq('id', prev.user_id);
        if (data?.length) die(`profiles.phone collision for ${e164}: ${data.map((r) => r.id).join(',')}`);
      }
      if (prev.profile_phone === e164) notes.push('profiles.phone already equals target — no write');
      else writes.push({ op: 'profiles.update', set: { phone: e164 }, where: { id: prev.user_id, phone: prev.profile_phone } });
    }
    if (entry.exempt) {
      if (prev.grandfathered) notes.push('already grandfathered — exemption not needed');
      else if (prev.exempt_row) notes.push('exemption row already present — no write');
      else writes.push({ op: 'account_phone_test_exempt.insert', row: { user_id: prev.user_id, reason: 'test_account' } });
    }
    if (entry.dob) {
      if (prev.dob.present && prev.dob.equals_planned) notes.push('DOB already stored with the same value — no write');
      else if (prev.dob.present) die(`${entry.email} already has a DIFFERENT DOB — never overwritten`);
      else writes.push({ op: 'user_private_dob.insert', row: { user_id: prev.user_id, source: 'test_seed_159', date_of_birth: '(planned value, not printed)' } });
    }
    rows.push({ entry: { email: entry.email, exempt: entry.exempt, phone: e164 || undefined, hasDob: !!entry.dob }, prev, writes, notes });
  }
  return rows;
}

const hashOf = (rows) => createHash('sha256').update(JSON.stringify(rows.map((r) => ({ e: r.entry, p: { ...r.prev, exempt_table: undefined }, w: r.writes })))).digest('hex').slice(0, 16);

function undoSql(rows) {
  const out = [];
  for (const r of rows) for (const w of r.writes) {
    if (w.op === 'profiles.update') out.push(`update public.profiles set phone = '${r.prev.profile_phone}' where id = '${r.prev.user_id}' and phone = '${w.set.phone}';`);
    if (w.op === 'account_phone_test_exempt.insert') out.push(`delete from public.account_phone_test_exempt where user_id = '${r.prev.user_id}';`);
    if (w.op === 'user_private_dob.insert') out.push(`delete from public.user_private_dob where user_id = '${r.prev.user_id}' and source = 'test_seed_159';`);
  }
  return out;
}

const rows = await buildPlan();
const hash = hashOf(rows);
console.log(JSON.stringify(rows, null, 2));
console.log('\nUNDO (run in order if you need to revert the data writes):\n' + (undoSql(rows).join('\n') || '(no writes planned)'));
console.log('\nplan hash:', hash);
if (rows.some((r) => r.writes.some((w) => w.op.startsWith('account_phone_test_exempt')) && r.prev.exempt_table === 'missing')) {
  console.log('NOTE: migration 159 is not applied yet (account_phone_test_exempt missing) — apply it first; --apply will refuse until then.');
}

if (!APPLY) { console.log('\nDRY RUN — nothing written. To apply: --apply --approve ' + hash); process.exit(0); }

// ---------------------------- apply ----------------------------
if (approved !== hash) die(`plan changed since approval (approved ${approved || 'none'}, now ${hash}) — re-run the dry-run and re-approve`);
if (rows.some((r) => r.prev.exempt_table === 'missing' && r.writes.some((w) => w.op.startsWith('account_phone_test_exempt')))) die('migration 159 not applied');

mkdirSync('.migration-state', { recursive: true });
const undoPath = `.migration-state/phone-test-exemption-undo-${Date.now()}.sql`;
writeFileSync(undoPath, undoSql(rows).join('\n') + '\n');
console.log('undo script saved:', undoPath);

for (const r of rows) for (const w of r.writes) {
  if (w.op === 'profiles.update') {
    const { data, error } = await sb.from('profiles').update(w.set).eq('id', w.where.id).eq('phone', w.where.phone).select('id');
    if (error || data?.length !== 1) die(`profiles update failed/changed for ${r.entry.email}: ${error?.message || 'no row matched previous value'} — run the undo script for earlier writes`);
  } else if (w.op === 'account_phone_test_exempt.insert') {
    const { error } = await sb.from('account_phone_test_exempt').insert(w.row);
    if (error) die(`exempt insert failed for ${r.entry.email}: ${error.message} — run the undo script for earlier writes`);
  } else if (w.op === 'user_private_dob.insert') {
    const plan = PLAN.find((p) => p.email === r.entry.email);
    const { error } = await sb.from('user_private_dob').insert({ user_id: r.prev.user_id, date_of_birth: plan.dob, source: 'test_seed_159' });
    if (error) die(`DOB insert failed for ${r.entry.email}: ${error.message} — run the undo script for earlier writes`);
  }
  console.log('applied', w.op, r.entry.email);
}
console.log('\nDONE. profiles.phone_verified and auth phone were NOT changed; no SMS sent.');
