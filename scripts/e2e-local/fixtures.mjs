// SYNTHETIC, LOCAL-ONLY fixture seeder for the isolated E2E stack (never touches hosted Supabase: guard.mjs is asserted first).
//
// DEVIATION from the `e2e-fixture-` id prefix for events: production's demo rows use the catalogue key as the event id, and the app
// joins on exactly that (Home card key -> goEvent/openEventOnMap(selectedId = key) -> Map events.id). A prefixed id breaks that join
// (spec 'Task 7' needs it), so events keep the catalogue ids; fixture rows are identifiable by organizer_id `e2e-fixture-org-*`.
//
// Why: the focused specs were written against production, where migration 020/063 turned the frontend's static demo
// catalogue (src/data/events.js ROWS) into real live public `events` rows with coordinates/categories. A fresh local DB has
// only 4 unrelated rows (evt_001..evt_004, two live), so Map Explore sees a single pin/list row and no supper/fashion/
// gallery/music events. This reproduces ONLY that data shape: 20 live public events (5 per category) + one organizer
// each, all owned by one dedicated synthetic owner. Organizer ids/owner email are prefixed `e2e-fixture-`; EVENT ids are the demo
// catalogue keys on purpose (see below); no personal data; idempotent
// (upsert on every run, dates re-anchored to "now" so they stay in the future). It deliberately does NOT write
// event photos/covers (no storage dependency), follows, stories, or bookings.
//
// What it cannot prove: real production data volume/distribution, real cover images, or anything about hosted behaviour.
import { createHash } from 'node:crypto';
import { assertIsolated } from './guard.mjs';

export const FIXTURE_PREFIX = 'e2e-fixture-';
const OWNER_EMAIL = 'e2e-fixture-owner@example.invalid';
// Deterministic layout, single latitude row. Constraints it is designed around (all measured against the current app):
//  * src/lib/densityHotspot.js centres the map on the densest 0.02-degree cell: cell A (i 6..14, 9 events) is the unique winner;
//    the 5 music events (i 15..19) sit alone in the next cell east so music's own hotspot differs from the overall one.
//  * The 5 s freshness poll re-queries only the INITIAL viewport bounds (393px-wide phone frame at zoom 13 =~ +-0.0168 deg lng
//    around the centre) and replaces the loaded events with the result, so every fixture event is kept inside that box.
//  * MapExplore.jsx gives every pin's wrapper an inline `position:relative` that overrides MapLibre's `.maplibregl-marker
//    {position:absolute}`, so with N markers pin k renders (-181px, +30k px) away from its true position (measured, see
//    diag/map-markers.diag.mjs; reported as an APP BUG, deliberately not worked around). The spec's `.first()` pin is DOM
//    index 0 (= earliest start = FIRST), placed ~100px east of the centre so it renders on screen, unobstructed.
const LNG = Array.from({ length: 20 }, (_, i) => (i <= 5 ? 106.6845 + 0.001 * i : i <= 14 ? 106.6905 + 0.00225 * (i - 6) : 106.711 + 0.001 * (i - 15)));
const FIRST = 14; // earliest event => first pin in DOM order
const coordsFor = (i) => ({ lat: 10.7769, lng: LNG[i] });
const CAT = { supper: 'Supper club', fashion: 'Thời trang', gallery: 'Phòng tranh', music: 'Nhạc' };
// key, cat_key, name, area, price_vnd, seats, days-from-now, hh:mm
const ROWS = [
  ['bepnho', 'supper', 'Bếp Nhỏ №12', 'Bình Thạnh', 900000, 3, 2, '19:00'], ['comnha', 'supper', 'Cơm Nhà Mai', 'Quận 3', 700000, 5, 3, '19:30'],
  ['bandai', 'supper', 'Bàn Dài №4', 'Thảo Điền', 1200000, 2, 4, '19:00'], ['phokhuya', 'supper', 'Phở Khuya', 'Quận 4', 350000, 9, 5, '23:00'],
  ['vuonsau', 'supper', 'Vườn Sau', 'Gò Vấp', 850000, 6, 6, '18:00'],
  ['orbit', 'fashion', 'ORBIT: Afterlight', 'Quận 1', 400000, 23, 2, '20:00'], ['aeie', 'fashion', 'AEIE: Mở Xưởng', 'Thảo Điền', 300000, 18, 3, '16:00'],
  ['fanci', 'fashion', 'Fanci: Đêm Thử Đồ', 'Quận 1', 500000, 12, 4, '19:00'], ['compound', 'fashion', 'Compound: Sân Thượng', 'Quận 1', 250000, 31, 5, '17:00'],
  ['motlop', 'fashion', 'Chỉ Một Lớp', 'Quận 3', 600000, 8, 6, '19:30'],
  ['vungtrang', 'gallery', 'Vùng Trắng', 'Thảo Điền', 150000, 41, 2, '18:00'], ['sonmai', 'gallery', 'Đối Thoại Sơn Mài', 'Quận 1', 100000, 26, 3, '18:30'],
  ['khongnguoi', 'gallery', 'Ảnh Không Người', 'Quận 3', 120000, 35, 4, '17:00'], ['noigiay', 'gallery', 'Nói Chuyện: Giấy', 'Quận 1', 80000, 20, 5, '19:00'],
  ['phong302', 'gallery', 'Phòng 302', 'Quận 5', 150000, 14, 6, '15:00'],
  ['chieucham', 'music', 'Chiều Chậm', 'Quận 1', 0, 58, 2, '15:00'], ['jazzgac', 'music', 'Jazz Ở Gác', 'Quận 1', 250000, 16, 3, '21:00'],
  ['bangcoi', 'music', 'Băng Cối', 'Quận 3', 180000, 22, 4, '20:00'], ['modular', 'music', 'Đêm Modular', 'Quận 4', 200000, 27, 5, '21:30'],
  ['pianomuon', 'music', 'Piano Muộn', 'Quận 1', 300000, 11, 6, '22:00'],
];
const pad = (n) => String(n).padStart(2, '0');

export async function seedFixtures(admin) {
  assertIsolated();
  // dedicated synthetic owner (find-or-create); organizers.owner_id references profiles(id) which the signup trigger creates
  let ownerId;
  ownerId = (await admin.from('email_registrations').select('auth_user_id').eq('email', OWNER_EMAIL).maybeSingle()).data?.auth_user_id;
  if (!ownerId) {
    const { data, error } = await admin.auth.admin.createUser({ email: OWNER_EMAIL, password: 'E2e-fixture-owner-Not-A-Real-Pw1', email_confirm: true, user_metadata: { display_name: 'E2E Fixture Owner' } });
    if (error) throw new Error('fixture owner: ' + error.message);
    ownerId = data.user.id;
  }
  const orgs = ROWS.map(([key, , name]) => ({ id: `org_${key}`, owner_id: ownerId, user_id: ownerId, name: `E2E Fixture ${name}`, about: 'Synthetic organizer for the local E2E stack.', verified: false }));
  let r = await admin.from('organizers').upsert(orgs); if (r.error) throw new Error('fixture organizers: ' + r.error.message);
  await admin.from('events').delete().like('id', `${FIXTURE_PREFIX}%`); // legacy prefixed ids from an earlier revision of this seeder
  const now = new Date();
  const events = ROWS.map(([key, cat, name, area, price, seats, days, hm], i) => {
    const { lat, lng } = coordsFor(i);
    const [hh, mm] = hm.split(':').map(Number);
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + (i === FIRST ? 1 : 2 + (i % 5)), hh, mm);
    return {
      id: key, key, slug: key, organizer_id: `org_${key}`,
      name, category: CAT[cat], cat_key: cat, cat_label: CAT[cat], description: 'E2E-FIXTURE synthetic event for the local E2E stack.', area, lat, lng,
      starts_at: d.toISOString(), event_date: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`, event_time: `${hm}:00`,
      price_vnd: price, price_cents: price * 100, capacity: seats + 10, seats_remaining: seats, status: 'live', visibility: 'public', approval: 'instant', country_code: 'VN',
    };
  });
  r = await admin.from('events').upsert(events); if (r.error) throw new Error('fixture events: ' + r.error.message);
  await admin.from('organizers').delete().like('id', `${FIXTURE_PREFIX}org-%`); // legacy organizer ids from an earlier revision (events were just re-pointed)
  // One event_photos row per event (Pulse's ranked query INNER JOINs event_photos, so an event without one never appears on Pulse).
  // Only the DB row: no storage object is uploaded, so the photo URL 404s locally - these rows prove Pulse ranking/loader wiring
  // exists, not that an image renders.
  const uuid = (k) => { const h = createHash('md5').update(`e2e-fixture-photo-${k}`).digest('hex'); return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`; };
  r = await admin.from('event_photos').upsert(ROWS.map(([key]) => ({ id: uuid(key), event_id: key, storage_path: `event-photos/${key}/cover.jpg`, sort_order: 0 })));
  if (r.error) throw new Error('fixture event_photos: ' + r.error.message);
  // Migration 010 (the generic sample data every fresh DB gets) leaves evt_001/002/004 as live 2024 rows (HCMC, Hanoi, Da Lat).
  // The specs describe a DB whose public discovery set is only the migration-020 demo catalogue: Home's feed sorts discovery
  // events by starts_at ascending and includes 'ended', so a 2024 row is always Home's first card (Task 7 then opens an event
  // the Map's live-only query cannot show), and as the earliest Map row it becomes the off-screen `.first()` pin.
  // Hide those three sample rows from public discovery (draft, same as the seed's own evt_003). Local DB only; reversible.
  r = await admin.from('events').update({ status: 'draft' }).in('id', ['evt_001', 'evt_002', 'evt_004']);
  if (r.error) throw new Error('fixture sample-row hide: ' + r.error.message);
  return { owner: ownerId, organizers: orgs.length, events: events.length };
}
