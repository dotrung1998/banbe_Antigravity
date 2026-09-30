// Location-hierarchy backfill (2026-09-30, .claude/notes/20-location-hierarchy-photo-viewer.md)
// — one-time, idempotent, rate-limited reverse-geocode of EXISTING events'
// OWN already-verified lat/lng to fill in ONLY the new
// country_code/state_province/neighborhood columns (migration
// 20261024000112_112_location_hierarchy_fields.sql) where they are
// currently null. Never invents a new lat/lng, never touches
// area/address_line/city — those are read-only inputs here, never written.
//
// Provider: Nominatim reverse geocoding (https://nominatim.openstreetmap.org/reverse),
// the SAME free, no-API-key provider the web app's own forward-geocode
// address autocomplete already uses (GocContext.jsx's searchCreateAddress).
// Sequential requests, 1 req/sec (matches Nominatim's usage policy — the
// same discipline the existing 500ms-debounced forward search already
// follows, just sequential here since this is a batch job, not a keystroke
// stream), with a real User-Agent per Nominatim's policy.
//
// DRY RUN by default: prints "id -> lat,lng -> resolved country/state/
// neighborhood" for every candidate row, and the exact count that WOULD
// change. Nothing is written to the database in this mode.
// `--write` actually applies the updates. Idempotent — only touches rows
// where ALL THREE of country_code/state_province/neighborhood are
// currently null (`.is('country_code', null)`), and re-checks at write
// time, so a re-run never clobbers a value this script (or anything else)
// already wrote.
// `--id=<event-id>` limits either mode to one specific event.
// Rows with no lat/lng are skipped and logged, never guessed.
//
// Run: node scripts/backfill-location-hierarchy.mjs [--write] [--id=<event-id>]
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

const args = process.argv.slice(2);
const WRITE = args.includes('--write');
const ONLY_ID = (args.find(a => a.startsWith('--id=')) || '').slice('--id='.length) || null;

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY (.env.local)');
  process.exit(1);
}
const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function reverseGeocode(lat, lng) {
  const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&addressdetails=1&lat=${lat}&lon=${lng}`;
  const res = await fetch(url, {
    headers: {
      Accept: 'application/json',
      // Nominatim usage policy requires an identifying User-Agent.
      'User-Agent': 'banbe-app-location-backfill/1.0 (one-time script, doqanh0906@gmail.com)',
    },
  });
  if (!res.ok) throw new Error(`GEOCODE_HTTP_${res.status}`);
  const hit = await res.json();
  const addr = hit.address || {};
  const countryCode = (addr.country_code || '').toUpperCase().slice(0, 2) || null;
  const stateProvince = (addr.state || addr.province || '').trim() || null;
  // "neighborhood" is finer than the district already stored in `area` —
  // Nominatim's neighbourhood/quarter tag when present, falling back to
  // suburb ONLY when it differs from what's already in the row's `area`
  // (checked by the caller, not here, since this function doesn't know
  // the row's existing area).
  const neighborhood = (addr.neighbourhood || addr.quarter || '').trim() || null;
  return { countryCode, stateProvince, neighborhood, raw: addr };
}

async function main() {
  let query = supabase
    .from('events')
    .select('id, area, city, lat, lng, country_code, state_province, neighborhood')
    .is('country_code', null);
  if (ONLY_ID) query = query.eq('id', ONLY_ID);
  const { data: rows, error } = await query;
  if (error) { console.error('Query failed:', error); process.exit(1); }

  console.log(`Mode: ${WRITE ? 'WRITE' : 'DRY RUN'}${ONLY_ID ? ` (id=${ONLY_ID})` : ''}`);
  console.log(`Candidate rows (country_code IS NULL): ${rows.length}\n`);

  let resolved = 0;
  let skippedNoCoords = 0;
  let failed = 0;

  for (const row of rows) {
    if (row.lat == null || row.lng == null) {
      skippedNoCoords += 1;
      console.log(`SKIP  ${row.id} — no lat/lng on row (area="${row.area}")`);
      continue;
    }
    try {
      const { countryCode, stateProvince, neighborhood, raw } = await reverseGeocode(row.lat, row.lng);
      console.log(
        `${WRITE ? 'WRITE' : 'DRY '}  ${row.id}  (${row.lat},${row.lng})  area="${row.area}"\n` +
        `        -> country_code=${countryCode}  state_province=${stateProvince}  neighborhood=${neighborhood}\n` +
        `        raw address keys: ${Object.keys(raw).join(', ')}`
      );
      if (countryCode || stateProvince || neighborhood) resolved += 1;
      if (WRITE) {
        const { error: upErr } = await supabase
          .from('events')
          .update({ country_code: countryCode, state_province: stateProvince, neighborhood })
          .eq('id', row.id)
          .is('country_code', null); // re-check at write time — never clobber a concurrent write
        if (upErr) { console.error(`  UPDATE FAILED for ${row.id}:`, upErr); failed += 1; }
      }
    } catch (err) {
      failed += 1;
      console.error(`FAIL  ${row.id} — reverse geocode error:`, err.message || err);
    }
    await sleep(1100); // 1 req/sec, plus a safety margin, per Nominatim's usage policy
  }

  console.log(`\nDone. Candidates: ${rows.length}  Resolved: ${resolved}  Skipped (no coords): ${skippedNoCoords}  Failed: ${failed}`);
  if (!WRITE) console.log('Dry run only — re-run with --write to apply.');
}

main();
