import { r2Config, signedFetch } from '../../api/_lib/r2.js';
import { LOCAL } from './guard.mjs';
const cfg = r2Config({ R2_ACCOUNT_ID: 'local', R2_ACCESS_KEY_ID: LOCAL.s3Key, R2_SECRET_ACCESS_KEY: LOCAL.s3Secret, R2_PUBLIC_BUCKET: 'banbe-media-public', R2_STAGING_BUCKET: 'banbe-media-staging', R2_ENDPOINT: LOCAL.s3 });
for (const b of [cfg.publicBucket, cfg.stagingBucket]) {
  const r = await signedFetch(cfg, { method: 'PUT', bucket: b, key: '' });
  if (!r.ok && r.status !== 409) throw new Error(`create bucket ${b}: ${r.status}`);
  console.log('bucket ready:', b);
}
