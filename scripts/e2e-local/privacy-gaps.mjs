#!/usr/bin/env node
// Verifies the four known privacy gaps against the ISOLATED local stack (never live):
//   1. public draft photos           2. existing public photos after an invite-only change
//   3. expired-story cleanup         4. account deletion leftovers
// Usage (stack + migrations applied via stack.sh):
//   node scripts/e2e-local/privacy-gaps.mjs before   # migration 154 NOT applied: demonstrates the gaps
//   node scripts/e2e-local/privacy-gaps.mjs after    # migration 154 applied: verifies the fixes
// Output is PASS/FAIL per check; 'GAP' lines are expected-to-be-open findings, not failures.
import { createClient } from '@supabase/supabase-js';
import { assertIsolated, LOCAL } from './guard.mjs';
import { makeMediaDb } from '../../api/_lib/mediaDb.js';
import { demoteLegacyInvitePhotos, sweepExpiredStories, sweep } from '../../api/_lib/media.js';

const PHASE = process.argv[2];
if (!['before', 'after'].includes(PHASE)) { console.error('usage: privacy-gaps.mjs before|after'); process.exit(2); }
assertIsolated();
const url = LOCAL.supabase;
const mk = (key) => createClient(url, key, { auth: { persistSession: false } });
const admin = mk(process.env.SUPABASE_SERVICE_ROLE_KEY);
const anon = mk(process.env.VITE_SUPABASE_ANON_KEY);
const out = [];
const check = (name, cond, extra = '') => out.push(`${cond ? 'PASS' : 'FAIL'}  ${name}${extra ? `  [${extra}]` : ''}`);
const gap = (name, extra = '') => out.push(`GAP   ${name}${extra ? `  [${extra}]` : ''}`);
const PW = 'BanbeE2e!Test1234', RUN = Date.now().toString(36);
const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(40)]); // opaque bytes are enough for Storage
const made = { users: [], orgs: [], events: [], stories: [], objects: [] };

async function user(label) {
  const email = `e2e-privacy-${label}-${RUN}@example.test`;
  const { data, error } = await admin.auth.admin.createUser({ email, password: PW, email_confirm: true });
  if (error) throw error;
  await admin.from('account_phone_grandfathered').upsert({ user_id: data.user.id, cohort: 'local-e2e-fixture' });
  const c = mk(process.env.VITE_SUPABASE_ANON_KEY);
  const { data: s, error: se } = await c.auth.signInWithPassword({ email, password: PW }); if (se) throw se;
  made.users.push(data.user.id);
  return { id: data.user.id, email, client: c, token: s.session.access_token };
}
async function org(ownerId, id) { await admin.from('organizers').insert({ id, owner_id: ownerId, name: id, verified: true }); made.orgs.push(id); return id; }
async function event(id, orgId, status, visibility) {
  const { error } = await admin.from('events').insert({ id, key: id, slug: id, organizer_id: orgId, name: id, price_vnd: 1, capacity: 1, seats_remaining: 1, status, approval: 'instant', visibility });
  if (error) throw error; made.events.push(id);
}
const publicUrl = (bucket, path) => `${url}/storage/v1/object/public/${bucket}/${path}`;
const status = async (u) => (await fetch(u)).status;

try {
  const host = await user('host'), stranger = await user('stranger');
  const orgId = await org(host.id, `e2e-priv-org-${RUN}`);
  const DRAFT = `e2e-priv-draft-${RUN}`, LIVE = `e2e-priv-live-${RUN}`, INV = `e2e-priv-inv-${RUN}`;
  await event(DRAFT, orgId, 'draft', 'public'); await event(LIVE, orgId, 'live', 'public'); await event(INV, orgId, 'live', 'invite');

  // ---- host uploads exactly like the current clients do (public bucket, <eventId>/<ts>.jpg) ----
  const up = async (ev, name) => { const p = `${ev}/${name}`; const { error } = await host.client.storage.from('event-photos').upload(p, png, { contentType: 'image/png' }); made.objects.push(['event-photos', p]); return { p, error }; };
  const d = await up(DRAFT, '1.png'), l = await up(LIVE, '1.png'), i = await up(INV, '1.png');
  check('host can upload a draft/live/invite photo through the normal client path', !d.error && !l.error && !i.error, d.error?.message || l.error?.message || i.error?.message);

  // ===== GAP 1: public draft photos =====
  const draftFetch = await status(publicUrl('event-photos', d.p));
  if (draftFetch === 200) gap('GAP 1: a DRAFT event photo is fetchable by anyone who knows its URL (public bucket bypasses RLS)', 'unfixable without moving drafts to a private bucket; see note 28 decision');
  else check('draft photo not publicly fetchable', true);
  const listed = async (client, ev) => { const { data } = await client.storage.from('event-photos').list(ev); return (data || []).length; };
  const anonDraftList = await listed(anon, DRAFT), anonLiveList = await listed(anon, LIVE);
  if (PHASE === 'before') {
    check('BEFORE 154: anon can enumerate a draft event\'s photo path (gap demonstrated)', anonDraftList > 0, `${anonDraftList} object(s)`);
  } else {
    check('AFTER 154: anon can NOT list a draft event\'s photos', anonDraftList === 0, `${anonDraftList}`);
    check('AFTER 154: anon CAN still list a live public event\'s photos', anonLiveList > 0, `${anonLiveList}`);
    check('AFTER 154: public URL display of a live photo unaffected', (await status(publicUrl('event-photos', l.p))) === 200);
    check('AFTER 154: host can still list their own draft folder', (await listed(host.client, DRAFT)) > 0);
    check('AFTER 154: stranger can NOT list the draft folder', (await listed(stranger.client, DRAFT)) === 0);
    const again = await host.client.storage.from('event-photos').upload(`${DRAFT}/2.png`, png, { contentType: 'image/png' }); made.objects.push(['event-photos', `${DRAFT}/2.png`]);
    check('AFTER 154: host can still upload another draft photo', !again.error, again.error?.message);
  }

  // ===== GAP 3 (rpc grant) + story cleanup =====
  const exp = async (orgId2, path, hoursAgo) => {
    const { data, error } = await admin.from('stories').insert({ organizer_id: orgId2, author_id: host.id, media_path: path, media_type: 'image', expires_at: new Date(Date.now() - hoursAgo * 3600_000).toISOString() }).select('id').single();
    if (error) throw error; made.stories.push(data.id); await admin.storage.from('stories').upload(path, png, { contentType: 'image/png', upsert: true }); made.objects.push(['stories', path]); return data.id;
  };
  const s1 = await exp(orgId, `${orgId}/old-${RUN}.png`, 2);
  const rpc = await stranger.client.rpc('cleanup_expired_stories');
  if (PHASE === 'before') check('BEFORE 154: any signed-in stranger can run cleanup_expired_stories() and sees other organizers\' media paths (gap demonstrated)', !rpc.error && (rpc.data || []).some((r) => (r.freed_media_path || '').includes(orgId)), rpc.error?.message || '');
  else check('AFTER 154: stranger can NOT call cleanup_expired_stories()', !!rpc.error && /permission|denied/i.test(rpc.error.message), rpc.error?.message);
  if (PHASE === 'before') { // the rpc above deleted the row but the object was left behind: the orphan the audit predicted
    const orphan = await admin.storage.from('stories').download(`${orgId}/old-${RUN}.png`);
    check('BEFORE 154: the story ROW is gone but its Storage object is still there (orphan, gap demonstrated)', !orphan.error);
  }

  const ctx = (env) => ({ env, db: makeMediaDb(admin), r2: { configured: false } });
  if (PHASE === 'after') {
    const keepId = await exp(orgId, `${orgId}/keep-${RUN}.png`, -5);                 // expires in the future
    const goneId = await exp(orgId, `${orgId}/expired-${RUN}.png`, 3);
    let stats = await sweep(ctx({}));                                                // flag off => nothing touched
    check('sweep with MEDIA_SWEEP_STORIES off removes nothing', stats.storiesRemoved === 0 && !(await admin.storage.from('stories').download(`${orgId}/expired-${RUN}.png`)).error);
    stats = await sweep(ctx({ MEDIA_SWEEP_STORIES: 'on' }));
    const goneObj = await admin.storage.from('stories').download(`${orgId}/expired-${RUN}.png`);
    const goneRow = await admin.from('stories').select('id').eq('id', goneId).maybeSingle();
    const keepRow = await admin.from('stories').select('id').eq('id', keepId).maybeSingle();
    const keepObj = await admin.storage.from('stories').download(`${orgId}/keep-${RUN}.png`);
    check('sweep (flag on) removes the expired story OBJECT and ROW', !!goneObj.error && !goneRow.data, `removed=${stats.storiesRemoved}`);
    check('sweep leaves a not-yet-expired story untouched (row + object)', !!keepRow.data && !keepObj.error);
    check('sweep is idempotent (second run removes 0)', (await sweepExpiredStories(ctx({}))) === 0);
  }

  // ===== GAP 2: existing public photos of an invite-only event =====
  const invUrl = publicUrl('event-photos', i.p);
  const invBefore = await status(invUrl);
  if (PHASE === 'before') {
    check('BEFORE: an INVITE-ONLY event\'s photo is publicly fetchable (gap demonstrated)', invBefore === 200);
  } else {
    await admin.from('event_photos').insert({ event_id: INV, storage_path: `event-photos/${i.p}`, sort_order: 0 });
    await admin.from('events').update({ cover_image: `event-photos/${i.p}` }).eq('id', INV);
    const pubCountBefore = (await admin.storage.from('event-photos').list(INV)).data?.length || 0;
    const privBeforeList = (await admin.storage.from('event-photos-private').list(INV)).data?.length || 0;
    check('AFTER 154 (precondition): the invite photo is still public until the demotion runs', invBefore === 200);
    // flag off => reconcile-style call must not move anything
    const off = await (async () => { const c = ctx({}); return c.env.MEDIA_DEMOTE_LEGACY_INVITE === 'on' ? 'on' : 'off'; })();
    check('demotion is gated: with MEDIA_DEMOTE_LEGACY_INVITE unset nothing runs (sweep)', off === 'off' && (await sweep(ctx({}))).legacyInviteMoved === 0 && (await status(invUrl)) === 200);
    const r = await demoteLegacyInvitePhotos(ctx({ MEDIA_DEMOTE_LEGACY_INVITE: 'on' }), { eventId: INV });
    const row = (await admin.from('event_photos').select('storage_path').eq('event_id', INV).single()).data;
    const ev = (await admin.from('events').select('cover_image').eq('id', INV).single()).data;
    const priv = await admin.storage.from('event-photos-private').download(i.p);
    made.objects.push(['event-photos-private', i.p]);
    check('legacy demotion moved the photo', r.moved === 1, JSON.stringify(r));
    check('public URL no longer serves the invite-only photo', (await status(invUrl)) !== 200, `${await status(invUrl)}`);
    check('bytes now exist in the PRIVATE bucket', !priv.error);
    check('event_photos.storage_path and events.cover_image repointed to the private path', row.storage_path === `event-photos-private/${i.p}` && ev.cover_image === `event-photos-private/${i.p}`);
    check('anon cannot read the private copy', (await status(`${url}/storage/v1/object/public/event-photos-private/${i.p}`)) !== 200 && !!(await anon.storage.from('event-photos-private').download(i.p)).error);
    check('stranger cannot read the private copy', !!(await stranger.client.storage.from('event-photos-private').download(i.p)).error);
    check('host CAN read the private copy', !(await host.client.storage.from('event-photos-private').download(i.p)).error);
    const pubCountAfter = (await admin.storage.from('event-photos').list(INV)).data?.length || 0;
    check('no new public copy was created (public object count dropped, never rose)', pubCountAfter === pubCountBefore - 1, `${pubCountBefore} -> ${pubCountAfter}`);
    check('re-running the demotion is a no-op', (await demoteLegacyInvitePhotos(ctx({ MEDIA_DEMOTE_LEGACY_INVITE: 'on' }), { eventId: INV })).moved === 0);
    void privBeforeList;
  }

  // ===== GAP 4: account deletion =====
  if (PHASE === 'after') {
    const { default: authHandler } = await import('../../api/auth/index.js');
    const owner = await user('delowner');                       // will delete their account
    const solo = await org(owner.id, `e2e-del-solo-${RUN}`);
    const shared = await org(owner.id, `e2e-del-shared-${RUN}`);
    const teammate = await user('teammate');
    await admin.from('organizer_members').insert({ organizer_id: shared, user_id: teammate.id, status: 'accepted', public_role: 'Member', joined_at: new Date().toISOString() });
    await admin.from('organizers').update({ avatar_path: `${solo}/avatar-1.png` }).eq('id', solo);
    await admin.from('organizers').update({ avatar_path: `${shared}/avatar-1.png` }).eq('id', shared);
    for (const o of [solo, shared]) { await admin.storage.from('organizer-photos').upload(`${o}/avatar-1.png`, png, { contentType: 'image/png', upsert: true }); made.objects.push(['organizer-photos', `${o}/avatar-1.png`]); }
    const sStory = await exp(solo, `${solo}/story-${RUN}.png`, -5), shStory = await exp(shared, `${shared}/story-${RUN}.png`, -5);
    const endedEv = `e2e-del-ended-${RUN}`; await event(endedEv, solo, 'ended', 'public');
    await admin.storage.from('event-photos').upload(`${endedEv}/1.png`, png, { contentType: 'image/png' }); made.objects.push(['event-photos', `${endedEv}/1.png`]);
    const res = { code: 0, body: null, headers: {}, setHeader() {}, status(c) { this.code = c; return this; }, json(b) { this.body = b; return this; } };
    await authHandler({ method: 'POST', headers: { authorization: `Bearer ${owner.token}` }, body: { type: 'delete_account' } }, res);
    check('account deletion succeeded', res.code === 200 && res.body?.deleted === true, `${res.code} ${JSON.stringify(res.body)}`);
    const dl = async (b, p) => !(await admin.storage.from(b).download(p)).error;
    check('sole-owned organizer: story object + row removed', !(await dl('stories', `${solo}/story-${RUN}.png`)) && !(await admin.from('stories').select('id').eq('id', sStory).maybeSingle()).data);
    check('sole-owned organizer: profile photo object removed and avatar_path cleared', !(await dl('organizer-photos', `${solo}/avatar-1.png`)) && (await admin.from('organizers').select('avatar_path').eq('id', solo).single()).data.avatar_path === '');
    check('organizer with another accepted team member: story + photo KEPT', (await dl('stories', `${shared}/story-${RUN}.png`)) && (await dl('organizer-photos', `${shared}/avatar-1.png`)) && !!(await admin.from('stories').select('id').eq('id', shStory).maybeSingle()).data);
    check('retained by design: event photos of an ended event are kept', await dl('event-photos', `${endedEv}/1.png`));
    const gone = await admin.auth.admin.getUserById(owner.id);
    check('auth user deleted', !gone.data?.user);
    const steps = (await admin.from('account_deletion_requests').select('steps').eq('user_id', owner.id).maybeSingle()).data?.steps || {};
    check('deletion audit row records the owned_media step', typeof steps.owned_media === 'string' && steps.owned_media.startsWith('ok'), steps.owned_media);
  }
} finally {
  for (const [b, p] of made.objects) await admin.storage.from(b).remove([p]).catch(() => {});
  if (made.stories.length) await admin.from('stories').delete().in('id', made.stories);
  if (made.events.length) { await admin.from('event_photos').delete().in('event_id', made.events); await admin.from('events').delete().in('id', made.events); }
  if (made.orgs.length) { await admin.from('organizer_members').delete().in('organizer_id', made.orgs); await admin.from('organizers').delete().in('id', made.orgs); }
  for (const id of made.users) { await admin.from('account_phone_grandfathered').delete().eq('user_id', id); await admin.auth.admin.deleteUser(id).catch(() => {}); }
  await admin.from('email_registrations').delete().like('email', 'e2e-privacy-%');
}
console.log(out.join('\n'));
process.exit(out.some((l) => l.startsWith('FAIL')) ? 1 : 0);
