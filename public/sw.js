// Local cache for Supabase Storage images.
//
// Why: signed URLs carry a rotating `?token=` (10min-1h TTL), and objects
// uploaded before the cacheControl fix carry a 1h max-age, so the browser
// re-downloads identical bytes — that is what burns Supabase cached egress.
// Every upload in this app writes a brand-new Date.now() path, so the object
// path (query stripped) is a correct, permanent identity for its content.
// See .claude/notes/22-supabase-bandwidth-optimization.md.
const CACHE = 'banbe-storage-v1';
const MAX_ENTRIES = 400;
const MAX_BYTES = 8 * 1024 * 1024; // don't keep big files (video etc.)
const STORAGE_RE = /^\/storage\/v1\/object\/(public|sign|authenticated)\//;

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter((n) => n.startsWith('banbe-storage-') && n !== CACHE).map((n) => caches.delete(n)));
    await self.clients.claim();
  })());
});

// Sign-out: private media (chat, payment proofs) must not outlive the session.
self.addEventListener('message', (event) => {
  if (event.data === 'banbe-clear-storage-cache') event.waitUntil(caches.delete(CACHE));
});

function stableKey(url) {
  const u = new URL(url);
  return u.origin + u.pathname;
}

async function trim(cache) {
  const keys = await cache.keys(); // insertion order
  for (let i = 0; i < keys.length - MAX_ENTRIES; i++) await cache.delete(keys[i]);
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET' || req.headers.has('range')) return;
  const url = new URL(req.url);
  if (!url.hostname.endsWith('.supabase.co') || !STORAGE_RE.test(url.pathname)) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const key = stableKey(req.url);
    const hit = await cache.match(key);
    if (hit) return hit;
    try {
      // Re-issue as CORS so we get a readable (non-opaque) response.
      const res = await fetch(req.url, { mode: 'cors', credentials: 'omit' });
      const type = res.headers.get('content-type') || '';
      const len = Number(res.headers.get('content-length') || 0);
      if (res.status === 200 && type.startsWith('image/') && len <= MAX_BYTES) {
        event.waitUntil(cache.put(key, res.clone()).then(() => trim(cache)).catch(() => {}));
      }
      return res;
    } catch {
      return fetch(req); // CORS refetch failed — fall back to the normal request
    }
  })());
});
