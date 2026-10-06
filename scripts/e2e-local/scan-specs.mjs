// Static pre-flight: refuse to run specs that could bypass the isolation guard (read .env.local themselves,
// hardcode the live project or a hosted URL). Complements net-guard.cjs, which blocks at the socket level.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
const here = new URL('.', import.meta.url).pathname;
const repo = process.env.E2E_REPO || join(here, '../..');
const files = [join(repo, 'tests/helpers.js')];
for (const n of readFileSync(join(here, 'focused-specs.txt'), 'utf8').split('\n').map((s) => s.trim()).filter(Boolean)) files.push(join(repo, `tests/${n}.spec.js`));
for (const d of ['focused-copies', 'specs', 'diag']) { const p = join(here, d); if (existsSync(p)) for (const f of readdirSync(p)) if (/\.(mjs|js)$/.test(f)) files.push(join(p, f)); }
const BAD = [
  [/['"`][^'"`\n]*\.env(\.local)?['"`]/, 'reads an .env file directly'],
  [/ukchdgdnwytretvqjjqu/, 'contains the live project ref'],
  [/dWtjaGRnZG53eXRyZXR2cWpqcXU|InJlZiI6InVrY2hk/, 'contains a JWT bound to the live project'],
  [/https?:\/\/[a-z0-9-]+\.supabase\.(co|in)/i, 'hardcodes a hosted Supabase URL'],
  [/api\.cloudflare\.com|r2\.cloudflarestorage\.com/, 'hardcodes a Cloudflare endpoint'],
];
const problems = [];
for (const f of files) {
  if (!existsSync(f)) { problems.push(`${f}: listed but missing`); continue; }
  const src = readFileSync(f, 'utf8').split('\n').filter((l) => !/^\s*(\/\/|\*)/.test(l)).join('\n');   // ignore comment-only lines
  for (const [re, why] of BAD) if (re.test(src)) problems.push(`${f.replace(repo + '/', '')}: ${why}`);
}
if (problems.length) { console.error('SPEC SCAN FAILED (a spec could bypass the isolation guard):\n - ' + problems.join('\n - ')); process.exit(3); }
console.log(`spec scan ok (${files.length} files)`);
