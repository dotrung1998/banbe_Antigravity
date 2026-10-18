// Product analytics boundary — web mirror of iOS `Lib/Analytics.swift` (note 43).
// There is NO vendor: `track()` is a no-op (dev builds log to the console). Events carry
// only ids, counts and buckets — never answers, names, emails or any other PII.
// To add a provider: replace `sink` after a privacy review.

let sink = (event) => {
  if (typeof import.meta !== 'undefined' && import.meta.env?.DEV) console.debug('[analytics]', event.name, event.props || {});
};

export function setAnalyticsSink(fn) { sink = typeof fn === 'function' ? fn : () => {}; }

export function track(name, props) {
  try { sink({ name, props }); } catch { /* analytics must never break the app */ }
}

/** Match counts are bucketed so no exact number leaves the device: 0 / 1-2 / 3-5 / 6-10 / 11+. */
export function matchBucket(n) {
  if (n <= 0) return '0';
  if (n <= 2) return '1-2';
  if (n <= 5) return '3-5';
  if (n <= 10) return '6-10';
  return '11+';
}
