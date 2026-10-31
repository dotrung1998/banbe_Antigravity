// Presents an Apple MapKit JS map through the small slice of the MapLibre API that MapExplore.jsx uses
// (flyTo/easeTo/getZoom/getCenter/getBounds/on/remove + Marker), so the screen has ONE code path and
// the OpenStreetMap map stays the fallback. Zoom levels are the web-mercator ones MapExplore already
// uses; they are converted to/from MapKit's coordinate span for the current container width.

const TILE = 256;

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

export function zoomToLngSpan(zoom, widthPx) { return (360 * Math.max(1, widthPx)) / (TILE * Math.pow(2, zoom)); }
export function lngSpanToZoom(lngSpan, widthPx) { return Math.log2((360 * Math.max(1, widthPx)) / (TILE * Math.max(1e-9, lngSpan))); }

export function createMapKitMap(mapkit, { container, center, zoom, theme }) {
  const widthPx = () => container.clientWidth || 390;
  const heightPx = () => container.clientHeight || 700;
  const spanFor = (z) => {
    const lng = zoomToLngSpan(z, widthPx());
    // Same pixels-per-degree vertically (mercator), shrunk by cos(lat) is close enough at city scale.
    return new mapkit.CoordinateSpan(lng * (heightPx() / widthPx()), lng);
  };
  const regionFor = (c, z) => new mapkit.CoordinateRegion(new mapkit.Coordinate(c.lat, c.lng), spanFor(z));

  const map = new mapkit.Map(container, {
    region: regionFor(center, zoom),
    showsCompass: mapkit.FeatureVisibility.Hidden,
    showsZoomControl: true,
    showsMapTypeControl: false,
    showsPointsOfInterest: true,
    colorScheme: theme === 'dark' ? mapkit.Map.ColorSchemes.Dark : mapkit.Map.ColorSchemes.Light,
  });

  const listeners = { movestart: [], moveend: [], click: [] };
  // MapKit JS doesn't say whether a region change came from a gesture: the Map screen treats a start with no
  // pending programmatic reason as the user's (src/lib/mapDiscovery.js).
  const onStart = () => listeners.movestart.forEach(fn => fn({}));
  const onEnd = () => listeners.moveend.forEach(fn => fn());
  const onTap = () => listeners.click.forEach(fn => fn());
  map.addEventListener('region-change-start', onStart);
  map.addEventListener('region-change-end', onEnd);
  map.addEventListener('single-tap', onTap);

  const setPadding = (p) => {
    if (!p) return;
    map.padding = new mapkit.Padding(p.top || 0, p.right || 0, p.bottom || 0, p.left || 0);
  };

  const api = {
    __isMapKit: true,
    getZoom: () => lngSpanToZoom(map.region.span.longitudeDelta, widthPx()),
    getCenter: () => ({ lat: map.region.center.latitude, lng: map.region.center.longitude }),
    getBounds: () => {
      const { center, span } = map.region;
      const north = clamp(center.latitude + span.latitudeDelta / 2, -90, 90), south = clamp(center.latitude - span.latitudeDelta / 2, -90, 90);
      const east = center.longitude + span.longitudeDelta / 2, west = center.longitude - span.longitudeDelta / 2;
      return { getNorth: () => north, getSouth: () => south, getEast: () => east, getWest: () => west };
    },
    // MapLibre-style camera moves: { center: [lng, lat], zoom, padding, duration }. MapKit animates on its own
    // schedule, so `duration` is ignored.
    flyTo(opts = {}) { api.easeTo(opts); },
    easeTo(opts = {}) {
      setPadding(opts.padding);
      const c = opts.center ? { lat: opts.center[1], lng: opts.center[0] } : api.getCenter();
      const z = opts.zoom != null ? opts.zoom : api.getZoom();
      map.setRegionAnimated(regionFor(c, z), true);
    },
    panBy() {},
    resize() { /* MapKit tracks its container size itself */ },
    setColorScheme(mode) {
      map.colorScheme = mode === 'dark' ? mapkit.Map.ColorSchemes.Dark : mapkit.Map.ColorSchemes.Light;
    },
    on(type, fn) { (listeners[type] || (listeners[type] = [])).push(fn); },
    addControl() {},
    remove() {
      map.removeEventListener('region-change-start', onStart);
      map.removeEventListener('region-change-end', onEnd);
      map.removeEventListener('single-tap', onTap);
      map.destroy();
    },
    __native: map,
  };

  /** Drop-in for `new maplibregl.Marker({ element })` (only setLngLat/addTo/remove are used). */
  api.Marker = class MapKitMarker {
    constructor({ element }) { this.element = element; this.coord = null; this.annotation = null; }
    setLngLat([lng, lat]) {
      this.coord = new mapkit.Coordinate(lat, lng);
      if (this.annotation) this.annotation.coordinate = this.coord;
      return this;
    }
    addTo() {
      if (!this.annotation) {
        this.annotation = new mapkit.Annotation(this.coord, () => this.element, { enabled: false, calloutEnabled: false, anchorOffset: new DOMPoint(0, 0) });
        map.addAnnotation(this.annotation);
      }
      return this;
    }
    remove() {
      if (this.annotation) { map.removeAnnotation(this.annotation); this.annotation = null; }
    }
  };
  return api;
}

/**
 * MapKit JS place -> the suggestion shape BanBeContext's shapeAddressSuggestion produces, mirroring iOS
 * `AddressSuggestion(mapItem:)` field for field so both platforms store the same thing.
 */
export function shapeMapKitPlace(place) {
  const t = v => String(v || '').trim();
  const houseNumber = t(place.subThoroughfare), street = t(place.thoroughfare), venueName = t(place.name);
  const district = t(place.subLocality) || t(place.locality);
  const iso = t(place.countryCode).toUpperCase();
  const adminArea = t(place.administrativeArea), locality = t(place.locality);
  const city = iso === 'US' && locality ? locality : adminArea;
  let addressLine, isVenue = false;
  if (houseNumber && street) addressLine = `${houseNumber} ${street}`;
  else if (venueName) { addressLine = venueName; isVenue = true; } else return null;
  if (!district || !city) return null;
  const lat = place.coordinate?.latitude, lng = place.coordinate?.longitude;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  const sub = t(place.subLocality);
  return {
    id: `${lat},${lng},${addressLine}`, addressLine, district, city, postalCode: t(place.postCode), isVenue, lat, lng,
    countryCode: iso || null, stateProvince: adminArea.slice(0, 100) || null,
    neighborhood: sub && sub.toLowerCase() !== district.toLowerCase() ? sub.slice(0, 100) : null,
    // The place's IANA zone when MapKit gives one (migration 195 takes it for multi-zone US states); else null.
    timeZone: typeof place.timeZone === 'string' ? place.timeZone : (t(place.timeZone?.identifier) || null),
    label: [addressLine, district, city].filter(Boolean).join(', '),
  };
}

/** Promise wrapper over `mapkit.Search`, biased to HCMC like iOS's MKLocalSearch region. */
export function mapKitSearch(mapkit, query) {
  return new Promise((resolve, reject) => {
    const region = new mapkit.CoordinateRegion(new mapkit.Coordinate(10.7769, 106.7009), new mapkit.CoordinateSpan(0.5, 0.5));
    const search = new mapkit.Search({ region, getsUserLocation: false, includeAddresses: true, includePointsOfInterest: true });
    search.search(query, (error, data) => (error ? reject(error) : resolve((data?.places || []).map(shapeMapKitPlace).filter(Boolean))));
  });
}
