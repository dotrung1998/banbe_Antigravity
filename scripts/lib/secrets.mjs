// Loads server credentials for the one-off R2 scripts from a local file, so no
// secret ever has to be typed into a shell (and land in shell history), pasted
// into a chat, or committed.
//
// Precedence: a real environment variable wins over a file (CI / one-off
// exports), then `.r2-secrets.local`, then `.env.local`, then `.env`.
// Nothing in this module prints or returns a value by accident: callers only
// ever get the merged map, plus helper messages that name keys, never values.
import { existsSync, readFileSync, statSync } from 'node:fs';

export const SECRETS_FILES = ['.r2-secrets.local', '.env.local', '.env'];

/** KEY=VALUE parser (comments, blank lines, optional surrounding quotes). */
export function parseEnvFile(text) {
  const out = {};
  for (const raw of String(text).split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq <= 0) continue;
    const key = line.slice(0, eq).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue;
    let value = line.slice(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    out[key] = value;
  }
  return out;
}

/**
 * Merged environment for the scripts. `files` is overridable for tests.
 * Values are never logged here.
 */
export function loadSecrets({ files = SECRETS_FILES, env = process.env } = {}) {
  const values = {};
  const sources = {};
  for (const file of files) {
    if (!existsSync(file)) continue;
    let parsed;
    try { parsed = parseEnvFile(readFileSync(file, 'utf8')); } catch { continue; }
    for (const [k, v] of Object.entries(parsed)) {
      if (v === '' || k in values) continue;
      values[k] = v;
      sources[k] = file;
    }
  }
  for (const [k, v] of Object.entries(env)) {
    if (typeof v === 'string' && v !== '') { values[k] = v; sources[k] = 'environment'; }
  }
  return { values, sources };
}

/** Names from `required` that have no value. Names only — never values. */
export function missingNames(values, required) {
  return required.filter((name) => !values[name]);
}

/** Files that exist but are readable by other local users (mode & 0o077). */
export function loosePermissions(files = SECRETS_FILES) {
  return files.filter((f) => {
    if (!existsSync(f)) return false;
    try { return (statSync(f).mode & 0o077) !== 0; } catch { return false; }
  });
}

/** Parses a comma-separated env list (ids, origins). */
export const envList = (value) => String(value || '').split(',').map((s) => s.trim()).filter(Boolean);
