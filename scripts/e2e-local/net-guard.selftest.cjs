// node --require ./net-guard.cjs net-guard.selftest.cjs   (exit 0 = guard works)
const out = [];
const tryFetch = async (url) => { try { const r = await fetch(url); return `reached:${r.status}`; } catch (e) { const c = e.cause || e; return `${c.code || c.name}:${String(c.message).slice(0, 60)}`; } };
(async () => {
  const hosted = await tryFetch('https://ukchdgdnwytretvqjjqu.supabase.co/rest/v1/');
  const cf = await tryFetch('https://api.cloudflare.com/client/v4/user');
  const ip = await tryFetch('http://1.1.1.1/');
  const local = await tryFetch('http://127.0.0.1:54999/');           // refused is fine: it proves loopback is NOT blocked
  console.log({ hosted, cf, ip, local });
  const blocked = [hosted, cf, ip].every((r) => /ENETGUARD|NET-GUARD/.test(r));
  const loopbackOk = /ECONNREFUSED|reached/.test(local);
  process.exit(blocked && loopbackOk ? 0 : 1);
})();
