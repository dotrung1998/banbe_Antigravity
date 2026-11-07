// One-off, idempotent backfill of events.details (event type profiles, migrations 203/204, note 66).
//
// Every event in the app is owner-created test data. This gives each one the facts its type shows (alcohol and
// minimum age for all; lineup / artists / brands and the type's choices), derived from its own title, description,
// included items, price and capacity where they say something, otherwise a plausible sample value.
//
//   node scripts/backfill-event-details.mjs <events.json> [--sql <out.sql>]
//
// <events.json>: rows of { id, cat_key, name, description, included (labels joined by ';'), price_vnd, capacity,
// details } (e.g. `supabase db query --output-format json` of the select in note 66). Prints the dry-run list.
// With --sql it writes ONE transaction that, per event, acts as that event's own host and calls
// set_event_details() (the same validator and writer the apps use) with `new || existing`: values already set
// always win, so nothing is overwritten and a second run changes nothing. Any failure aborts the whole run.
import { readFileSync, writeFileSync } from 'node:fs';
import { profileFor, cleanDetails } from '../src/lib/eventTypes.js';

const [, , input, flag, outPath] = process.argv;
if (!input) { console.error('usage: node scripts/backfill-event-details.mjs <events.json> [--sql <out.sql>]'); process.exit(2); }
const text = readFileSync(input, 'utf8');
const parsed = JSON.parse(text.slice(text.indexOf('{') >= 0 && text.indexOf('{') < text.indexOf('[') ? text.indexOf('{') : text.indexOf('[')));
const rows = Array.isArray(parsed) ? parsed : parsed.rows;

const fold = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D').toLowerCase();
const has = (e, ...words) => words.some(w => fold(`${e.name} ${e.description} ${e.included}`).includes(fold(w)));

// Read from the event itself first: alcohol from what is included, age from alcohol.
function alcoholOf(e) {
  if (has(e, 'ruou', 'vang', 'cocktail', 'bia', 'welcome drink')) return 'included';
  if (has(e, 'do uong', 'mot do uong')) return 'paid';
  if (has(e, 'tra', 'ca phe', 'nuoc')) return 'none';
  return null;
}

// Hand-read from each seeded event's title / description / included items (2026-10-30 production snapshot).
// Names in lists are sample names where the event text gives none.
const KNOWN = {
  // supper
  bandai: { dietary: ['can_accommodate'], dress_code: 'Lịch sự, thoải mái' },
  banrieng: { dietary: ['pescatarian', 'can_accommodate'], dress_code: 'Lịch sự' },
  bepnho: { dietary: ['vegetarian', 'can_accommodate'] },
  comnha: { dietary: ['vegetarian'], alcohol: 'none', min_age: '16', dress_code: 'Thoải mái' },
  phokhuya: { dietary: ['can_accommodate'], alcohol: 'none', min_age: '16' },
  vuonsau: { dietary: ['vegetarian', 'gluten_free'], min_age: '21' },
  'test-s-ki-n-8444c8': { dietary: ['vegan'], alcohol: 'byo', min_age: '18' },
  'test-cfe040': { dietary: ['halal'], alcohol: 'byo', min_age: '18' },
  'test-2-edad57': { dietary: ['vegan', 'vegetarian'], alcohol: 'none', min_age: '16' },
  // music
  jazzgac: { lineup: ['Bộ ba Gác', 'Khách mời: Linh Sax'], genre: ['jazz'], format: 'seated', alcohol: 'included', min_age: '18' },
  pianomuon: { lineup: ['Minh Châu (piano)'], genre: ['classical'], format: 'seated', alcohol: 'included', min_age: '18' },
  modular: { lineup: ['Đêm Modular Collective', 'Hạt'], genre: ['electronic', 'experimental'], format: 'standing', alcohol: 'paid', min_age: '18' },
  chieucham: { lineup: ['Mây Chiều', 'Tú (guitar)'], genre: ['acoustic', 'folk'], format: 'mixed', alcohol: 'none', min_age: '16' },
  bangcoi: { lineup: ['Băng Cối'], genre: ['folk', 'indie'], format: 'seated', alcohol: 'none', min_age: '16' },
  // gallery
  khongnguoi: { artists: ['Trần Vũ'], medium: ['photography'] },
  phong302: { artists: ['Lê Na', 'Đỗ Khang', 'Hà My'], medium: ['painting', 'print', 'lacquer', 'installation'] },
  sonmai: { artists: ['Nguyễn Tư', 'Nguyễn Tư An'], medium: ['lacquer'] },
  noigiay: { artists: ['Xưởng Giấy Dó'], medium: ['print'] },
  vungtrang: { artists: ['Phạm Thu', 'Lý Đan', 'Ngô Bảo'], medium: ['painting', 'installation'] },
  // fashion
  aeie: { brands: ['AEIE'], experience: 'show', price_range: 'premium', alcohol: 'none', min_age: '16' },
  compound: { brands: ['Compound'], experience: 'sale', price_range: 'budget', alcohol: 'paid', min_age: '18' },
  fanci: { brands: ['Fanci'], experience: 'fitting', price_range: 'mid', alcohol: 'included', min_age: '18' },
  motlop: { brands: ['Chỉ Một Lớp', 'Vải Mộc', 'Sợi', 'Ô Studio'], experience: 'talk', price_range: 'mid' },
  orbit: { brands: ["L'Édition"], experience: 'show', price_range: 'premium', alcohol: 'included', min_age: '18' },
};

// Anything not in the table (an event created later): only what the event itself says, plus safe defaults.
function derived(e) {
  const alcohol = alcoholOf(e) || 'none';
  const out = { alcohol, min_age: alcohol === 'none' ? '16' : '18' };
  switch (e.cat_key) {
    case 'music': return { ...out, lineup: [e.name], format: 'seated' };
    case 'gallery': return { ...out, artists: [e.name] };
    case 'fashion': case 'popup': return { ...out, brands: [e.name] };
    default: return out;
  }
}

const plan = [];
for (const e of rows) {
  const profile = profileFor(e.cat_key);
  if (!profile.detailFields) { plan.push({ e, skip: `type '${e.cat_key}' has no facts` }); continue; }
  const proposal = { ...derived(e), ...(KNOWN[e.id] || {}) };
  // Same cleaning the apps do, then existing values win (never overwritten).
  const add = cleanDetails(profile, proposal);
  const existing = e.details && typeof e.details === 'object' ? e.details : {};
  const merged = { ...add, ...existing };
  const changed = Object.keys(add).filter(k => k !== 'v' && !(k in existing));
  plan.push({ e, add, merged, changed });
}

const short = (v) => (Array.isArray(v) ? v.join('+') : v);
console.log(`DRY RUN: ${rows.length} events`);
for (const p of plan) {
  if (p.skip) { console.log(`  ${p.e.id.padEnd(20)} SKIP ${p.skip}`); continue; }
  const vals = p.changed.map(k => `${k}=${short(p.add[k])}`).join(' ');
  console.log(`  ${p.e.id.padEnd(20)} ${String(p.e.cat_key).padEnd(8)} ${p.changed.length ? vals : '(nothing new, already set)'}`);
}

if (flag === '--sql' && outPath) {
  const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
  const values = plan.filter(p => !p.skip).map(p => `    (${q(p.e.id)}, ${q(JSON.stringify(p.add))}::jsonb)`).join(',\n');
  const sql = `-- GENERATED by scripts/backfill-event-details.mjs — one transaction, idempotent (existing values win).
BEGIN;
DO $bf$
DECLARE
  e record; merged jsonb; r jsonb; n_set int := 0; n_same int := 0;
BEGIN
  FOR e IN
    SELECT ev.id, ev.details, coalesce(o.owner_id, o.user_id) AS host, v.add
    FROM (VALUES
${values}
    ) AS v(id, add)
    JOIN public.events ev ON ev.id = v.id
    LEFT JOIN public.organizers o ON o.id = ev.organizer_id
    ORDER BY ev.id
  LOOP
    merged := e.add || e.details;            -- the right side wins: values already set are kept
    IF merged = e.details THEN n_same := n_same + 1; CONTINUE; END IF;
    IF e.host IS NULL THEN RAISE EXCEPTION 'BACKFILL % has no host to act as', e.id; END IF;
    PERFORM set_config('request.jwt.claim.sub', e.host::text, true);   -- act as this event's own host
    r := public.set_event_details(e.id, merged);
    IF coalesce((r->>'success')::boolean, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'BACKFILL % failed: %', e.id, r->>'error';
    END IF;
    n_set := n_set + 1;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  RAISE NOTICE 'BACKFILL set=% unchanged=%', n_set, n_same;
END $bf$;
COMMIT;
`;
  writeFileSync(outPath, sql);
  console.log(`SQL written: ${outPath}`);
}
