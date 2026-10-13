import test from 'node:test';
import assert from 'node:assert/strict';
import { planOrganizerCleanup, applyOrganizerCleanup, removeStoragePrefix, SCRUB_CORE, SCRUB_OPTIONAL, ORGANIZER_BUCKETS } from '../../api/_lib/organizerCleanup.js';

test('plan: other team members -> skip; nothing referencing -> delete; anything referencing -> anonymize', () => {
  assert.equal(planOrganizerCleanup({ events: 0, threads: 0, surveys: 0, otherMembers: 1 }), 'skip');
  assert.equal(planOrganizerCleanup({ events: 5, otherMembers: 2 }), 'skip');
  assert.equal(planOrganizerCleanup({}), 'delete');
  assert.equal(planOrganizerCleanup({ events: 0, threads: 0, surveys: 0, otherMembers: 0 }), 'delete');
  for (const k of ['events', 'threads', 'surveys']) assert.equal(planOrganizerCleanup({ [k]: 1 }), 'anonymize');
});

test('scrub covers identity, contact and payment fields', () => {
  for (const k of ['name', 'about', 'intro_long', 'avatar_path', 'bank_account_no', 'bank_name', 'momo_phone', 'pay_qr_path', 'alert_phone', 'billing_address', 'tax_code', 'social_links']) {
    assert.ok(k in SCRUB_CORE, k);
  }
  assert.notEqual(SCRUB_CORE.name, '');
  for (const k of ['avatar_r2_ref', 'share_card', 'pay_qr_payload']) assert.ok(k in SCRUB_OPTIONAL, k);
});

// In-memory fake of the bits of the Supabase client these helpers use.
function fakeAdmin({ files = {}, failColumns = false } = {}) {
  const log = { removed: [], updated: [], deleted: [] };
  const storage = {
    from: (bucket) => ({
      list: async (prefix, { limit = 100, offset = 0 } = {}) => {
        const entries = new Map();
        for (const path of files[bucket] || []) {
          if (!path.startsWith(prefix + '/')) continue;
          const rest = path.slice(prefix.length + 1);
          const [head, ...tail] = rest.split('/');
          entries.set(head, tail.length ? { name: head, id: null } : { name: head, id: 'x' });
        }
        return { data: [...entries.values()].slice(offset, offset + limit), error: null };
      },
      remove: async (paths) => { log.removed.push(...paths.map(p => `${bucket}:${p}`)); return { error: null }; },
    }),
  };
  const from = (table) => ({
    delete: () => ({ eq: async (c, v) => { log.deleted.push(`${table}:${c}=${v}`); return { error: null }; } }),
    update: (patch) => ({ eq: async (c, v) => {
      if (failColumns && 'avatar_r2_ref' in patch) return { error: { code: '42703', message: 'column "avatar_r2_ref" does not exist' } };
      log.updated.push({ table, patch, where: `${c}=${v}` }); return { error: null };
    } }),
  });
  return { storage, from, log };
}

test('removeStoragePrefix removes files and files inside sub-folders', async () => {
  const admin = fakeAdmin({ files: { 'organizer-photos': ['org1/a.jpg', 'org1/sub/b.jpg', 'org2/c.jpg'] } });
  const n = await removeStoragePrefix(admin, 'organizer-photos', 'org1');
  assert.equal(n, 2);
  assert.deepEqual(admin.log.removed.sort(), ['organizer-photos:org1/a.jpg', 'organizer-photos:org1/sub/b.jpg']);
});

test('apply delete: removes files in every organizer bucket, then the row', async () => {
  const admin = fakeAdmin({ files: { 'organizer-photos': ['org1/a.jpg'], 'pay-qr': ['org1/qr.jpg'] } });
  const r = await applyOrganizerCleanup(admin, 'org1', 'delete');
  assert.equal(r.filesRemoved, 2);
  assert.deepEqual(admin.log.deleted, ['organizers:id=org1']);
  assert.equal(ORGANIZER_BUCKETS.length, 2);
});

test('apply anonymize: removes files and scrubs, never deletes the row; retries without optional columns', async () => {
  const admin = fakeAdmin({ files: { 'organizer-photos': ['org1/a.jpg'] }, failColumns: true });
  const r = await applyOrganizerCleanup(admin, 'org1', 'anonymize');
  assert.equal(admin.log.deleted.length, 0);
  assert.equal(admin.log.updated.length, 1, 'second attempt, without the optional columns, succeeded');
  assert.equal('avatar_r2_ref' in admin.log.updated[0].patch, false);
  assert.equal(admin.log.updated[0].patch.bank_account_no, '');
  assert.equal(r.filesRemoved, 1);
});

test('apply skip is a no-op', async () => {
  const admin = fakeAdmin({ files: { 'organizer-photos': ['org1/a.jpg'] } });
  await applyOrganizerCleanup(admin, 'org1', 'skip');
  assert.deepEqual(admin.log, { removed: [], updated: [], deleted: [] });
});
