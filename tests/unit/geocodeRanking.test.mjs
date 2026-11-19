// Offline tests for api/_lib/handlers/geocode.js's pure ranking helpers. No network: the fixtures are
// Nominatim/Photon-shaped rows copied from real responses (Lý Tự Trọng, Lê Lợi, Chợ Bến Thành), so a change
// that lets a same-named school outrank the street, or a foreign address outrank the local one, fails here.
import test from 'node:test';
import assert from 'node:assert/strict';
import { cleanQuery, tokens, dedupeAndRank, roadCoverageOf } from '../../api/_lib/handlers/geocode.js';

const HCMC = { lat: 10.7769, lon: 106.7009 };
let seq = 0;

function row({
  name = '', display = '', type = '', house = '', road = '',
  suburb = 'Bến Thành', city = 'Thành phố Hồ Chí Minh', lat = 10.772, lon = 106.698, cc = 'vn',
} = {}) {
  seq += 1;
  return {
    place_id: `fixture-${seq}`,
    name,
    display_name: display || [name, house && road ? `${house} ${road}` : road, suburb, city].filter(Boolean).join(', '),
    lat: String(lat),
    lon: String(lon),
    addresstype: type,
    type,
    address: { house_number: house, road, suburb, city, city_district: suburb, country_code: cc },
  };
}

test('cleanQuery strips the Vietnamese address prefix and trailing country', () => {
  assert.equal(cleanQuery('  Số   12 Nguyễn Văn Đậu, Việt Nam '), '12 Nguyễn Văn Đậu');
  assert.equal(cleanQuery('12 Nguyễn Văn Đậu,  , Quận 1'), '12 Nguyễn Văn Đậu, Quận 1');
  assert.equal(cleanQuery('so 5 Ly Tu Trong'), '5 Ly Tu Trong');
});

test('tokens folds diacritics and keeps single-digit house numbers', () => {
  assert.deepEqual(tokens('Số 5 Lý Tự Trọng'), ['5', 'ly', 'tu', 'trong']);
  assert.deepEqual(tokens('12 Nguyễn Văn Đậu'), ['12', 'nguyen', 'van', 'dau']);
});

test('an addressed query prefers the street it names over a school named after it', () => {
  // The real Photon trap: "Trường THCS Lý Tự Trọng" sits on Lê Đức Thọ, not on Lý Tự Trọng.
  const school = row({ name: 'Trường Trung học cơ sở Lý Tự Trọng', type: 'house', house: '578', road: 'Lê Đức Thọ', lat: 10.79, lon: 106.68 });
  const street = row({ name: 'Đường Lý Tự Trọng', type: 'tertiary', road: 'Lý Tự Trọng', lat: 10.773, lon: 106.699 });
  const out = dedupeAndRank([school, street], 'Số 5 Lý Tự Trọng', HCMC);

  assert.equal(out.length, 1, 'the school is not an address suggestion for this query');
  assert.match(out[0].name, /Lý Tự Trọng/);
  assert.equal(out[0].address.road, 'Lý Tự Trọng');
});

test('an exact house number outranks the bare street', () => {
  const exact = row({ name: 'Capital Building', type: 'building', house: '123', road: 'Lê Lợi', lat: 10.7735, lon: 106.6995 });
  const street = row({ name: 'Lê Lợi', type: 'secondary', road: 'Lê Lợi', lat: 10.771, lon: 106.7 });
  const out = dedupeAndRank([street, exact], '123 Lê Lợi', HCMC);

  assert.equal(out[0].address.house_number, '123');
  assert.equal(out[0].name, 'Capital Building');
});

test('a local match drops other continents when the query is local', () => {
  const hcmc = row({ name: 'Lê Lợi', type: 'secondary', road: 'Lê Lợi' });
  const france = row({
    name: '123 Lotissement Le Clos de La Boire', type: 'house', house: '123',
    road: 'Lotissement Le Clos de La Boire', suburb: 'Les Bouchardières', city: 'Mauges-sur-Loire',
    lat: 47.35, lon: -0.83, cc: 'fr',
  });
  const out = dedupeAndRank([france, hcmc], '123 Lê Lợi', HCMC);

  assert.equal(out.length, 1);
  assert.equal(out[0].address.country_code, 'vn');
});

test('a venue query ranks the exact market above a station named after another market', () => {
  const market = row({ name: 'Chợ Bến Thành', type: 'amenity', road: 'Công trường Quách Thị Trang', lat: 10.7725, lon: 106.698 });
  const busStation = row({ name: 'Bến xe Chợ Lớn', type: 'house', road: 'Hồng Bàng', suburb: 'Bình Tây', lat: 10.754, lon: 106.66 });
  const out = dedupeAndRank([busStation, market], 'Chợ Bến Thành', HCMC);

  assert.equal(out[0].name, 'Chợ Bến Thành');
});

test('the same point from both providers is offered once', () => {
  const a = row({ name: 'The Workshop Coffee', type: 'amenity', house: '27', road: 'Ngô Đức Kế' });
  const b = row({ name: 'The Workshop Coffee', type: 'amenity', house: '27', road: 'Ngô Đức Kế' });
  b.lat = a.lat; b.lon = a.lon;
  const out = dedupeAndRank([a, b], 'The Workshop Coffee', HCMC);

  assert.equal(out.length, 1);
});

test('roadCoverage gives an alley name the same standing as a road tag', () => {
  const alley = row({ name: 'Hẻm 45/43/12 Nguyễn Văn Đậu', type: 'street', road: '', lat: 10.79, lon: 106.68 });
  const tokensOfQuery = tokens('12 Nguyễn Văn Đậu');
  assert.equal(roadCoverageOf(alley, tokensOfQuery), 1);
});
