// TASK D (2026-10-01 UX foundation pass) — configurable App Store
// destination for the "app not installed" fallback banner on a shared
// public-profile web page. Real value comes from a build-time env var
// (VITE_APP_STORE_URL) once this app actually has an App Store listing;
// the placeholder below is intentionally obvious so it's never mistaken
// for a real link if that env var is never set.
export const APP_STORE_URL = import.meta.env.VITE_APP_STORE_URL || 'https://apps.apple.com/app/banbe/id0000000000';
