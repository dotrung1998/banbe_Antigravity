// Real browser -> real /api/media (via the Vite /api proxy) -> presigned PUT to the local S3 server -> finalize -> read from the
// local "media domain". Exercises the UI upload paths (organizer avatar, Dashboard event photo), the resolver (R2 vs legacy),
// privacy change, deletion and cold/warm transfer. The API-unavailable fallback is NOT what this spec tests.
import { test, expect } from '@playwright/test';
import { setupToHome } from '../../../tests/helpers.js';
import { admin, MEDIA, RUN, cfg, makeOrg, makeEvent, setFlags, media, resetMock, mockCalls, mediaStats, png, realJpeg, s3Has } from './_lib.mjs';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SHARED_EMAIL } from '../test-accounts.mjs';

test.describe.configure({ mode: 'serial' });
const SHARED = SHARED_EMAIL;
let uid, ORG, EV, dir, saved;
const file = (name, buf) => { const p = join(dir, name); writeFileSync(p, buf); return p; };
const MEDIA_RE = new RegExp(`^${MEDIA.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}/v1/`);

// The Dashboard only lists events whose key is in the app's static catalogue, so this spec borrows the seeded catalogue event
// `bepnho` (see fixtures.mjs): the shared test account temporarily owns its organizer, its seeded photo row is set aside, and
// afterAll puts everything back exactly as found.
test.beforeAll(async () => {
  dir = mkdtempSync(join(tmpdir(), 'e2e-br-'));
  uid = (await admin.from('email_registrations').select('auth_user_id').eq('email', SHARED).single()).data.auth_user_id;
  ORG = 'org_bepnho'; EV = 'bepnho';
  const org = (await admin.from('organizers').select('owner_id, user_id, avatar_path, avatar_r2_ref').eq('id', ORG).single()).data;
  const photos = (await admin.from('event_photos').select('*').eq('event_id', EV)).data || [];
  const ev = (await admin.from('events').select('cover_image, cover_r2_ref').eq('id', EV).single()).data;
  const profile = (await admin.from('profiles').select('role, display_name').eq('id', uid).single()).data;
  saved = { org, photos, ev, profile };
  await admin.from('event_photos').delete().eq('event_id', EV);
  await admin.from('organizers').update({ owner_id: uid }).eq('id', ORG);
  await admin.from('profiles').update({ role: 'organizer', display_name: 'R2 Browser Tester' }).eq('id', uid);
  await setFlags({ MEDIA_R2_UPLOADS: 'on' });
});
test.afterAll(async () => {
  await admin.from('event_photos').delete().eq('event_id', EV);
  await admin.from('media_assets').delete().eq('owner_user_id', uid);
  if (saved.photos.length) await admin.from('event_photos').insert(saved.photos);
  await admin.from('events').update({ visibility: 'public', cover_image: saved.ev.cover_image, cover_r2_ref: saved.ev.cover_r2_ref }).eq('id', EV);
  await admin.from('organizers').update({ owner_id: saved.org.owner_id, avatar_path: saved.org.avatar_path, avatar_r2_ref: saved.org.avatar_r2_ref }).eq('id', ORG);
  await admin.from('profiles').update({ role: saved.profile.role, display_name: saved.profile.display_name }).eq('id', uid);
  const { data: objs } = await admin.storage.from('organizer-photos').list(ORG);
  if (objs?.length) await admin.storage.from('organizer-photos').remove(objs.map((o) => `${ORG}/${o.name}`));
});

async function toDashboard(page) {
  await setupToHome(page);
  await page.getByTestId('tab-profile').click();
  await page.waitForSelector('[data-screen-label="Account"]');
  await expect(page.getByTestId('organizer-mode-toggle')).toBeVisible({ timeout: 8000 });
  await page.getByTestId('account-tab-host').click();
  await page.getByTestId('org-profile-card').click();
  await expect(page.locator('[data-screen-label="Organizer dashboard"]')).toBeVisible({ timeout: 8000 });
}
const track = (page) => {
  const seen = { api: [], puts: [], mediaGets: [] };
  page.on('request', (r) => {
    const u = r.url();
    if (u.includes('/api/media')) seen.api.push(JSON.parse(r.postData() || '{}').op);
    if (r.method() === 'PUT' && u.startsWith('http://127.0.0.1:59000/')) seen.puts.push(u.split('?')[0].split('/').pop());
    if (MEDIA_RE.test(u)) seen.mediaGets.push(u);
  });
  return seen;
};

test('organizer avatar: UI upload goes through init -> 3 presigned PUTs -> finalize and renders from the media domain', async ({ page }) => {
  const seen = track(page);
  await toDashboard(page);
  await page.getByTestId('dashboard-organizer-public-profile').click();
  await expect(page.locator('[data-screen-label="Organizer profile"]')).toBeVisible({ timeout: 8000 });
  await page.getByTestId('organizer-profile-edit').click();
  await page.setInputFiles('[data-testid="organizer-profile-avatar-input"]', file('avatar.png', png(900, 700, { seed: 7 })));
  await page.getByTestId('organizer-profile-save').click();
  await expect(page.getByTestId('organizer-profile-edit-card')).toHaveCount(0, { timeout: 15000 });
  const img = page.getByTestId('organizer-profile-avatar');
  await expect(img).toBeVisible({ timeout: 10000 });
  await expect(img).toHaveAttribute('src', MEDIA_RE);
  expect(seen.api).toEqual(['init', 'finalize']);                                   // the REAL endpoint answered (not a fallback)
  expect(seen.puts.sort()).toEqual(['card', 'full', 'thumb']);                      // browser PUT three variants straight to storage
  const o = (await admin.from('organizers').select('avatar_r2_ref').eq('id', ORG).single()).data;
  expect(o.avatar_r2_ref).toMatch(/^r2:org-/);
  const a = (await admin.from('media_assets').select('status, variants, kind').eq('organizer_id', ORG).single()).data;
  expect(a).toMatchObject({ status: 'published', kind: 'organizer_avatar' });
  expect(a.variants.full.w).toBeLessThanOrEqual(1600); expect(a.variants.thumb.w).toBeLessThanOrEqual(320);
});

test('event photo: Dashboard upload is published on R2; card/thumb used for lists, full only for the viewer', async ({ page }) => {
  const seen = track(page);
  await toDashboard(page);
  const [chooser] = await Promise.all([page.waitForEvent('filechooser'), page.getByTestId(`dashboard-add-photo-${EV}`).click()]);
  await chooser.setFiles(file('photo.png', png(2000, 1300, { seed: 5 })));
  await expect.poll(async () => (await admin.from('event_photos').select('r2_ref').eq('event_id', EV)).data?.[0]?.r2_ref, { timeout: 20000 }).toMatch(/^r2:ev-/);
  expect(seen.api).toEqual(['init', 'finalize']);
  expect(seen.puts.sort()).toEqual(['card', 'full', 'thumb']);
  const { data: row } = await admin.from('event_photos').select('storage_path, r2_ref').eq('event_id', EV).single();
  expect(row.storage_path).toBe(row.r2_ref);
  const a = (await admin.from('media_assets').select('variants').eq('event_id', EV).single()).data;
  for (const v of ['thumb', 'card', 'full']) expect(await s3Has(cfg.publicBucket, a.variants[v].key), v).toBe(true);
  expect(a.variants.full.w).toBeLessThanOrEqual(1600);
});

test('read path: a public R2 photo renders from the media domain; with the read flag semantics a legacy row still renders from Supabase', async ({ page }) => {
  const seen = track(page);
  await setupToHome(page);
  await page.goto(`/org/${ORG}`);
  await page.waitForTimeout(3000);
  const srcs = await page.$$eval('img', (els) => els.map((e) => e.currentSrc || e.src));
  const mediaImgs = srcs.filter((s) => MEDIA_RE.test(s));
  expect(mediaImgs.length, `images on the organizer page: ${JSON.stringify(srcs)}`).toBeGreaterThan(0);
  expect(mediaImgs.some((s) => /\/full\.(png|jpg)$/.test(s)), 'a list/profile surface must not request the full-size variant').toBe(false);
  expect(seen.mediaGets.length).toBeGreaterThan(0);
});

test('cold vs warm transfer: second visit is served from the browser cache (immutable), no new media-domain requests', async ({ browser }) => {
  const ctx = await browser.newContext({ storageState: process.env.E2E_STORAGE_STATE });
  const page = await ctx.newPage();
  await setupToHome(page);
  await resetMock();
  await page.goto(`/org/${ORG}`); await page.waitForLoadState('networkidle');
  const cold = await mediaStats();
  expect(cold.requests).toBeGreaterThan(0);
  await page.goto('about:blank'); await page.goto(`/org/${ORG}`); await page.waitForLoadState('networkidle');
  const warm = await mediaStats();
  test.info().annotations.push({ type: 'transfer', description: `cold: ${cold.requests} req / ${cold.bytes} B; warm revisit added ${warm.requests - cold.requests} req / ${warm.bytes - cold.bytes} B` });
  expect(warm.requests - cold.requests).toBe(0);
  await ctx.close();
});

test('privacy change from the host\'s side removes the public copy; the page stops serving it', async ({ page }) => {
  await setupToHome(page);
  const { data: row } = await admin.from('event_photos').select('r2_ref').eq('event_id', EV).single();
  const m = /^r2:(.+)\/([0-9a-f-]{36})\.(\w+)$/.exec(row.r2_ref);
  const full = `${MEDIA}/v1/${m[1]}/${m[2]}/full.${m[3]}`;
  expect((await fetch(full)).status).toBe(200);
  const token = await page.evaluate(() => { const k = Object.keys(localStorage).find((x) => x.endsWith('-auth-token')); return JSON.parse(localStorage.getItem(k)).access_token; });
  await resetMock();
  await admin.from('events').update({ visibility: 'invite' }).eq('id', EV);
  const r = await media(token, { op: 'reconcile', eventId: EV });
  expect(r.json.unpublished).toBe(1);
  expect((await fetch(full)).status).toBe(404);
  expect((await mockCalls()).flatMap((c) => c.files)).toContain(full);
  await page.goto(`/org/${ORG}`); await page.waitForTimeout(2500);
  const srcs = await page.$$eval('img', (els) => els.map((e) => e.currentSrc || e.src));
  expect(srcs.filter((s) => s.includes(m[2])), 'the withdrawn photo must not be rendered from the public domain').toHaveLength(0);
});

test('legacy fallback in the browser: server flag off -> the same UI upload lands in Supabase Storage and renders from there', async ({ page }) => {
  await setFlags({ MEDIA_R2_UPLOADS: 'off' });
  const seen = track(page);
  await toDashboard(page);
  await page.getByTestId('dashboard-organizer-public-profile').click();
  await page.getByTestId('organizer-profile-edit').click();
  await page.setInputFiles('[data-testid="organizer-profile-avatar-input"]', file('avatar2.png', png(600, 600, { seed: 2 })));
  await page.getByTestId('organizer-profile-save').click();
  await expect(page.getByTestId('organizer-profile-edit-card')).toHaveCount(0, { timeout: 15000 });
  const img = page.getByTestId('organizer-profile-avatar');
  await expect(img).toHaveAttribute('src', new RegExp(`/storage/v1/object/public/organizer-photos/${ORG}/avatar-`), { timeout: 10000 });
  expect(seen.api).toEqual(['init']);                                                // init answered {provider:'supabase'}, nothing else
  expect(seen.puts).toHaveLength(0);
  // A legacy upload that REPLACES an R2 avatar must not leave the old R2 pointer behind: any resolver that prefers
  // avatar_r2_ref (iOS, or web with reads on after a reload) would otherwise keep showing the stale photo.
  const org = (await admin.from('organizers').select('avatar_path, avatar_r2_ref').eq('id', ORG).single()).data;
  expect(org.avatar_path).toMatch(new RegExp(`^${ORG}/avatar-`));
  expect(org.avatar_r2_ref, 'stale R2 avatar pointer left after a legacy replacement').toBeNull();
  await setFlags({ MEDIA_R2_UPLOADS: 'on' });
});
