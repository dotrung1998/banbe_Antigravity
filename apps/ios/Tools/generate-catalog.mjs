// Emits apps/ios/BanbeApp/Resources/events.json from the web app's own
// catalogue (src/data/events.js), so the iOS feed shows exactly the same
// events, copy, photos and organizer detail as the web feed instead of a
// hand-transcribed second copy that drifts.
//
// Run from the repo root after changing src/data/events.js:
//   node apps/ios/Tools/generate-catalog.mjs
import { writeFileSync } from 'node:fs';
import { EVENTS } from '../../../src/data/events.js';

const rows = EVENTS.map(e => ({
  key: e.key,
  catKey: e.catKey,
  cat: e.cat,
  cat2Key: e.cat2Key,
  catDisplay: e.catDisplay,
  name: e.name,
  img: e.img,
  lat: e.lat,
  lng: e.lng,
  meta: e.meta,
  where: e.where,
  when: e.when,
  price: e.price,
  seats: e.seats,
  seatsLong: e.seatsLong,
  urgent: e.urgent,
  desc: e.desc,
  included: e.included,
  host: e.host,
  hostShort: e.hostShort,
  greeting: e.greeting,
  gallery: e.gallery,
  orgGallery: e.orgGallery,
  orgName: e.orgName,
  orgIg: e.orgIg,
  orgDesc: e.orgDesc,
  orgSince: e.orgSince,
  orgCount: e.orgCount,
  orgTrusted: e.orgTrusted,
  cancelled: e.cancelled,
  cancelledHoursAgo: e.cancelledHoursAgo,
  endedHoursAgo: e.endedHoursAgo,
  soldOut: e.soldOut,
  inviteOnly: e.inviteOnly,
  until: e.until,
  untilLabel: e.untilLabel,
}));

const out = new URL('../BanbeApp/Resources/events.json', import.meta.url);
writeFileSync(out, JSON.stringify(rows, null, 2) + '\n');
console.log(`Wrote ${rows.length} events to ${out.pathname}`);
