// The existing specs expect one specific synthetic test account to exist. Rather than copying its address into more
// files, read it from the repo's own tests/global-setup.js (the single place that already defines it).
import { readFileSync } from 'node:fs';
const src = readFileSync(new URL('../../tests/global-setup.js', import.meta.url), 'utf8');
const grab = (name) => { const m = new RegExp(`${name}\\s*=\\s*'([^']+)'`).exec(src); if (!m) throw new Error(`could not read ${name} from tests/global-setup.js`); return m[1]; };
export const SHARED_EMAIL = grab('PERSISTENT_TEST_EMAIL');
export const SHARED_PASSWORD = grab('PERSISTENT_TEST_PASSWORD');
