// Demo-catalogue-to-real-data parity pass (2026-09-29) — inventory finding:
// EVERY static demo catalogue event (src/data/events.js's own EVENTS
// array, 21 entries) ALREADY has a real, DB-backed `events` row, a real
// `organizers` row, and real `event_photos` rows (confirmed live against
// the actual project before writing this — see the phase-3 report for the
// exact counts: 21/21 events, 21/21 organizers, 85 event_photos rows, 0
// missing). Migration 010's original seed already did the real backfill
// this ticket asked for — there is no missing events/organizers/photos
// data to insert.
//
// What IS genuinely missing, confirmed the same way: `included_items`
// (migration 087's structured "Bao gồm" — `[{label, detail}]`) is an empty
// array on all 21 demo rows, even though every one of them already has the
// OLDER, pre-087 `included` column populated with a real, bullet-joined
// string (e.g. "5 món ▪︎ rượu gạo ▪︎ cà phê") from the original seed. This
// backfill mechanically decomposes that ALREADY-REAL string into the
// structured shape — never invents new content, just re-shapes existing
// data into the newer column migration 087 added after the original seed
// ran. `address_line`/`city`/`address_verified` are deliberately NOT
// touched here: the demo dataset has no real street-address text anywhere
// (only a district-level `area` string), and inventing a house number to
// make `address_verified` true would be exactly the fabrication the ticket
// prohibits — those stay empty/false, honestly reflecting "never verified,"
// same as any other legacy event.
//
// Idempotent: only ever touches a row whose `included_items` is CURRENTLY
// an empty array — a second run is a safe no-op (see the `already-
// populated` skip below). Never touches `included`, any user-edited real
// event, or any row outside the demo catalogue's own 21 keys.
//
// Run once with: node scripts/backfill-demo-included-items.mjs
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

const { EVENTS } = await import(path.join(repoRoot, 'src/data/events.js'));
const demoKeys = EVENTS.map(e => e.key);

const { data: rows, error } = await admin
  .from('events')
  .select('id, included, included_items')
  .in('id', demoKeys);
if (error) throw error;

const summary = { backfilled: [], skippedAlreadyPopulated: [], skippedNoIncludedText: [], skippedTooManyItems: [] };

for (const row of rows) {
  if (Array.isArray(row.included_items) && row.included_items.length > 0) {
    summary.skippedAlreadyPopulated.push(row.id);
    continue;
  }
  const raw = (row.included || '').trim();
  if (!raw) {
    summary.skippedNoIncludedText.push(row.id);
    continue;
  }
  // Same separator the app's own display string already uses
  // everywhere (' ▪︎ ') — splitting on it is the exact inverse of how
  // `create_event_draft`/`resubmit_event_for_review` (migration 087)
  // build `included` FROM `included_items` in the first place
  // (`array_to_string(v_included_labels, ' ▪︎ ')`), so this is a lossless
  // round-trip for this dataset's shape, not a guess.
  const labels = raw.split(' ▪︎ ').map(s => s.trim()).filter(Boolean);
  if (labels.length > 3) {
    // Migration 087's own cap — never write something the same schema's
    // own validation would reject on a real submit.
    summary.skippedTooManyItems.push(row.id);
    continue;
  }
  if (labels.some(l => l.length > 60)) {
    summary.skippedTooManyItems.push(row.id); // reusing the same bucket — also a validation-cap miss
    continue;
  }
  const items = labels.map(label => ({ label, detail: '' }));
  const { error: updateErr } = await admin.from('events').update({ included_items: items }).eq('id', row.id);
  if (updateErr) throw updateErr;
  summary.backfilled.push({ id: row.id, items });
}

console.log(JSON.stringify(summary, null, 2));
console.log(`\nBackfilled: ${summary.backfilled.length}, already populated (skipped): ${summary.skippedAlreadyPopulated.length}, no included text (skipped): ${summary.skippedNoIncludedText.length}, over validation cap (skipped): ${summary.skippedTooManyItems.length}`);
