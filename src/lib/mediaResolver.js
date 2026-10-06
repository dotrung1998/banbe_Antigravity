// Public-media URL resolver for the Supabase + Cloudflare R2 hybrid
// (.claude/notes/28-r2-hybrid-media.md). Pure and dependency-free so it can be
// unit-tested under plain node. A ref is `r2:<scope>/<assetId>.<ext>`; the
// public object of a variant lives at `<base>/v1/<scope>/<assetId>/<variant>.<ext>`.
// Anything that does not match the strict grammar is NEVER turned into a URL.

const REF_RE = /^r2:((?:ev|org)-[A-Za-z0-9_-]{1,64})\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.(jpg|jpeg|png|webp)$/i;
const VARIANTS = new Set(['thumb', 'card', 'full']);

/** Parses a ref into { scope, assetId, ext } or null when it is not valid. */
export function parseR2Ref(ref) {
  if (typeof ref !== 'string' || ref.length > 200) return null;
  const m = REF_RE.exec(ref);
  if (!m) return null;
  return { scope: m[1], assetId: m[2].toLowerCase(), ext: m[3].toLowerCase() };
}

export function isR2Ref(ref) {
  return parseR2Ref(ref) !== null;
}

function cleanBase(baseUrl) {
  if (typeof baseUrl !== 'string') return '';
  const b = baseUrl.trim().replace(/\/+$/, '');
  return /^https?:\/\/[^\s/?#]+(\/[^\s?#]*)?$/i.test(b) ? b : '';
}

/** Public URL of one variant, or null when ref/variant/baseUrl is unusable. */
export function r2VariantUrl(ref, variant, { baseUrl } = {}) {
  const parsed = parseR2Ref(ref);
  const base = cleanBase(baseUrl);
  if (!parsed || !base || !VARIANTS.has(variant)) return null;
  return `${base}/v1/${parsed.scope}/${parsed.assetId}/${variant}.${parsed.ext}`;
}

/** Client media config. `env` is injectable for tests. */
export function getMediaConfig(env = import.meta.env) {
  return {
    baseUrl: cleanBase(env?.VITE_MEDIA_PUBLIC_BASE_URL || ''),
    readsEnabled: env?.VITE_MEDIA_R2_READS === '1',
  };
}

/**
 * R2 URL only when reads are enabled, a base URL is configured and the ref
 * parses; otherwise `legacyUrl` (which may be null/undefined/'').
 * `baseUrl`/`readsEnabled` default to the build-time config when omitted.
 */
export function resolveMediaUrl({ r2Ref, legacyUrl, variant = 'card', baseUrl, readsEnabled } = {}) {
  const cfg = (baseUrl === undefined || readsEnabled === undefined) ? getMediaConfig() : null;
  const base = baseUrl === undefined ? cfg.baseUrl : baseUrl;
  const reads = readsEnabled === undefined ? cfg.readsEnabled : readsEnabled;
  if (reads && base && r2Ref) {
    const url = r2VariantUrl(r2Ref, variant, { baseUrl: base });
    if (url) return url;
  }
  return legacyUrl;
}
