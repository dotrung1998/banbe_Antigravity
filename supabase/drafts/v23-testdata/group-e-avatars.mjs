// v2.3 test data, group E: host photos for 10 test organizers that had none.
// Each image is a square crop of a people-free photo from that host's OWN event photos
// (event-photos bucket), viewed by hand before it was chosen (no faces, no brand text, no flags).
// Files: supabase/drafts/v23-testdata/avatars/<organizer id>.jpg (512 px JPEG).
// Hosts left on the monogram fallback because every own photo shows people or signage:
// comnha, khongnguoi, pianomuon, vungtrang, bangcoi, phong302.
//
// Modes (run from the repo root, needs SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY from .env.local):
//   node supabase/drafts/v23-testdata/group-e-avatars.mjs dry       checks + SQL in a rolled-back transaction, NO upload
//   node supabase/drafts/v23-testdata/group-e-avatars.mjs apply     uploads to organizer-photos, then SQL COMMIT
//   node supabase/drafts/v23-testdata/group-e-avatars.mjs rollback  avatar_path back to '' and removes the uploaded files
// Only rows whose avatar_path is still '' and avatar_r2_ref is NULL are touched (a host's own upload always wins).
import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const MODE = process.argv[2];
if (!['dry', 'apply', 'rollback'].includes(MODE)) { console.error('mode: dry | apply | rollback'); process.exit(2); }
const URL_ = process.env.SUPABASE_URL, KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL_ || !KEY) { console.error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing'); process.exit(2); }
const H = { apikey: KEY, Authorization: `Bearer ${KEY}` };
const BUCKET = 'organizer-photos';
const IDS = ['org_aeie', 'org_bandai', 'org_bepnho', 'org_sonmai', 'org_fanci', 'org_modular', 'org_jazzgac', 'org_orbit', 'org_motlop', 'org_noigiay'];
const pathOf = id => `${id}/v23-avatar-20261113.jpg`;
const dir = new URL('./avatars/', import.meta.url);

function sql(text) {
  const f = join(tmpdir(), `v23-e-${process.pid}.sql`);
  writeFileSync(f, text);
  const out = execFileSync('supabase', ['db', 'query', '--linked', '-o', 'json', '-f', f], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  return JSON.parse(out).rows;
}
const list = IDS.map(id => `'${id}'`).join(',');
const setSql = end => `BEGIN;
DO $$ BEGIN
  IF (SELECT count(*) FROM organizers WHERE id IN (${list}) AND coalesce(avatar_path,'') = '' AND avatar_r2_ref IS NULL) <> ${IDS.length} THEN
    RAISE EXCEPTION 'some organizers already have a photo or are missing';
  END IF;
END $$;
${IDS.map(id => `UPDATE organizers SET avatar_path = '${pathOf(id)}' WHERE id = '${id}' AND coalesce(avatar_path,'') = '' AND avatar_r2_ref IS NULL;`).join('\n')}
SELECT id, name, avatar_path FROM organizers WHERE id IN (${list}) ORDER BY id;
${end};`;

if (MODE === 'dry' || MODE === 'apply') {
  for (const id of IDS) readFileSync(new URL(`${id}.jpg`, dir)); // every file present
  if (MODE === 'apply') {
    for (const id of IDS) {
      const r = await fetch(`${URL_}/storage/v1/object/${BUCKET}/${pathOf(id)}`, {
        method: 'POST',
        headers: { ...H, 'Content-Type': 'image/jpeg', 'cache-control': 'max-age=31536000', 'x-upsert': 'false' },
        body: readFileSync(new URL(`${id}.jpg`, dir)),
      });
      if (!r.ok) { console.error('upload failed', id, r.status, await r.text()); process.exit(1); }
      console.log('uploaded', pathOf(id));
    }
  }
  const rows = sql(setSql(MODE === 'apply' ? 'COMMIT' : 'ROLLBACK'));
  for (const r of rows) console.log(r.id.padEnd(12), r.name.padEnd(22), '→', r.avatar_path);
  if (MODE === 'apply') {
    for (const id of IDS) {
      const r = await fetch(`${URL_}/storage/v1/object/public/${BUCKET}/${pathOf(id)}`, { method: 'HEAD' });
      console.log('public', id, r.status);
    }
  }
} else {
  const rows = sql(`BEGIN;
${IDS.map(id => `UPDATE organizers SET avatar_path = '' WHERE id = '${id}' AND avatar_path = '${pathOf(id)}';`).join('\n')}
SELECT id, avatar_path FROM organizers WHERE id IN (${list}) ORDER BY id;
COMMIT;`);
  for (const r of rows) console.log(r.id, JSON.stringify(r.avatar_path));
  const r = await fetch(`${URL_}/storage/v1/object/${BUCKET}`, {
    method: 'DELETE', headers: { ...H, 'Content-Type': 'application/json' },
    body: JSON.stringify({ prefixes: IDS.map(pathOf) }),
  });
  console.log('storage delete', r.status, (await r.text()).slice(0, 200));
}
