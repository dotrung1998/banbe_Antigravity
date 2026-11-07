// Generates seed SQL from the static events.js data.
// Usage: node scripts/seed-generate.mjs
import { EVENTS } from '../src/data/events.js';

function priceCents(priceText) {
  if (/Miễn phí|Free/i.test(priceText)) return 0;
  const m = priceText.match(/[\d.]+/);
  if (!m) return 0;
  return parseInt(m[0].replace(/\./g, ''), 10) * 100;
}

function seatsN(seatsStr) {
  const m = seatsStr.match(/(\d+)/);
  return m ? parseInt(m[1], 10) : 0;
}

function pgStr(s) {
  if (s == null) return "''";
  return "'" + String(s).replace(/'/g, "''") + "'";
}

const LOCAL_PHOTOS = [
  'DSCF4423.jpg', 'DSCF5481.jpg', 'DSCF6107.jpg', 'DSCF5891.jpg', 'DSCF2836.jpg',
  'DSCF4627.jpg', 'DSCF2503.jpg', 'DSCF4254.jpg', 'DSCF5796.jpg', 'DSCF5780.jpg',
  'DSCF2539.jpg', 'DSCF4517.jpg', 'DSCF6366.jpg', 'DSCF4223.jpg', 'DSCF5542.jpg',
  'DSCF2341.jpg', 'DSCF4238.jpg', 'DSCF7257.jpg', 'DSCF6279.jpg', 'DSCF4282.jpg',
  'DSCF4550.jpg', 'DSCF4212.jpg', 'DSCF4880.jpg', 'DSCF4488.jpg', 'DSCF4889.jpg',
  'DSCF7202.jpg', 'DSCF7039.jpg', 'DSCF6022.jpg', 'DSCF4207.jpg', 'DSCF6837.jpg',
  'DSCF2438.jpg', 'DSCF4864.jpg', 'DSCF4196.jpg', 'DSCF6368.jpg', 'DSCF2237.jpg',
  'DSCF5973.jpg', 'DSCF4058.jpg', 'DSCF4039.jpg', 'DSCF4065.jpg',
  'DSCF7752.jpg', 'DSCF7609.jpg', 'DSCF7597.jpg', 'DSCF7584.jpg', 'DSCF7576.jpg',
  'DSCF7556.jpg', 'DSCF7501.jpg', 'DSCF7459.jpg', 'DSCF5586.jpg', 'DSCF2128.jpg',
  'DSCF2101.jpg', 'DSCF2095.jpg', 'DSCF2060.jpg', 'DSCF2023.jpg', 'DSCF1740.jpg',
  'DSCF1683.jpg',
];

// Build org map from events
const orgMap = {};
EVENTS.forEach((e) => {
  if (!orgMap[e.key]) {
    orgMap[e.key] = {
      name: e.orgName,
      ig: e.orgIg,
      desc: e.orgDesc,
      since: e.orgSince,
      count: e.orgCount,
    };
  }
});

// Parse when: "Th 7, 11.07 ▪︎ 19:00"
function parseWhen(whenStr) {
  const parts = whenStr.split('▪︎').map((s) => s.trim());
  return { dayShort: parts[0] || '', timeText: parts[1] || '' };
}

// Parse where: "Bình Thạnh ▪︎ 2,1 km từ bạn ▪︎ Thứ Bảy, 11 tháng 7 ▪︎ 19:00"
function parseWhere(whereStr) {
  const parts = whereStr.split('▪︎').map((s) => s.trim());
  return { area: parts[0] || '', km: parts[1] || '', dayLong: parts[2] || '', time: parts[3] || '' };
}

let sql = "-- Generated seed data for Góc\n";
sql += "-- Organizers and events seeded from the original static data in events.js\n\n";
sql += "DO $$\nDECLARE\n  _org_id uuid;\nBEGIN\n\n";

// Organizers
const orgKeys = Object.keys(orgMap);
orgKeys.forEach((key) => {
  const o = orgMap[key];
  sql += `  INSERT INTO organizers (name, ig_handle, bio, hosting_since, event_count, verified)\n`;
  sql += `  VALUES (${pgStr(o.name)}, ${pgStr(o.ig)}, ${pgStr(o.desc)}, ${o.since}, ${o.count}, ${o.count >= 20})\n`;
  sql += `  ON CONFLICT DO NOTHING RETURNING id INTO _org_id;\n`;
  sql += `  PERFORM set_config('goc.org_${key}', _org_id::text, true);\n\n`;
});

// Events
sql += "  -- Events\n";
EVENTS.forEach((e, idx) => {
  const { area, km, dayLong } = parseWhere(e.where);
  const { dayShort, timeText } = parseWhen(e.when);
  const photo = LOCAL_PHOTOS[idx % LOCAL_PHOTOS.length];
  const gallery = [photo];
  for (let i = 0; i < 7; i++) gallery.push(LOCAL_PHOTOS[(idx * 5 + i) % LOCAL_PHOTOS.length]);
  const orgGallery = [photo];
  for (let i = 0; i < 21; i++) orgGallery.push(LOCAL_PHOTOS[(idx * 3 + i) % LOCAL_PHOTOS.length]);

  const pc = priceCents(e.price);
  const isFree = pc === 0;
  const sn = seatsN(e.seats);
  const status = e.cancelled ? 'cancelled' : e.soldOut ? 'sold_out' : e.endedHoursAgo != null ? 'ended' : 'open';

  // Parse date from dayShort: "Th 7, 11.07" -> 2026-07-11
  const dm = dayShort.match(/(\d{1,2})\.(\d{2})/);
  const eventDate = dm ? `2026-${dm[2]}-${dm[1].padStart(2, '0')}` : null;

  sql += `  INSERT INTO events (\n`;
  sql += `    key, organizer_id, name, cat_key, cat_label, description, included,\n`;
  sql += `    price_text, price_cents, is_free, capacity, seats_remaining,\n`;
  sql += `    location, area, km_text, day_short, day_long, time_text,\n`;
  sql += `    event_date, event_time, status, invite_only, greeting,\n`;
  sql += `    hero_photo, gallery, org_gallery, host_name, host_short, palette,\n`;
  sql += `    cancelled_hours_ago, ended_hours_ago\n`;
  sql += `  ) VALUES (\n`;
  sql += `    ${pgStr(e.key)}, NULLIF(current_setting('goc.org_${e.key}', true), '')::uuid,\n`;
  sql += `    ${pgStr(e.name)}, ${pgStr(e.catKey)}, ${pgStr(e.cat)},\n`;
  sql += `    ${pgStr(e.desc)}, ${pgStr(e.included)},\n`;
  sql += `    ${pgStr(e.price)}, ${pc}, ${isFree},\n`;
  sql += `    ${sn}, ${sn},\n`;
  sql += `    ${pgStr(e.where)}, ${pgStr(area)}, ${pgStr(km)},\n`;
  sql += `    ${pgStr(dayShort)}, ${pgStr(dayLong)}, ${pgStr(timeText)},\n`;
  sql += `    ${eventDate ? pgStr(eventDate) : 'NULL'}, ${pgStr(timeText)},\n`;
  sql += `    ${pgStr(status)}, ${e.inviteOnly}, ${pgStr(e.greeting)},\n`;
  sql += `    ${pgStr('/photos/' + photo)},\n`;
  sql += `    jsonb_build_array(${gallery.map((g) => pgStr('/photos/' + g)).join(',')})::jsonb,\n`;
  sql += `    jsonb_build_array(${orgGallery.map((g) => pgStr('/photos/' + g)).join(',')})::jsonb,\n`;
  sql += `    ${pgStr(e.host)}, ${pgStr(e.hostShort)}, ${pgStr(e.palette ? 'concrete' : 'concrete')},\n`;
  sql += `    ${e.cancelledHoursAgo != null ? e.cancelledHoursAgo : 'NULL'},\n`;
  sql += `    ${e.endedHoursAgo != null ? e.endedHoursAgo : 'NULL'}\n`;
  sql += `  ) ON CONFLICT (key) DO NOTHING;\n\n`;
});

// Secondary categories (paid placement)
const CAT2_KEYS = { motlop: 'gallery', aeie: 'gallery', chieucham: 'supper' };
const CAT2_LABELS = { motlop: 'Phòng tranh', aeie: 'Phòng tranh', chieucham: 'Supper club' };

sql += "  -- Secondary categories (paid placement)\n";
Object.keys(CAT2_KEYS).forEach((key) => {
  sql += `  INSERT INTO event_categories (event_id, cat_key, cat_label, sort_order)\n`;
  sql += `  SELECT id, ${pgStr(CAT2_KEYS[key])}, ${pgStr(CAT2_LABELS[key])}, 1 FROM events WHERE key = ${pgStr(key)}\n`;
  sql += `  ON CONFLICT DO NOTHING;\n`;
});

sql += "\nEND $$;\n";

console.log(sql);
