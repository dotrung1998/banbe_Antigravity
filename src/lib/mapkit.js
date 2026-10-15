// Apple MapKit JS on the web — OFF by default. The web app keeps MapLibre/OpenFreeMap (+ the server-side
// OpenStreetMap address search) until BOTH hold: VITE_MAPKIT_ENABLED=true at build time AND the server has
// the MAPKIT_* env set (api/_lib/handlers/mapkitToken.js). Any failure to load or authorise MapKit
// resolves null and callers fall back to the OpenStreetMap path, so turning it on can never break maps.
const env = (typeof import.meta !== 'undefined' && import.meta.env) ? import.meta.env : {};
const SCRIPT_URL = 'https://cdn.apple-mapkit.com/mk/5.x.x/mapkit.js';

export const mapKitEnabled = () => String(env.VITE_MAPKIT_ENABLED || '').toLowerCase() === 'true';

let pending = null;

function loadScript() {
  if (typeof window === 'undefined') return Promise.reject(new Error('NO_WINDOW'));
  if (window.mapkit?.init) return Promise.resolve(window.mapkit);
  return new Promise((resolve, reject) => {
    const el = document.createElement('script');
    el.src = SCRIPT_URL;
    el.crossOrigin = 'anonymous';
    el.async = true;
    el.onload = () => (window.mapkit ? resolve(window.mapkit) : reject(new Error('MAPKIT_MISSING')));
    el.onerror = () => reject(new Error('MAPKIT_SCRIPT_FAILED'));
    document.head.appendChild(el);
  });
}

async function fetchToken() {
  const res = await fetch('/api/mapkit-token', { headers: { Accept: 'application/json' } });
  if (!res.ok) throw new Error(`MAPKIT_TOKEN_${res.status}`);
  const { token } = await res.json();
  if (!token) throw new Error('MAPKIT_TOKEN_EMPTY');
  return token;
}

/** Resolves the initialised `mapkit` global, or null when disabled / not configured / unreachable. */
export function loadMapKit() {
  if (!mapKitEnabled()) return Promise.resolve(null);
  if (!pending) {
    pending = (async () => {
      try {
        const [mapkit, firstToken] = await Promise.all([loadScript(), fetchToken()]);
        let first = true;
        mapkit.init({
          authorizationCallback: (done) => {
            if (first) { first = false; done(firstToken); return; }
            fetchToken().then(done).catch(() => done(''));
          },
          language: (typeof document !== 'undefined' && document.documentElement.lang) || 'vi',
        });
        return mapkit;
      } catch (e) {
        console.info('[mapkit] unavailable, using OpenStreetMap:', e.message);
        return null;
      }
    })();
  }
  return pending;
}
