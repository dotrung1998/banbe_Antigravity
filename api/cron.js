// ONE serverless function for every scheduled job (see the crons in
// vercel.json, each `/api/cron?job=<name>`). Each job still checks the
// CRON_SECRET bearer itself. Handlers live in api/_lib/handlers/ so they don't
// count against the Hobby plan's 12-function limit.
import escalateVerifications from './_lib/handlers/cronEscalateVerifications.js';
import purgePaymentDocuments from './_lib/handlers/cronPurgePaymentDocuments.js';
import walletPassSweep from './_lib/handlers/cronWalletPassSweep.js';
import mediaSweep from './_lib/handlers/cronMediaSweep.js';

const JOBS = {
  'escalate-verifications': escalateVerifications,
  'purge-payment-documents': purgePaymentDocuments,
  'wallet-pass-sweep': walletPassSweep,
  'media-sweep': mediaSweep,
};

export default async function handler(req, res) {
  const job = Array.isArray(req.query?.job) ? req.query.job[0] : req.query?.job;
  const fn = JOBS[job];
  if (!fn) return res.status(404).json({ error: 'UNKNOWN_CRON_JOB' });
  return fn(req, res);
}
