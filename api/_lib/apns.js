import http2 from 'node:http2';

// Tells Wallet "this pass changed, come and fetch it". The push carries no data
// by design (PassKit's rule): Wallet then calls our update web service. It is
// authenticated with the SAME Pass Type ID certificate that signs the pass, as a
// TLS client certificate, and addressed with the pass type as apns-topic.
//
// Returns { sent, failed, gone: [pushTokens APNs says no longer exist] }.
export async function pushPassUpdates(tokens, cfg) {
  const out = { sent: 0, failed: 0, gone: [] };
  if (!tokens.length) return out;

  const session = http2.connect('https://api.push.apple.com', {
    cert: cfg.signerCert,
    key: cfg.signerKey,
    passphrase: cfg.passphrase,
  });
  session.on('error', () => {});

  await Promise.all(tokens.map((token) => new Promise((resolve) => {
    const req = session.request({
      ':method': 'POST',
      ':path': `/3/device/${token}`,
      'apns-topic': cfg.passTypeId,
      'apns-push-type': 'background',
      'apns-priority': '5',
    });
    let status = 0;
    req.on('response', (h) => { status = h[':status']; });
    req.on('data', () => {});
    req.on('end', () => {
      if (status === 200) out.sent += 1;
      else { out.failed += 1; if (status === 410) out.gone.push(token); }
      resolve();
    });
    req.on('error', () => { out.failed += 1; resolve(); });
    req.setTimeout(10000, () => { req.close(); });
    req.end('{}');
  })));

  session.close();
  return out;
}
