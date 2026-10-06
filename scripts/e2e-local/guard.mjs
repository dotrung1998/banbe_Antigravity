// Fail-closed isolation guard for the local E2E harness.
// Allows ONLY loopback endpoints and the fixed local test credentials; anything that could
// reach a hosted Supabase project, real R2/Cloudflare, email, SMS or webhook is refused.
export const LOCAL = {
  supabase: 'http://127.0.0.1:55321',
  s3: 'http://127.0.0.1:59000',
  mediaBase: 'http://127.0.0.1:59010',
  cloudflareMock: 'http://127.0.0.1:59100',
  api: 'http://127.0.0.1:5198',
  s3Key: 'banbe-e2e-local',
  s3Secret: 'banbe-e2e-local-secret',
};
const LIVE_REF = 'ukchdgdnwytretvqjjqu';
const HOSTED = /(\.supabase\.(co|in|com)\b|r2\.cloudflarestorage\.com|api\.cloudflare\.com|\.r2\.dev\b|amazonaws\.com|gmail\.com\/|smtp\.)/i;
const MUST_BE_EMPTY = /^(GMAIL_|SMS_|ZALO_|TELEGRAM_|PAYOS_|CASSO_|BANK_WEBHOOK|WEBHOOK|APNS|WALLET_)/;
const LOCAL_ONLY = { // key -> required exact value, when set at all
  SUPABASE_URL: LOCAL.supabase, VITE_SUPABASE_URL: LOCAL.supabase,
  R2_ENDPOINT: LOCAL.s3, MEDIA_PUBLIC_BASE_URL: LOCAL.mediaBase, VITE_MEDIA_PUBLIC_BASE_URL: LOCAL.mediaBase,
  CLOUDFLARE_API_BASE: LOCAL.cloudflareMock, CLOUDFLARE_ZONE_ID: 'local-zone', CLOUDFLARE_PURGE_TOKEN: 'local-purge-token', CRON_SECRET: 'local-cron-secret', R2_ACCESS_KEY_ID: LOCAL.s3Key, R2_SECRET_ACCESS_KEY: LOCAL.s3Secret,
};
export function guardProblems(env = process.env) {
  const problems = [];
  for (const k of ['SUPABASE_URL', 'VITE_SUPABASE_URL']) if (env[k] !== LOCAL.supabase) problems.push(`${k} must be ${LOCAL.supabase}`);
  for (const k of ['SUPABASE_SERVICE_ROLE_KEY', 'VITE_SUPABASE_ANON_KEY']) if (!env[k]) problems.push(`${k} missing`);
  for (const [k, want] of Object.entries(LOCAL_ONLY)) if (env[k] && env[k] !== want) problems.push(`${k} must be ${want} (or unset)`);
  for (const [k, v] of Object.entries(env)) {
    if (typeof v !== 'string' || !v) continue;
    if (k.startsWith('npm_') || k === 'PATH' || k === 'PWD' || k === 'OLDPWD' || k === '_' ) continue;
    if (v.includes(LIVE_REF)) problems.push(`${k} references the live project`);
    if (HOSTED.test(v) && !/^(E2E_|PLAYWRIGHT)/.test(k)) problems.push(`${k} references a hosted service`);
    if (MUST_BE_EMPTY.test(k)) problems.push(`${k} must be empty in the isolated run`);
  }
  // R2 settings are all-or-nothing and only the local values are acceptable
  const r2 = ['R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_ENDPOINT'].filter((k) => env[k]);
  if (r2.length && r2.length !== 3) problems.push('R2_* must be fully local or fully unset');
  return problems;
}
export function assertIsolated(env = process.env) {
  const p = guardProblems(env);
  if (p.length) { console.error('ISOLATION GUARD FAILED:\n - ' + p.join('\n - ')); process.exit(3); }
}
