// Migration 153 guard checks on the isolated local stack: clients cannot write *_r2_ref, normal writes still work, scope/shape
// constraints hold, visibility via RLS. Run: scripts/e2e-local/with-env.sh node scripts/e2e-local/r2-db-guard.mjs
import { createClient } from '@supabase/supabase-js';
import { assertIsolated } from './guard.mjs';
import { SHARED_EMAIL, SHARED_PASSWORD } from './test-accounts.mjs';
assertIsolated();
const url = process.env.SUPABASE_URL;
const admin = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const user = createClient(url, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const other = createClient(url, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const out = []; const ok = (n, c, x = '') => out.push(`${c ? 'PASS' : 'FAIL'}  ${n}${x ? '  [' + x + ']' : ''}`);
const E = SHARED_EMAIL, P = SHARED_PASSWORD;
const { data: s1, error: e1 } = await user.auth.signInWithPassword({ email: E, password: P }); if (e1) throw e1;
const uid = s1.user.id;
// a second ordinary, grandfathered user to prove cross-account behaviour
const E2 = 'r2test-other@example.com';
let { data: cu } = await admin.auth.admin.createUser({ email: E2, password: P, email_confirm: true });
const uid2 = cu?.user?.id || (await admin.from('email_registrations').select('auth_user_id').eq('email', E2).single()).data.auth_user_id;
await admin.from('account_phone_grandfathered').upsert({ user_id: uid2, cohort: 'local-e2e-fixture' });
await other.auth.signInWithPassword({ email: E2, password: P });

const ORG = 'r2test-org', EV = 'r2test-ev', REF_EV = 'r2:ev-r2test-ev/11111111-1111-4111-8111-111111111111.jpg', REF_ORG = 'r2:org-r2test-org/22222222-2222-4222-8222-222222222222.jpg';
try {
  await admin.from('organizers').upsert({ id: ORG, owner_id: uid, name: 'R2 test org', verified: true });
  await admin.from('events').upsert({ id: EV, key: EV, slug: EV, organizer_id: ORG, name: 'r2 test event', price_vnd: 1, capacity: 1, seats_remaining: 1, status: 'live', approval: 'instant', visibility: 'public' });
  const ins = await user.from('event_photos').insert({ event_id: EV, storage_path: 'event-photos/r2test-ev/a.jpg', sort_order: 0 }).select('id').single();
  ok('owner can still insert a normal event_photos row (no r2_ref)', !ins.error, ins.error?.message);
  const rowId = ins.data?.id;

  // client writes of r2_ref are rejected
  let r = await user.from('event_photos').update({ r2_ref: REF_EV }).eq('id', rowId).select();
  ok('owner cannot UPDATE event_photos.r2_ref', !!r.error && /server-managed|42501|permission/i.test(r.error.message + r.error.code), r.error?.message);
  r = await user.from('event_photos').insert({ event_id: EV, storage_path: 'event-photos/r2test-ev/b.jpg', r2_ref: REF_EV, sort_order: 1 });
  ok('owner cannot INSERT event_photos with r2_ref', !!r.error, r.error?.message);
  r = await user.from('events').update({ cover_r2_ref: REF_EV }).eq('id', EV).select();
  ok('owner cannot UPDATE events.cover_r2_ref', !!r.error, r.error?.message);
  r = await user.from('organizers').update({ avatar_r2_ref: REF_ORG }).eq('id', ORG).select();
  ok('owner cannot UPDATE organizers.avatar_r2_ref', !!r.error, r.error?.message);
  r = await other.from('event_photos').update({ r2_ref: REF_EV }).eq('id', rowId).select();
  ok('other account cannot write r2_ref either', !!r.error || (r.data || []).length === 0, r.error?.message || 'no rows');

  // normal writes unaffected (trigger must not break existing flows)
  r = await user.from('events').update({ name: 'r2 test event renamed' }).eq('id', EV).select('name');
  ok('owner can still UPDATE other events columns', !r.error && r.data?.[0]?.name === 'r2 test event renamed', r.error?.message);
  r = await user.from('organizers').update({ about: 'hello' }).eq('id', ORG).select('about');
  ok('owner can still UPDATE other organizers columns', !r.error, r.error?.message);
  r = await user.from('events').insert({ id: 'r2test-ev2', key: 'r2test-ev2', slug: 'r2test-ev2', organizer_id: ORG, name: 'second', price_vnd: 1, capacity: 1, seats_remaining: 1, status: 'draft', approval: 'instant', visibility: 'public' });
  ok('owner can still INSERT a new event (trigger OLD-safe on INSERT)', !r.error, r.error?.message);

  // service role path + scope guard + shape constraint
  r = await admin.from('event_photos').update({ r2_ref: REF_EV }).eq('id', rowId);
  ok('service role CAN set a correctly scoped r2_ref', !r.error, r.error?.message);
  r = await admin.from('event_photos').update({ r2_ref: 'r2:ev-someone-else/11111111-1111-4111-8111-111111111111.jpg' }).eq('id', rowId);
  ok('service role cannot set a ref scoped to a different event', !!r.error, r.error?.message);
  r = await admin.from('event_photos').update({ r2_ref: 'r2:ev-r2test-ev/../../x.jpg' }).eq('id', rowId);
  ok('malformed ref (path traversal) rejected by CHECK', !!r.error, r.error?.message);
  r = await admin.from('organizers').update({ avatar_r2_ref: REF_ORG }).eq('id', ORG);
  ok('service role CAN set organizer avatar ref', !r.error, r.error?.message);

  // visibility: an anonymous reader sees the ref only through events RLS
  const anon = createClient(url, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });
  r = await anon.from('event_photos').select('r2_ref').eq('id', rowId);
  ok('anon can read r2_ref of a PUBLIC live event photo (needed for delivery)', !r.error && r.data?.[0]?.r2_ref === REF_EV, r.error?.message);
  await admin.from('events').update({ visibility: 'invite' }).eq('id', EV);
  r = await anon.from('event_photos').select('r2_ref').eq('id', rowId);
  ok('anon can NOT read r2_ref once the event is invite-only', !r.error && (r.data || []).length === 0, r.error?.message);
  r = await other.from('media_assets').select('id');
  ok('media_assets: other account sees no rows', !r.error && (r.data || []).length === 0, r.error?.message);
  r = await user.from('media_assets').insert({ kind: 'event_photo', scope: 'ev-x', owner_user_id: uid, ext: 'jpg' });
  ok('media_assets: clients cannot insert', !!r.error, r.error?.message);
} finally {
  await admin.from('event_photos').delete().eq('event_id', EV);
  await admin.from('events').delete().in('id', [EV, 'r2test-ev2']);
  await admin.from('organizers').delete().eq('id', ORG);
  if (uid2) { await admin.from('account_phone_grandfathered').delete().eq('user_id', uid2); await admin.auth.admin.deleteUser(uid2); await admin.from('email_registrations').delete().eq('email', E2); }
}
console.log(out.join('\n'));
process.exit(out.some(l => l.startsWith('FAIL')) ? 1 : 0);
