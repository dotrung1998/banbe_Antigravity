// Address search for Create Event / surveys on the web. The browser used to call nominatim.openstreetmap.org
// directly; from some networks (seen in Vietnam) that request fails outright, and the public Nominatim
// instance also asks callers to identify themselves (a User-Agent, which a browser cannot set). So the
// search runs here, server-side, over two OpenStreetMap geocoders:
//
//   Nominatim  — the reference OSM search, best structured `address` breakdown.
//   Photon     — a separate index over the same OSM data; often returns venues/house numbers Nominatim's
//                ranking drops, and keeps working when Nominatim rate-limits us.
//
// Both are queried in parallel, merged, de-duplicated and re-ranked toward the caller's neighbourhood
// (a `lat`/`lon` bias; HCMC when none is given). Nothing is restricted by country: the app supports US
// venues too, so `countrycodes=vn` is deliberately gone — Vietnam is a preference, not a filter.
//
//   GET /api/geocode?q=<text>&lat=<n>&lon=<n>   ->  [ Nominatim-shaped rows ]  (what shapeAddressSuggestion expects)
//
// Rows are cached briefly per query so repeated typing/backspacing does not spend the providers' rate limits.
const UA = 'banbe.app/1.0 (address search; contact doqanh0906@gmail.com)';
const HCMC = { lat: 10.7769, lon: 106.7009 };
const VIEWBOX = '106.45,11.03,106.95,10.53'; // left,top,right,bottom — a bias, never `bounded=1`
const TIMEOUT_MS = 6000;
const MAX_ROWS = 8;
const CACHE_TTL_MS = 10 * 60 * 1000;
const CACHE_MAX = 200;

const cache = new Map();

async function getJson(url) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT_MS);
  try {
    const r = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/json', 'Accept-Language': 'vi,en;q=0.7' }, signal: ctl.signal });
    if (!r.ok) throw new Error(`HTTP_${r.status}`);
    return await r.json();
  } finally { clearTimeout(timer); }
}

// Nominatim asks for at most one request per second from one client. The serverless instances are shared, so
// only one call per instance is allowed in flight; while it runs, Photon answers and the second call simply
// skips Nominatim instead of earning a 429.
let nominatimBusy = false;
async function nominatimIfIdle(q) {
  if (nominatimBusy) return null;
  nominatimBusy = true;
  try { return await nominatim(q); } finally { nominatimBusy = false; }
}

async function nominatim(q) {
  const p = new URLSearchParams({
    format: 'jsonv2', addressdetails: '1', limit: '10', dedupe: '1',
    'accept-language': 'vi,en', viewbox: VIEWBOX, q,
  });
  const rows = await getJson(`https://nominatim.openstreetmap.org/search?${p}`);
  if (!Array.isArray(rows)) throw new Error('BAD_SHAPE');
  return rows;
}

// Photon feature -> the Nominatim row fields the client reads. `addresstype` is carried through so the
// client can tell an exact house/venue from a street-level or area-only match.
function fromPhoton(f) {
  const pr = f.properties || {};
  const [lon, lat] = f.geometry?.coordinates || [];
  const street = [pr.housenumber, pr.street].filter(Boolean).join(' ');
  // Keep the venue name too when it differs from its street, so the row reads "The Workshop Coffee, 27 Ngô Đức Kế…".
  const parts = [pr.name && street && fold(pr.name) !== fold(street) ? pr.name : null, street || pr.name, pr.district, pr.city || pr.county, pr.state, pr.country].filter(Boolean);
  return {
    place_id: pr.osm_id ? `${pr.osm_type || 'x'}${pr.osm_id}` : undefined,
    lat: String(lat), lon: String(lon), name: pr.name || '',
    addresstype: pr.type || '', type: pr.type || '',
    display_name: parts.join(', '),
    address: {
      house_number: pr.housenumber, road: pr.street, suburb: pr.locality || pr.district, city_district: pr.district,
      city: pr.city || pr.county, state: pr.state, postcode: pr.postcode, country_code: (pr.countrycode || '').toLowerCase(),
    },
  };
}

async function photon(q, bias) {
  const p = new URLSearchParams({ q, limit: '10', lat: String(bias.lat), lon: String(bias.lon) });
  const data = await getJson(`https://photon.komoot.io/api/?${p}`);
  return (data.features || []).map(fromPhoton);
}

// ---------- ranking ----------
// Vietnamese diacritics are folded so "nguyen van dau" still matches "Nguyễn Văn Đậu".
const fold = (v) => String(v || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/đ/gi, 'd').toLowerCase();
const STOP = new Set(['so', 'no', 'the', 'and', 'vietnam', 'viet', 'nam', 'hcm', 'tphcm', 'pho', 'ho', 'chi', 'minh', 'vn']);
function tokens(q) {
  // Keep house numbers even when single-digit ("Số 5 Lý Tự Trọng"): they are what makes a query an address.
  return [...new Set(fold(q).split(/[^a-z0-9]+/).filter(t => (t.length > 1 || /^\d+$/.test(t)) && !STOP.has(t)))];
}
const EXACT_TYPES = new Set(['house', 'building', 'apartments', 'residential', 'place', 'amenity', 'shop', 'tourism', 'leisure', 'office', 'craft', 'healthcare', 'historic', 'highway']);
const AREA_TYPES = new Set(['city', 'town', 'village', 'suburb', 'district', 'county', 'state', 'region', 'country', 'municipality', 'neighbourhood', 'quarter', 'administrative']);

const roughKm = (aLat, aLon, bLat, bLon) => {
  const dLat = (aLat - bLat) * 111;
  const dLon = (aLon - bLon) * 111 * Math.cos((bLat * Math.PI) / 180);
  return Math.hypot(dLat, dLon);
};

// Whole-token overlap, not substring: "88" must not match "885".
function coverageOf(row, qTokens) {
  const textTokens = new Set(fold([row.display_name, row.name].filter(Boolean).join(' ')).split(/[^a-z0-9]+/).filter(Boolean));
  const hits = qTokens.filter(t => textTokens.has(t)).length;
  return qTokens.length ? hits / qTokens.length : 0;
}

// "Số 5 Lý Tự Trọng" is an address query: a school NAMED Lý Tự Trọng on another street is a false
// friend. When the query carries a number, the road/street has to carry the words.
function roadCoverageOf(row, qTokens) {
  const significant = qTokens.filter(t => !/^\d+$/.test(t));
  if (!significant.length) return 1;
  const addr = row.address || {};
  // Some OSM alleys have no `street` tag at all: their name IS the address ("Hẻm 45/43/12 Nguyễn Văn Đậu").
  const type = String(row.addresstype || row.type || '').toLowerCase();
  const nameIsStreet = type === 'street' || /^(hẻm|hem|ngõ|ngo|ngách|ngach|số|so)\b/i.test(row.name || '');
  const roadTokens = new Set(fold([addr.road, addr.house_number, nameIsStreet ? row.name : null, addr.suburb, addr.city_district].filter(Boolean).join(' ')).split(/[^a-z0-9]+/).filter(Boolean));
  if (!roadTokens.size) return 0;
  return significant.filter(t => roadTokens.has(t)).length / significant.length;
}

function scoreRow(row, qTokens, coverage, roadCoverage, bias) {
  const addr = row.address || {};
  const type = String(row.addresstype || row.type || '').toLowerCase();
  const numeric = qTokens.some(t => /^\d+$/.test(t));
  let score = 0;
  // A house number is only evidence when the query asked for that exact number; a random house
  // elsewhere is not a better answer than the street that was typed.
  if (addr.house_number) score += qTokens.includes(fold(addr.house_number)) ? 40 : 8;
  if (EXACT_TYPES.has(type)) score += 20;
  if (AREA_TYPES.has(type)) score -= 18;
  const cc = String(addr.country_code || '').toLowerCase();
  if (cc === 'vn') score += 12;
  const lat = parseFloat(row.lat), lon = parseFloat(row.lon);
  if (Number.isFinite(lat) && Number.isFinite(lon)) {
    score += Math.max(0, 18 - roughKm(lat, lon, bias.lat, bias.lon) / 14);
  }
  // Relevance dominates: Photon in particular will happily return a house number on an unrelated
  // street, which used to outrank the street the host actually typed.
  score += coverage * (numeric ? 18 : 36);
  if (numeric) score += roadCoverage * 30;
  if (coverage < 0.6) score -= 60;
  return score;
}

function dedupeAndRank(rows, q, bias) {
  const qTokens = tokens(q);
  const seenPlace = new Set();
  const seenPoint = new Set();
  const out = [];
  for (const row of rows) {
    if (!row || row.lat == null || row.lon == null) continue;
    const place = String(row.place_id || '');
    const point = `${Number(row.lat).toFixed(4)},${Number(row.lon).toFixed(4)}`;
    if ((place && seenPlace.has(place)) || seenPoint.has(point)) continue;
    const coverage = coverageOf(row, qTokens);
    // A multi-word query that shares almost nothing with the result is provider noise, not a suggestion.
    if (qTokens.length >= 3 ? coverage < 0.7 : qTokens.length === 2 ? coverage < 0.4 : false) continue;
    const numeric = qTokens.some(t => /^\d+$/.test(t));
    const roadCoverage = numeric ? roadCoverageOf(row, qTokens) : 1;
    if (numeric && qTokens.filter(t => !/^\d+$/.test(t)).length >= 2 && roadCoverage < 0.34) {
      // "12 Nguyễn Văn Đậu" must not surface a house number on Lê Đức Thọ just because a school there
      // happens to be named Nguyễn Văn Đậu.
      continue;
    }
    if (place) seenPlace.add(place);
    seenPoint.add(point);
    out.push({ row, score: scoreRow(row, qTokens, coverage, roadCoverage, bias) });
  }
  out.sort((a, b) => b.score - a.score);
  // A strong local match makes other continents noise. When the best row is far away, nothing is dropped:
  // that is a legitimate search for a place outside the bias (a US venue searched from Vietnam, say).
  const kmOf = (r) => roughKm(parseFloat(r.lat), parseFloat(r.lon), bias.lat, bias.lon);
  const local = out.length > 0 && kmOf(out[0].row) < 150;
  const kept = local ? out.filter(x => kmOf(x.row) < 1500) : out;
  return kept.slice(0, MAX_ROWS).map(x => x.row);
}

// Strip noise the geocoders choke on: a leading "Số", a trailing country, doubled commas.
function cleanQuery(q) {
  return q
    .replace(/\s+/g, ' ')
    .replace(/^(số|so)\s+/i, '')
    .replace(/[,\s]+(việt nam|vietnam)$/i, '')
    .replace(/\s*,\s*,+/g, ',')
    .trim();
}

export default async function handler(req, res) {
  if (req.method !== 'GET') { res.setHeader('Allow', 'GET'); return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' }); }
  const raw = Array.isArray(req.query?.q) ? req.query.q[0] : req.query?.q;
  const q = typeof raw === 'string' ? cleanQuery(raw.trim().slice(0, 200)) : '';
  if (q.length < 3) return res.status(400).json({ error: 'QUERY_TOO_SHORT' });

  const numParam = (v) => (typeof v === 'string' ? parseFloat(v) : NaN);
  const lat = numParam(Array.isArray(req.query?.lat) ? req.query.lat[0] : req.query?.lat);
  const lon = numParam(Array.isArray(req.query?.lon) ? req.query.lon[0] : req.query?.lon);
  const bias = Number.isFinite(lat) && Number.isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180 ? { lat, lon } : HCMC;

  const key = `${q.toLowerCase()}|${bias.lat.toFixed(1)},${bias.lon.toFixed(1)}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) {
    res.setHeader('Cache-Control', 'public, s-maxage=86400, stale-while-revalidate=604800');
    return res.status(200).json(hit.rows);
  }

  // Both providers at once: Nominatim for structure, Photon for coverage. One may fail without taking the search down.
  const [nom, pho] = await Promise.allSettled([nominatimIfIdle(q), photon(q, bias)]);
  let rows = null;
  if (nom.status === 'fulfilled' || pho.status === 'fulfilled') {
    rows = [
      ...(nom.status === 'fulfilled' && nom.value ? nom.value : []),
      ...(pho.status === 'fulfilled' ? pho.value : []),
    ];
  } else {
    console.warn('geocode: both providers failed:', nom.reason?.message, pho.reason?.message);
  }

  // A query with a typo/extra ward can miss entirely; one cleaned retry is worth it before saying "not found".
  if (rows && rows.length === 0) {
    const clean = cleanQuery(q);
    if (clean !== q && clean.length >= 3) {
      try { rows = await nominatimIfIdle(clean); } catch { /* keep the empty result */ }
    }
  }

  // Providers unreachable: an older answer for this same query is still better than an error+retry dead end.
  if (rows === null && hit) {
    res.setHeader('Cache-Control', 'public, s-maxage=60, stale-while-revalidate=600');
    return res.status(200).json(hit.rows);
  }
  if (rows === null) return res.status(502).json({ error: 'GEOCODE_UNAVAILABLE' });
  const ranked = dedupeAndRank(rows, q, bias);

  cache.set(key, { at: Date.now(), rows: ranked });
  if (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value);

  res.setHeader('Cache-Control', 'public, s-maxage=86400, stale-while-revalidate=604800');
  return res.status(200).json(ranked);
}
