import { getSupabaseAdmin } from './authLookup.js';
import { accountGateStatus } from './accountGate.js';
import { makeMediaDb } from './mediaDb.js';
import { makeKeychainDb } from './keychainArt.js';
import { r2Config, presignUrl, getObject, putObject, deleteObject, purgeUrls } from './r2.js';

/** Builds the production ctx for media.js, or null if R2/Supabase are not configured. */
export function buildMediaCtx(env = process.env) {
  const admin = getSupabaseAdmin();
  const cfg = r2Config(env);
  const notConfigured = { configured: false, presignStagingPut() { throw new Error('R2_NOT_CONFIGURED'); } };
  const r2 = !cfg.ok || !cfg.publicBaseUrl ? notConfigured : {
    configured: true,
    presignStagingPut: (key, headers) => presignUrl(cfg, { method: 'PUT', bucket: cfg.stagingBucket, key, headers, expiresIn: 300 }),
    getStaging: (key, max) => getObject(cfg, cfg.stagingBucket, key, max),
    deleteStaging: (key) => deleteObject(cfg, cfg.stagingBucket, key),
    putPublic: (key, body, opts) => putObject(cfg, cfg.publicBucket, key, body, opts),
    getPublic: (key, max) => getObject(cfg, cfg.publicBucket, key, max),
    deletePublic: (key) => deleteObject(cfg, cfg.publicBucket, key),
    publicUrl: (key) => `${cfg.publicBaseUrl}/${key}`,
    purge: (urls) => purgeUrls(urls, env),
  };
  return {
    env,
    admin,
    r2,
    db: admin ? makeMediaDb(admin) : null,
    keychain: admin ? makeKeychainDb(admin) : null,
    auth: {
      async verify(token) { const { data, error } = await admin.auth.getUser(token); return error || !data?.user ? null : data.user.id; },
      async gate(token) { return (await accountGateStatus(token)).ok; },
    },
  };
}
