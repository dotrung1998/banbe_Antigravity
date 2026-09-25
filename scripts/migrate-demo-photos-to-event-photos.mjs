// STAGE D (2026-09-25) — one-time data migration: uploads each REAL
// catalog-matched event's own bundled demo gallery images (already real
// photo files in public/photos/, just never tied to a real Storage row)
// to the real `event-photos` Storage bucket under that event's real id,
// then inserts a corresponding `event_photos` row for each — so every
// screen that used to read the static, DB-disconnected `gallery`/
// `orgGallery` can read real data instead. Idempotent: skips any event
// that already has event_photos rows (re-running this is always safe).
//
// Run once with: node scripts/migrate-demo-photos-to-event-photos.mjs
// Requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (.env.local).
import { createClient } from '@supabase/supabase-js';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');

for (const f of ['.env', '.env.local']) {
  const p = path.join(repoRoot, f);
  if (fs.existsSync(p)) {
    for (const line of fs.readFileSync(p, 'utf8').split('\n')) {
      const m = line.match(/^([A-Z_]+)=(.*)$/);
      if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
    }
  }
}

const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

// PHOTOS_PER_EVENT caps how many of each event's own bundled gallery
// images get migrated — not all 8 need to become real rows for the
// feature to be real; a handful of real photos per event is enough for
// Pulse's photo tab / Task 3's like-heart system to have genuine data for
// every event, not just one.
const PHOTOS_PER_EVENT = 4;

const { EVENTS } = await import(path.join(repoRoot, 'src/data/events.js'));

const { data: realEvents, error: evErr } = await admin.from('events').select('id, status, visibility');
if (evErr) throw evErr;
const realEventIds = new Set(realEvents.map(e => e.id));

const { data: existingPhotos, error: phErr } = await admin.from('event_photos').select('event_id');
if (phErr) throw phErr;
const eventsWithPhotos = new Set(existingPhotos.map(p => p.event_id));

const summary = { migrated: [], skippedAlreadyHasPhotos: [], skippedNoRealRow: [] };

for (const ev of EVENTS) {
  if (!realEventIds.has(ev.key)) { summary.skippedNoRealRow.push(ev.key); continue; }
  if (eventsWithPhotos.has(ev.key)) { summary.skippedAlreadyHasPhotos.push(ev.key); continue; }

  const gallery = (ev.gallery || []).slice(0, PHOTOS_PER_EVENT);
  let uploaded = 0;
  for (let i = 0; i < gallery.length; i++) {
    const webPath = gallery[i]; // e.g. "/photos/DSCF4423.jpg"
    const filename = webPath.split('/').pop();
    const localPath = path.join(repoRoot, 'public', 'photos', filename);
    if (!fs.existsSync(localPath)) { console.warn(`  ! missing local file for ${ev.key}: ${localPath}`); continue; }
    const bytes = fs.readFileSync(localPath);
    const storagePath = `${ev.key}/${filename}`;
    const { error: upErr } = await admin.storage.from('event-photos').upload(storagePath, bytes, {
      contentType: 'image/jpeg', upsert: true,
    });
    if (upErr) { console.warn(`  ! upload failed for ${ev.key}/${filename}:`, upErr.message); continue; }
    const { error: rowErr } = await admin.from('event_photos').insert({
      event_id: ev.key, storage_path: `event-photos/${storagePath}`, sort_order: i,
    });
    if (rowErr) { console.warn(`  ! row insert failed for ${ev.key}/${filename}:`, rowErr.message); continue; }
    uploaded++;
  }
  if (uploaded > 0) summary.migrated.push({ key: ev.key, count: uploaded });
}

console.log('\n=== Migration summary ===');
console.log(`Migrated (real photos added): ${summary.migrated.length} events`);
for (const m of summary.migrated) console.log(`  ${m.key}: ${m.count} photo(s)`);
console.log(`\nSkipped, already had event_photos: ${summary.skippedAlreadyHasPhotos.length}`, summary.skippedAlreadyHasPhotos);
console.log(`Skipped, no real events row at all: ${summary.skippedNoRealRow.length}`, summary.skippedNoRealRow);
