// ONE serverless function for everything Wallet. The Hobby plan allows 12
// functions per deployment and this repo had reached 15, so related handlers
// live in api/_lib/handlers/ (never counted as functions) and are routed here
// by the rewrites in vercel.json — every public URL is unchanged:
//
//   /api/wallet-pass     -> op=pass     issue a .pkpass
//   /api/wallet-refresh  -> op=refresh  re-check one pass
//   /api/wallet/v1/...   -> op=ws       Apple's PassKit update web service
import issue from './_lib/handlers/walletPassIssue.js';
import refresh from './_lib/handlers/walletRefresh.js';
import webService from './_lib/handlers/walletWebService.js';

const OPS = { pass: issue, refresh, ws: webService };

export default async function handler(req, res) {
  const op = Array.isArray(req.query?.op) ? req.query.op[0] : req.query?.op;
  const fn = OPS[op];
  if (!fn) return res.status(404).json({ error: 'UNKNOWN_WALLET_OP' });
  return fn(req, res);
}
