// Audit 2026-11-23 #5: the first visit used to download every screen in one 3.33 MB entry chunk. The screens reached by
// a tap are now split out, and this check keeps it that way: a new eager import (or a lazy() wrapper Rollup ignores
// because something else imports the module statically) fails the build instead of silently putting the whole app back
// into the first download. Run after `npm run build`.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { join } from 'node:path';

const DIR = 'dist/assets';
// The audit's target for the entry chunk ("entry < 2 MB").
const ENTRY_LIMIT_BYTES = 2_000_000;
// Chunks that must stay split: the Map (maplibre + discovery maths) and the admin / test-account routes.
const REQUIRED_CHUNKS = [
  ['MapExplore', /^MapExplore-.*\.js$/],
  ['AdminTestAccounts', /^AdminTestAccounts-.*\.js$/],
  ['AdminEvents', /^AdminEvents-.*\.js$/],
];

let files;
try {
  files = readdirSync(DIR);
} catch {
  console.error(`No ${DIR} directory — run \`npm run build\` first.`);
  process.exit(1);
}

const entry = files.find((f) => /^index-.*\.js$/.test(f));
if (!entry) {
  console.error(`No entry chunk (index-*.js) in ${DIR} — did the build run?`);
  process.exit(1);
}

const entryPath = join(DIR, entry);
const entryBytes = statSync(entryPath).size;
const entryGzip = gzipSync(readFileSync(entryPath)).length;
console.log(`entry ${entry}: ${entryBytes} B (gzip ${entryGzip} B), budget ${ENTRY_LIMIT_BYTES} B`);

let failed = entryBytes >= ENTRY_LIMIT_BYTES;
if (failed) console.error(`entry chunk is over the 2 MB budget (${entryBytes} B) — split more, do not raise the budget`);

for (const [name, pattern] of REQUIRED_CHUNKS) {
  const found = files.find((f) => pattern.test(f));
  if (!found) {
    console.error(`missing split chunk: ${name} — it is being pulled back into the entry`);
    failed = true;
    continue;
  }
  console.log(`split ${name}: ${found} (${statSync(join(DIR, found)).size} B)`);
}

process.exit(failed ? 1 : 0);
