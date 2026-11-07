import { pushPassUpdates } from './apns.js';
import { TICKET_SELECT, stateHash } from './walletPass.js';

/**
 * Re-reads one booking, and if what its pass shows has changed, stamps the pass
 * as updated and pushes every device that holds it. Idempotent: calling it when
 * nothing changed does nothing.
 * `admin` is a service-role Supabase client.
 */
export async function refreshWalletPass(admin, serial, cfg) {
  const { data: pass } = await admin.from('wallet_passes').select('serial_number, state_hash').eq('serial_number', serial).maybeSingle();
  if (!pass) return { changed: false, pushed: 0 };

  const { data: booking } = await admin.from('bookings').select(TICKET_SELECT).eq('id', serial).maybeSingle();
  if (!booking) return { changed: false, pushed: 0 };

  const hash = stateHash(booking);
  if (hash === pass.state_hash) return { changed: false, pushed: 0 };

  await admin.from('wallet_passes')
    .update({ state_hash: hash, updated_at: new Date().toISOString() })
    .eq('serial_number', serial);

  const { data: regs } = await admin.from('wallet_pass_registrations').select('device_id, push_token').eq('serial_number', serial);
  const result = await pushPassUpdates((regs || []).map((r) => r.push_token), cfg);
  if (result.gone.length) {
    await admin.from('wallet_pass_registrations').delete().eq('serial_number', serial).in('push_token', result.gone);
  }
  return { changed: true, pushed: result.sent };
}
