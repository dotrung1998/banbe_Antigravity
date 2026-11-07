# 42 — Apple MapKit JS on the web (implemented, OFF by default)

**Status:** IMPLEMENTED, DISABLED. Nothing changes until the switch below is turned on; OpenStreetMap stays the fallback.

- Map (Map Explore) and Create Event / survey address search use MapKit JS when enabled, so web matches iOS (MapKit + MKLocalSearch).
- Off path: MapLibre + OpenFreeMap, address search via `/api/geocode` (Nominatim, Photon fallback), credit "© OpenStreetMap contributors".
- On path: `src/lib/mapkit.js` (loader) -> `src/lib/mapkitAdapter.js` (MapLibre-shaped adapter incl. `Marker`, `shapeMapKitPlace` mirroring iOS `AddressSuggestion(mapItem:)`, `mapKitSearch`). MapExplore.jsx has ONE code path via `markerCtorRef`; the theme follows `setColorScheme`.
- Any failure (script blocked, token 503, auth error) resolves `null` and the OpenStreetMap path is used; MapKit search errors fall back to `/api/geocode` too.

## To turn it on (needs an Apple Developer Program membership)
1. developer.apple.com > Certificates, IDs & Profiles: create a **Maps ID** and a **Maps key** (.p8); note Team ID + Key ID.
2. Vercel env: `MAPKIT_TEAM_ID`, `MAPKIT_KEY_ID`, `MAPKIT_PRIVATE_KEY` (the .p8 contents), then `VITE_MAPKIT_ENABLED=true` (build-time) and redeploy.
3. Token endpoint: `/api/mapkit-token` (inside `api/calendar.js`, `?op=mapkit-token`, Hobby cap = 12 functions). Tokens last 1h and carry the page `origin`.

## Not verified
Never run against real Apple servers (no credentials yet): the adapter's camera/zoom conversion, annotation anchoring/size and the tap-to-deselect event (`single-tap`) need a visual pass on first enable. Unit tests cover only the pure math/shaping (`tests/unit/mapkitAdapter.test.mjs`) and JWT signing was checked against a throwaway key.
