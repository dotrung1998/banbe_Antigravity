// scripts/migrate-media-to-r2.mjs against the isolated stack + local S3: dry-run, allowlist, copy+verify,
// resume, exclusions, rollback. The script itself is the production script, unmodified.
import { test, expect } from '@playwright/test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { admin, MEDIA, cfg, RUN, makeUser, dropUser, makeOrg, makeEvent, realJpeg, s3Has, sha, setFlags } from './_lib.mjs';

test.describe.configure({ mode: 'serial' });
const ROOT = new URL('../../../', import.meta.url).pathname;
let U, ORG, PUB, DRAFT, INV, state, orig, legacyPath, assetRef;
const run = (args) => {
  const r = spawnSync('node', ['scripts/migrate-media-to-r2.mjs', '--state', state, ...args], { cwd: ROOT, env: process.env, encoding: 'utf8' });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
};

test.beforeAll(async () => {
  state = join(mkdtempSync(join(tmpdir(), 'e2e-mig-')), 'audit.jsonl');
  U = await makeUser('mig'); ORG = await makeOrg(U.id, `e2e-mig-org-${RUN}`);
  PUB = await makeEvent(`e2e-mig-pub-${RUN}`, ORG, 'live', 'public');
  DRAFT = await makeEvent(`e2e-mig-draft-${RUN}`, ORG, 'draft', 'public');
  INV = await makeEvent(`e2e-mig-inv-${RUN}`, ORG, 'live', 'invite');
  orig = realJpeg(1800, 1200);
  legacyPath = `${PUB}/${Date.now()}.jpg`;
  for (const [ev, bucket, path] of [[PUB, 'event-photos', legacyPath], [DRAFT, 'event-photos', `${DRAFT}/${Date.now()}.jpg`], [INV, 'event-photos-private', `${INV}/${Date.now()}.jpg`]]) {
    const up = await admin.storage.from(bucket).upload(path, orig, { contentType: 'image/jpeg' }); expect(up.error).toBeNull();
    await admin.from('event_photos').insert({ event_id: ev, storage_path: `${bucket}/${path}`, sort_order: 0 });
  }
  await admin.from('events').update({ cover_image: `event-photos/${legacyPath}` }).eq('id', PUB);
  await setFlags({ MEDIA_R2_UPLOADS: 'on' });
});
test.afterAll(async () => {
  const evs = [PUB, DRAFT, INV];
  const { data: rows } = await admin.from('event_photos').select('storage_path').in('event_id', evs);
  for (const r of rows || []) { const [b, ...p] = r.storage_path.split('/'); await admin.storage.from(b).remove([p.join('/')]).catch(() => {}); }
  await admin.from('event_photos').delete().in('event_id', evs); await admin.from('media_assets').delete().eq('owner_user_id', U.id);
  await admin.from('events').delete().in('id', evs); await admin.from('organizers').delete().eq('id', ORG); await dropUser(U);
  await admin.from('email_registrations').delete().like('email', 'e2e-r2-mig-%');
});

test('dry-run: lists eligible assets, writes and downloads nothing', async () => {
  const r = run(['--event-ids', `${PUB},${DRAFT},${INV}`]);
  expect(r.code).toBe(0);
  expect(r.out).toContain('DRY-RUN: 1 eligible');
  expect(r.out).toContain(`event-photos/${legacyPath}`);
  expect(r.out).not.toContain(DRAFT + '/'); expect(r.out).not.toContain(INV + '/');
  expect((await admin.from('media_assets').select('id').eq('legacy_path', legacyPath)).data).toHaveLength(0);
  expect((await admin.from('event_photos').select('r2_ref').eq('event_id', PUB).single()).data.r2_ref).toBeNull();
  expect(existsSync(state)).toBe(false);                                                                     // no audit log from a dry run
});

test('--apply refuses to run without an allowlist (or --all)', async () => {
  const r = run(['--apply']);
  expect(r.code).toBe(2); expect(r.out).toContain('--apply needs');
  expect((await admin.from('media_assets').select('id').eq('legacy_path', legacyPath)).data).toHaveLength(0);
});

test('apply: copy + checksum verify, then references; originals untouched; draft and invite-only excluded', async () => {
  const r = run(['--apply', '--event-ids', `${PUB},${DRAFT},${INV}`]);
  expect(r.code, r.out).toBe(0);
  expect(r.out).toContain('"migrated":1'); expect(r.out).toContain('"failed":0');
  const { data: row } = await admin.from('event_photos').select('storage_path, r2_ref').eq('event_id', PUB).single();
  assetRef = row.r2_ref;
  expect(assetRef).toMatch(/^r2:ev-.+\/[0-9a-f-]{36}\.jpg$/);
  expect(row.storage_path).toBe(`event-photos/${legacyPath}`);                                              // legacy column NEVER rewritten
  expect((await admin.from('events').select('cover_r2_ref, cover_image').eq('id', PUB).single()).data).toEqual({ cover_r2_ref: assetRef, cover_image: `event-photos/${legacyPath}` });
  const dl = await admin.storage.from('event-photos').download(legacyPath);
  expect(dl.error).toBeNull();
  expect(await sha(Buffer.from(await dl.data.arrayBuffer()))).toBe(await sha(orig));                       // original byte-identical
  const { data: a } = await admin.from('media_assets').select('*').eq('legacy_path', legacyPath).single();
  expect(a).toMatchObject({ source: 'migration', status: 'published', legacy_bucket: 'event-photos', event_id: PUB });
  expect(a.legacy_sha256).toBe(await sha(orig));
  for (const v of ['thumb', 'card', 'full']) {
    expect(await s3Has(cfg.publicBucket, a.variants[v].key), v).toBe(true);
    const served = Buffer.from(await (await fetch(`${MEDIA}/${a.variants[v].key}`)).arrayBuffer());
    expect(await sha(served), `${v} served bytes match the recorded checksum`).toBe(a.variants[v].sha256);
  }
  expect(a.variants.thumb.bytes).toBeLessThan(a.variants.card.bytes); expect(a.variants.card.bytes).toBeLessThan(a.variants.full.bytes);
  expect(a.variants.full.bytes).toBeLessThan(orig.length);                                                   // smaller than the original
  const kb = (n) => `${(n / 1024).toFixed(0)}KB`;
  test.info().annotations.push({ type: 'bytes', description: `${Math.round(Math.sqrt(1)) && ''}original ${kb(orig.length)} (what every client downloads today) -> thumb ${kb(a.variants.thumb.bytes)} (${(100 - 100 * a.variants.thumb.bytes / orig.length).toFixed(0)}% less), card ${kb(a.variants.card.bytes)} (${(100 - 100 * a.variants.card.bytes / orig.length).toFixed(0)}% less), full ${kb(a.variants.full.bytes)} (${(100 - 100 * a.variants.full.bytes / orig.length).toFixed(0)}% less)` });
  expect(Math.max(a.variants.full.w, a.variants.full.h)).toBeLessThanOrEqual(1600);
  expect((await admin.from('media_assets').select('id').in('event_id', [DRAFT, INV])).data).toHaveLength(0);  // exclusions
  expect((await admin.from('event_photos').select('r2_ref').in('event_id', [DRAFT, INV])).data.every((x) => x.r2_ref === null)).toBe(true);
  const log = readFileSync(state, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  expect(log.some((l) => l.status === 'ok' && l.originalSha256 === a.legacy_sha256)).toBe(true);           // audit trail carries checksums
});

test('resumable: a second apply skips finished work', async () => {
  const r = run(['--apply', '--event-ids', PUB]);
  expect(r.code).toBe(0); expect(r.out).toContain('"migrated":0');
  expect((await admin.from('media_assets').select('id').eq('legacy_path', legacyPath)).data).toHaveLength(1);
});

test('rollback: dry-run changes nothing; --apply drops the R2 pointers, legacy copy stays intact', async () => {
  const dry = run(['--rollback', '--event-ids', PUB]);
  expect(dry.code).toBe(0); expect(dry.out).toContain('would rollback');
  expect((await admin.from('event_photos').select('r2_ref').eq('event_id', PUB).single()).data.r2_ref).toBe(assetRef);
  const r = run(['--rollback', '--apply', '--event-ids', PUB]);
  expect(r.code, r.out).toBe(0); expect(r.out).toContain('1 asset(s) rolled back');
  expect((await admin.from('event_photos').select('r2_ref, storage_path').eq('event_id', PUB).single()).data).toEqual({ r2_ref: null, storage_path: `event-photos/${legacyPath}` });
  expect((await admin.from('events').select('cover_r2_ref').eq('id', PUB).single()).data.cover_r2_ref).toBeNull();
  expect((await admin.from('media_assets').select('status').eq('legacy_path', legacyPath).single()).data.status).toBe('failed');
  expect((await admin.storage.from('event-photos').download(legacyPath)).error).toBeNull();                 // original still there
  expect((await fetch(`${process.env.SUPABASE_URL}/storage/v1/object/public/event-photos/${legacyPath}`)).status).toBe(200);
});
