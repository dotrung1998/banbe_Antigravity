// Minimal .env loader for the real-backend E2E test — no `dotenv` dependency
// exists in this repo (see package.json), and this only needs to read two
// flat KEY=VALUE files (.env, .env.local) into process.env once, at import
// time. Values are taken verbatim to end-of-line (no shell-style splitting),
// which matters here: GMAIL_APP_PASSWORD contains spaces.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

function loadFile(name) {
  let text;
  try {
    text = readFileSync(path.join(repoRoot, name), 'utf8');
  } catch {
    return; // fine — not every env file exists in every checkout
  }
  for (const rawLine of text.split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    const value = line.slice(eq + 1).trim();
    if (key && !(key in process.env)) process.env[key] = value;
  }
}

// .env.local last so it wins on overlap — SUPABASE_SERVICE_ROLE_KEY/
// SUPABASE_URL/AUTH_REDIRECT_URL and GMAIL_USER/GMAIL_APP_PASSWORD all live
// there (gitignored), not in .env.example (which is committed and must stay
// placeholders only — see the 2026-09-14 entry in 05-notify-retention.md).
loadFile('.env');
loadFile('.env.local');
