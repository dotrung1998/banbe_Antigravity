// Preloaded into EVERY Node process the harness starts (NODE_OPTIONS=--require). Hard fail-closed network guard:
// any outbound TCP connection to a non-loopback address throws, regardless of what a spec (or a library it uses)
// decided to call — including specs that read .env.local themselves. DNS names are only allowed if they are
// localhost; the resolved address must be loopback. Does not depend on environment variables.
const net = require('node:net');
const dns = require('node:dns');
const LOOPBACK = /^(127\.\d+\.\d+\.\d+|::1|::ffff:127\.\d+\.\d+\.\d+|localhost)$/i;
const deny = (target) => { const e = new Error(`NET-GUARD: blocked non-loopback connection to ${target} (isolated test run)`); e.code = 'ENETGUARD'; return e; };

const origConnect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function patched(...args) {
  let opts = args[0];
  if (Array.isArray(opts)) opts = opts[0];          // normalized form used internally by net
  const host = opts && typeof opts === 'object' ? (opts.host || 'localhost') : (typeof args[1] === 'string' ? args[1] : 'localhost');
  const isPipe = opts && typeof opts === 'object' && opts.path;
  if (!isPipe && !LOOPBACK.test(String(host))) { process.nextTick(() => this.destroy(deny(host))); return this; }
  return origConnect.apply(this, args);
};
const origLookup = dns.lookup;
dns.lookup = function patchedLookup(hostname, ...rest) {
  if (!LOOPBACK.test(String(hostname))) {
    const cb = rest.find((x) => typeof x === 'function');
    if (cb) return process.nextTick(cb, deny(hostname));
  }
  return origLookup.call(dns, hostname, ...rest);
};
if (dns.promises) {
  const origP = dns.promises.lookup;
  dns.promises.lookup = (hostname, ...rest) => (LOOPBACK.test(String(hostname)) ? origP.call(dns.promises, hostname, ...rest) : Promise.reject(deny(hostname)));
}
