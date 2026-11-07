// Event-introduction backfill (2026-09-28, revised after auto-review of a
// real dry run against live data) — fills `events.intro` ("Giới thiệu sự
// kiện") for existing events that don't have one, using ONLY verified
// facts already on each event's own row: name, cat_label (category),
// area (district), event_date/event_time (see the timezone note below —
// NEVER `starts_at`), and included_items. Never invents performers,
// menus, amenities, accessibility, pricing benefits, or organizer
// promises — an event with too few reliable facts gets a short, honest
// sentence instead of padded-out fiction. Every existing organizer-
// written intro is left untouched, and `included_items`/`included` are
// never rewritten — this only ever writes to `intro`.
//
// Auto-review findings from the first real dry run against live data,
// fixed here (not hypothetical — see this script's own git history for
// the pre-review version):
//   1. `starts_at` is NOT a reliable source for a displayed clock time.
//      Migration 20260921000063 (the demo-event date randomizer) builds
//      it as `(current_date + offset) + event_time` — a NAIVE timestamp
//      cast to timestamptz, which Postgres interprets in the session's
//      OWN timezone (UTC on this project), not Asia/Ho_Chi_Minh. A real,
//      RPC-created event's `starts_at` (create_event_draft) IS correctly
//      converted via `AT TIME ZONE 'Asia/Ho_Chi_Minh'`. Reading `starts_at`
//      the same way for both classes of row — confirmed live via a direct
//      query — produces a 7-hour-wrong clock time for one class or the
//      other; there is no single correct interpretation from this script
//      alone. `event_date`/`event_time` (naive date/time columns, no
//      timezone ambiguity) are the actual wall-clock values the create
//      flow itself was given — used instead, and only when both are
//      present (a handful of demo rows, e.g. evt_001-004, have ONLY
//      starts_at — those get no date/time mentioned at all rather than a
//      guessed one).
//   2. Every voice had an identical closing CTA sentence ("Số chỗ có hạn
//      — xem chi tiết và giữ chỗ ngay trên trang sự kiện.") — real
//      repetitive boilerplate across 7+ events, AND factually wrong
//      "book now" framing for events whose `status` is already
//      'cancelled'/'ended' (confirmed live: bandai is cancelled;
//      compound/fanci/jazzgac/modular/orbit/phokhuya/vuonsau/pianomuon and
//      evt_001/002/004 are ended). Removed entirely, not reworded per
//      status — Event Detail's own status/seats UI already owns that
//      messaging; an auto-generated intro doesn't need to repeat it.
//   3. The gallery voice claimed "Một không gian mở cho bất kỳ ai muốn
//      ghé qua" (open to anyone) — not actually verified anywhere
//      on the row (`visibility` can be 'invite', confirmed live for 2 of
//      the 27 candidates) — removed.
//   4. All phrasing switched to tense-neutral, dash-appositive
//      constructions ("Tên — tại Quận, ngày") instead of verb-committed
//      ones ("diễn ra vào...", "mở cửa..."), so the SAME sentence reads
//      correctly whether `status` is upcoming, ended, or cancelled,
//      without needing separate past/future copy per status.
//
// ID-scoped, idempotent, reviewable:
//   - DRY RUN by default: prints "id -> existing intro -> proposed intro"
//     for every candidate row, plus the exact count that WOULD change.
//     Nothing is written to the database in this mode.
//   - `--write` actually applies the updates. Still idempotent — only
//     touches rows where `intro = ''` (not `IS NULL`; migration 088 made
//     the column NOT NULL DEFAULT '', so an untouched row is always the
//     empty string, never SQL NULL), and re-checks that condition at
//     write time (`.eq('intro', '')`) so a re-run, or a race against a
//     host who wrote their own intro in the meantime, can never clobber
//     real organizer copy.
//   - `--id=<event-id>` limits either mode to one specific event.
//   - Never touches owner/organizer_id, bookings, price_vnd, event_date/
//     event_time/starts_at, status, or included_items/included — the
//     UPDATE statement below sets `intro` and nothing else.
//
// Run: node scripts/backfill-event-intros.mjs [--write] [--id=<event-id>]
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

const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

const VN_MONTHS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'];
const VN_WEEKDAYS = ['Chủ nhật', 'Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7'];

/**
 * `event_date`/`event_time` ONLY — see this file's own header for why
 * `starts_at` is not used. Both are naive (no timezone) columns, parsed
 * as plain wall-clock digits, never shifted. `null` when either is
 * missing (some rows only have `starts_at` — no date is mentioned for
 * those rather than guessing one from an ambiguous source).
 */
function formatVnDate(eventDate, eventTime) {
  if (!eventDate) return null;
  // eventDate: "2026-11-09" (a `date` column serializes as this).
  const [y, m, d] = eventDate.split('-').map(Number);
  if (!y || !m || !d) return null;
  const weekday = VN_WEEKDAYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
  const dateLabel = `${weekday}, ${d} tháng ${VN_MONTHS[m - 1]}`;
  if (!eventTime) return dateLabel;
  // eventTime: "19:00:00" (a `time` column).
  const [hh, mm] = eventTime.split(':');
  if (hh == null || mm == null) return dateLabel;
  return `${dateLabel} lúc ${hh}:${mm}`;
}

function includedClause(items) {
  const labels = (Array.isArray(items) ? items : []).map(it => (it?.label || '').trim()).filter(Boolean);
  if (labels.length === 0) return null;
  if (labels.length === 1) return labels[0];
  if (labels.length === 2) return `${labels[0]} và ${labels[1]}`;
  return `${labels.slice(0, -1).join(', ')} và ${labels[labels.length - 1]}`;
}

/**
 * One generator per category — deliberately DIFFERENT sentence
 * structures (not just different nouns) so a reviewer can compare
 * editorial approaches across event types, per this ticket's own ask.
 * Every clause is tense-neutral (a dash-appositive, never "diễn ra vào"/
 * "sẽ..."/"đã...") so the SAME sentence is accurate whether the event is
 * upcoming, ended, or cancelled — Event Detail's own status/seats UI
 * already owns that messaging, this never repeats or contradicts it.
 * Built ONLY from `name`/`catLabel`/`area`/`dateLabel`/`includedText` —
 * no claim (open entry, atmosphere, quality) beyond what those fields
 * actually say.
 */
const VOICES = {
  supper(name, catLabel, area, dateLabel, includedText) {
    const bits = [name];
    if (area) bits.push(`tại ${area}`);
    if (dateLabel) bits.push(dateLabel);
    let s = bits.join(' — ') + '.';
    if (includedText) s += ` Bao gồm ${includedText}.`;
    return s;
  },
  fashion(name, catLabel, area, dateLabel, includedText) {
    const loc = [area, dateLabel].filter(Boolean).join(', ');
    let s = `${name}${loc ? ` (${loc})` : ''} — một sự kiện ${catLabel ? catLabel.toLowerCase() : ''}.`.replace('  ', ' ');
    if (includedText) s += `\n\nBao gồm: ${includedText}.`;
    return s;
  },
  gallery(name, catLabel, area, dateLabel, includedText) {
    const bits = [name];
    if (area) bits.push(`tại ${area}`);
    if (dateLabel) bits.push(dateLabel);
    let s = bits.join(', ') + '.';
    if (includedText) s += ` Có sẵn ${includedText} tại chỗ.`;
    return s;
  },
  music(name, catLabel, area, dateLabel, includedText) {
    const loc = [dateLabel, area ? `tại ${area}` : null].filter(Boolean).join(' — ');
    let s = `${name}${loc ? ` — ${loc}` : ''}.`;
    if (includedText) s += `\n\nBao gồm ${includedText}.`;
    return s;
  },
  popup(name, catLabel, area, dateLabel, includedText) {
    const bits = [name];
    if (catLabel) bits.push(catLabel.toLowerCase());
    if (area) bits.push(area);
    let s = bits.join(' ▪︎ ') + (dateLabel ? ` — ${dateLabel}.` : '.');
    if (includedText) s += ` Có ${includedText}.`;
    return s;
  },
};

/** Honest, minimal fallback for a category with no dedicated voice above (or too few fields for that voice to say anything specific). */
function genericIntro(name, catLabel, area, dateLabel, includedText) {
  const bits = [name];
  const where = [catLabel, area].filter(Boolean).join(', ');
  if (where) bits.push(where);
  if (dateLabel) bits.push(dateLabel);
  let s = bits.join(' — ') + '.';
  if (includedText) s += ` Bao gồm ${includedText}.`;
  return s;
}

function buildIntro(row) {
  const name = (row.name || '').trim();
  if (!name) return null; // nothing reliable to write about at all
  const catLabel = (row.cat_label || '').trim() || null;
  const area = (row.area || '').trim() || null;
  const dateLabel = formatVnDate(row.event_date, row.event_time);
  const includedText = includedClause(row.included_items);
  const voice = VOICES[row.cat_key];
  const text = (voice ? voice(name, catLabel, area, dateLabel, includedText) : null)
    || genericIntro(name, catLabel, area, dateLabel, includedText);
  return text.length > 4000 ? text.slice(0, 4000) : text;
}

let query = admin.from('events').select('id, name, cat_key, cat_label, area, event_date, event_time, status, included_items, intro');
if (ONLY_ID) query = query.eq('id', ONLY_ID);
const { data: rows, error } = await query;
if (error) throw error;

const candidates = rows.filter(r => (r.intro || '') === '');
const skippedHasIntro = rows.length - candidates.length;

console.log(`\n=== Event introduction backfill (${WRITE ? 'WRITE' : 'DRY RUN'}) ===`);
console.log(`${rows.length} event row(s) scanned${ONLY_ID ? ` (--id=${ONLY_ID})` : ''}; ${skippedHasIntro} already have an intro (untouched); ${candidates.length} candidate(s).\n`);

let changed = 0;
const skippedNoFacts = [];
for (const row of candidates) {
  const proposed = buildIntro(row);
  if (!proposed) {
    skippedNoFacts.push(row.id);
    console.log(`  ${row.id} -> SKIPPED (no name on record, nothing honest to write)`);
    continue;
  }
  console.log(`  ${row.id} [${row.status}]`);
  console.log(`    existing intro: (empty)`);
  console.log(`    proposed intro: ${proposed.replace(/\n/g, ' ⏎ ')}`);
  if (WRITE) {
    // Correctness fix (2026-09-28, after the first real --write run) —
    // `{ count: 'exact' }` on `.select()` does NOT populate the
    // destructured `count` the way it does for a plain `.select()` query;
    // confirmed live (an update that demonstrably wrote a row still came
    // back with `count: null`). `data.length` (PostgREST's own returned
    // rows from `RETURNING`) is the actual signal a `.update()` matched
    // anything — used instead.
    const { error: upErr, data: updated } = await admin
      .from('events')
      .update({ intro: proposed })
      .eq('id', row.id)
      .eq('intro', '') // re-checked at write time — never overwrites a real intro written since this scan started
      .select('id');
    if (upErr) {
      console.log(`    ! write failed: ${upErr.message}`);
      continue;
    }
    if (!updated?.length) {
      console.log(`    ! skipped at write time — this row already got an intro from elsewhere since the scan started`);
      continue;
    }
  }
  changed++;
}

console.log(`\n${WRITE ? 'Updated' : 'Would update'}: ${changed} event(s).`);
if (skippedNoFacts.length) console.log(`Skipped (no reliable facts): ${skippedNoFacts.join(', ')}`);
if (!WRITE) console.log('Dry run only — re-run with --write to apply.');
