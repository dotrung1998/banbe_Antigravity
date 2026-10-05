import { readWalletConfig, getWalletAdmin } from '../_lib/walletPass.js';
import { refreshWalletPass } from '../_lib/walletRefresh.js';

// Safety net for the Wallet update service: re-checks every issued pass whose
// ticket may have changed without anyone calling api/wallet-refresh (a hold that
// was cancelled, a gift made on another client, a push that never arrived), and
// pushes the ones that did. Vercel Cron, see vercel.json.

const BATCH = 200;

export default async function handler(req, res) {
  const secret = process.env.CRON_SECRET;
  if (secret && (req.headers.authorization || '') !== `Bearer ${secret}`) {
    return res.status(401).json({ error: 'UNAUTHORIZED' });
  }
  const cfg = readWalletConfig();
  const admin = getWalletAdmin();
  if (!cfg || !admin) return res.status(200).json({ skipped: 'WALLET_NOT_CONFIGURED' });

  // Only passes somebody actually holds can need a push.
  const { data: regs, error } = await admin.from('wallet_pass_registrations').select('serial_number').limit(5000);
  if (error) return res.status(500).json({ error: error.message });
  const serials = [...new Set((regs || []).map((r) => r.serial_number))].slice(0, BATCH);

  let changed = 0;
  let pushed = 0;
  for (const serial of serials) {
    try {
      const r = await refreshWalletPass(admin, serial, cfg);
      if (r.changed) changed += 1;
      pushed += r.pushed;
    } catch (e) {
      console.warn('wallet sweep failed for', serial, e?.message);
    }
  }
  return res.status(200).json({ checked: serials.length, changed, pushed });
}
