// One place decides which request Host may become a customer-facing origin.
//
// Several endpoints used to build URLs from `req.headers.host` /
// `x-forwarded-host` directly: MapKit's JWT `origin`, Apple Wallet's
// webServiceURL and image fetches, the payment-document wordmark, and the
// photo-share OG page. A forged Host therefore became attacker-controlled
// HTML (payment-document <img src>) or an attacker-controlled third-party
// fetch. A forwarded Host is not proof of the origin by itself, so this module
// allowlists it and otherwise falls back to the canonical site.
//
// Production: set PUBLIC_SITE_URL (preferred) or AUTH_REDIRECT_URL. Vercel's
// own deployment hostnames and an optional comma-separated ORIGIN_ALLOWLIST
// are accepted; everything else gets the canonical origin.

const DEFAULT_CANONICAL = 'https://www.banbe.app';
const LOCAL_HOSTNAMES = new Set(['localhost', '127.0.0.1', '[::1]']);

function normaliseOrigin(value) {
  if (!value) return null;
  try {
    const raw = String(value).trim();
    const url = new URL(/^[a-z][a-z0-9+.-]*:\/\//i.test(raw) ? raw : `https://${raw}`);
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
    if (url.username || url.password) return null;
    if (url.protocol === 'http:' && !LOCAL_HOSTNAMES.has(url.hostname)) return null;
    return url.origin;
  } catch {
    return null;
  }
}

function configuredOrigin() {
  return normaliseOrigin(process.env.PUBLIC_SITE_URL)
    || normaliseOrigin(process.env.AUTH_REDIRECT_URL)
    || normaliseOrigin(process.env.VITE_AUTH_REDIRECT_URL)
    || normaliseOrigin(process.env.VITE_SITE_URL)
    || DEFAULT_CANONICAL;
}

function hostnameOf(value) {
  if (!value) return null;
  try {
    return new URL(/^[a-z][a-z0-9+.-]*:\/\//i.test(value) ? value : `https://${value}`).hostname.toLowerCase();
  } catch {
    return null;
  }
}

function allowedHostnames(canonical) {
  const allowed = new Set(['banbe.app', 'www.banbe.app']);
  const canonicalHost = hostnameOf(canonical);
  if (canonicalHost) allowed.add(canonicalHost);

  for (const value of [
    process.env.VERCEL_PROJECT_PRODUCTION_URL,
    process.env.VERCEL_BRANCH_URL,
    process.env.VERCEL_URL,
  ]) {
    const host = hostnameOf(value);
    if (host) allowed.add(host);
  }

  for (const value of String(process.env.ORIGIN_ALLOWLIST || '').split(',')) {
    const host = hostnameOf(value.trim());
    if (host) allowed.add(host);
  }
  return allowed;
}

function requestHost(req) {
  const forwarded = req?.headers?.['x-forwarded-host'];
  const raw = Array.isArray(forwarded) ? forwarded[0] : forwarded;
  const host = String(raw || req?.headers?.host || '').split(',')[0].trim().toLowerCase();
  // Hostnames, IPv4, or a bracketed IPv6 literal, each optionally with a port.
  if (!/^(?:[a-z0-9.-]+|\[[0-9a-f:]+\])(?::\d{1,5})?$/.test(host)) return null;
  return host;
}

/**
 * The origin this request may safely use in links, HTML and outbound fetches.
 * Never returns an unvalidated Host, never includes credentials or a path.
 */
export function requestOrigin(req) {
  const canonical = configuredOrigin();
  const host = requestHost(req);
  if (!host) return canonical;

  const hostname = host.replace(/:\d+$/, '');
  if (LOCAL_HOSTNAMES.has(hostname)) return `http://${host}`;
  if (allowedHostnames(canonical).has(hostname)) return `https://${host}`;
  return canonical;
}

export { normaliseOrigin };
