// Address search for Create Event / surveys on the web. The browser used to call nominatim.openstreetmap.org
// directly; from some networks (seen in Vietnam) that request fails outright, and the public Nominatim
// instance also asks callers to identify themselves (a User-Agent, which a browser cannot set). So the
// search runs here, with Photon (also OpenStreetMap data) as a fallback when Nominatim is unreachable.
//
//   GET /api/geocode?q=<text>   ->  [ Nominatim-shaped rows ]  (what shapeAddressSuggestion expects)
//
// Biased, not restricted, toward Ho Chi Minh City: the same region iOS gives MKLocalSearch.
const UA = 'banbe.app/1.0 (address search; contact doqanh0906@gmail.com)';
const HCMC = { lat: 10.7769, lon: 106.7009 };
const VIEWBOX = '106.45,11.03,106.95,10.53'; // left,top,right,bottom
const TIMEOUT_MS = 6000;

async function getJson(url) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT_MS);
  try {
    const r = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/json', 'Accept-Language': 'vi,en;q=0.5' }, signal: ctl.signal });
    if (!r.ok) throw new Error(`HTTP_${r.status}`);
    return await r.json();
  } finally { clearTimeout(timer); }
}

async function nominatim(q) {
  const p = new URLSearchParams({ format: 'jsonv2', addressdetails: '1', limit: '5', countrycodes: 'vn', 'accept-language': 'vi', viewbox: VIEWBOX, q });
  const rows = await getJson(`https://nominatim.openstreetmap.org/search?${p}`);
  if (!Array.isArray(rows)) throw new Error('BAD_SHAPE');
  return rows;
}

// Photon feature -> the Nominatim row fields the client reads.
function fromPhoton(f) {
  const pr = f.properties || {};
  const [lon, lat] = f.geometry?.coordinates || [];
  const parts = [pr.housenumber && pr.street ? `${pr.housenumber} ${pr.street}` : pr.name, pr.district, pr.city || pr.county, pr.state].filter(Boolean);
  return {
    place_id: pr.osm_id ? `${pr.osm_type || 'x'}${pr.osm_id}` : undefined,
    lat: String(lat), lon: String(lon), name: pr.name || '', display_name: parts.join(', '),
    address: {
      house_number: pr.housenumber, road: pr.street, suburb: pr.locality || pr.district, city_district: pr.district,
      city: pr.city || pr.county, state: pr.state, postcode: pr.postcode, country_code: (pr.countrycode || '').toLowerCase(),
    },
  };
}

async function photon(q) {
  const p = new URLSearchParams({ q, limit: '5', lat: String(HCMC.lat), lon: String(HCMC.lon) });
  const data = await getJson(`https://photon.komoot.io/api/?${p}`);
  return (data.features || []).filter(f => (f.properties?.countrycode || '').toUpperCase() === 'VN').map(fromPhoton);
}

export default async function handler(req, res) {
  if (req.method !== 'GET') { res.setHeader('Allow', 'GET'); return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' }); }
  const raw = Array.isArray(req.query?.q) ? req.query.q[0] : req.query?.q;
  const q = typeof raw === 'string' ? raw.trim().slice(0, 200) : '';
  if (q.length < 3) return res.status(400).json({ error: 'QUERY_TOO_SHORT' });
  let rows = null;
  try { rows = await nominatim(q); } catch (e) { console.warn('geocode: nominatim failed:', e.message); }
  if (!rows || !rows.length) {
    try { const alt = await photon(q); if (alt.length || rows === null) rows = alt; } catch (e) { console.warn('geocode: photon failed:', e.message); }
  }
  if (rows === null) return res.status(502).json({ error: 'GEOCODE_UNAVAILABLE' });
  res.setHeader('Cache-Control', 'public, s-maxage=86400, stale-while-revalidate=604800');
  return res.status(200).json(rows);
}
