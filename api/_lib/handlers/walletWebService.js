import {
  readWalletConfig, getWalletAdmin, buildPass, designFromRow, tokenMatches, TICKET_SELECT, stateHash,
} from '../walletPass.js';
import { refreshWalletPass } from '../walletRefresh.js';

// Apple's PassKit web service, which Wallet calls itself (no Supabase login:
// each pass carries its own HMAC authenticationToken). `webServiceURL` in every
// pass is <origin>/api/wallet, so Wallet asks for:
//
//   POST   /v1/devices/:device/registrations/:passType/:serial   register + push token
//   DELETE /v1/devices/:device/registrations/:passType/:serial   unregister
//   GET    /v1/devices/:device/registrations/:passType?passesUpdatedSince=
//                                                                which serials changed
//   GET    /v1/passes/:passType/:serial                          the latest .pkpass
//   POST   /v1/log                                               Wallet's error log
//
// What changes a pass: the ticket was gifted / cancelled (it is re-issued VOIDED
// with no QR), or its seat count, code or entry token changed.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const text = (v) => (typeof v === 'string' ? v.trim() : '');

export default async function handler(req, res) {
  const cfg = readWalletConfig();
  const admin = getWalletAdmin();
  if (!cfg || !admin) return res.status(503).json({ error: 'WALLET_NOT_CONFIGURED' });

  // The rewrite in vercel.json delivers the rest of the URL as ONE string
  // ("v1/devices/..."); a dynamic-route file used to deliver an array.
  const parts = [].concat(req.query?.path || []).flatMap((p) => String(p).split('/')).filter(Boolean);
  if (parts[0] !== 'v1') return res.status(404).end();

  try {
    if (parts[1] === 'log' && req.method === 'POST') {
      console.warn('wallet log:', JSON.stringify(req.body?.logs || req.body || {}).slice(0, 2000));
      return res.status(200).end();
    }

    // /v1/devices/:device/registrations/:passType[/:serial]
    if (parts[1] === 'devices' && parts[3] === 'registrations') {
      const [, , device, , passType, serial] = parts;
      if (passType !== cfg.passTypeId) return res.status(404).end();

      if (serial) {
        if (!UUID.test(serial)) return res.status(404).end();
        if (!tokenMatches(req.headers.authorization, serial, cfg)) return res.status(401).end();

        if (req.method === 'POST') {
          const body = typeof req.body === 'string' ? safeJson(req.body) : (req.body || {});
          const pushToken = text(body.pushToken);
          if (!pushToken) return res.status(400).end();
          const { data: pass } = await admin.from('wallet_passes').select('serial_number').eq('serial_number', serial).maybeSingle();
          if (!pass) return res.status(404).end();
          const { data: existing } = await admin.from('wallet_pass_registrations')
            .select('device_id').eq('device_id', device).eq('serial_number', serial).maybeSingle();
          const { error } = await admin.from('wallet_pass_registrations')
            .upsert({ device_id: device, serial_number: serial, push_token: pushToken });
          if (error) throw error;
          return res.status(existing ? 200 : 201).end();
        }
        if (req.method === 'DELETE') {
          await admin.from('wallet_pass_registrations').delete().eq('device_id', device).eq('serial_number', serial);
          return res.status(200).end();
        }
        return res.status(405).end();
      }

      if (req.method === 'GET') {
        const { data: regs } = await admin.from('wallet_pass_registrations')
          .select('serial_number').eq('device_id', device);
        const serials = (regs || []).map((r) => r.serial_number);
        if (!serials.length) return res.status(204).end();

        // Catches changes nobody pushed for (cancelled hold, missed push).
        await Promise.all(serials.map((s) => refreshWalletPass(admin, s, cfg).catch(() => null)));

        const since = text(req.query?.passesUpdatedSince);
        let q = admin.from('wallet_passes').select('serial_number, updated_at').in('serial_number', serials);
        if (since) q = q.gt('updated_at', new Date(Number(since) || since).toISOString());
        const { data: rows } = await q;
        if (!rows?.length) return res.status(204).end();
        const lastUpdated = rows.reduce((m, r) => Math.max(m, new Date(r.updated_at).getTime()), 0);
        return res.status(200).json({
          serialNumbers: rows.map((r) => r.serial_number),
          lastUpdated: String(lastUpdated),
        });
      }
      return res.status(405).end();
    }

    // /v1/passes/:passType/:serial
    if (parts[1] === 'passes' && req.method === 'GET') {
      const [, , passType, serial] = parts;
      if (passType !== cfg.passTypeId || !UUID.test(serial || '')) return res.status(404).end();
      if (!tokenMatches(req.headers.authorization, serial, cfg)) return res.status(401).end();

      await refreshWalletPass(admin, serial, cfg).catch(() => null);
      const { data: row } = await admin.from('wallet_passes').select('*').eq('serial_number', serial).maybeSingle();
      if (!row) return res.status(404).end();

      const modified = new Date(row.updated_at);
      const ims = req.headers['if-modified-since'];
      if (ims && new Date(ims) >= new Date(Math.floor(modified.getTime() / 1000) * 1000)) return res.status(304).end();

      const { data: booking } = await admin.from('bookings').select(TICKET_SELECT).eq('id', serial).maybeSingle();
      if (!booking) return res.status(404).end();

      const origin = `https://${req.headers.host || 'www.banbe.app'}`;
      const pass = await buildPass({ booking, cfg, origin, design: designFromRow(row) });
      res.setHeader('Content-Type', 'application/vnd.apple.pkpass');
      res.setHeader('Last-Modified', modified.toUTCString());
      res.setHeader('Cache-Control', 'private, no-store');
      return res.status(200).send(pass.getAsBuffer());
    }

    return res.status(404).end();
  } catch (e) {
    console.warn('wallet web service failed:', e);
    return res.status(500).end();
  }
}

function safeJson(s) {
  try { return JSON.parse(s); } catch { return {}; }
}
