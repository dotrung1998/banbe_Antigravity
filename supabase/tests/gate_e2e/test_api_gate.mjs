// Assertion test for api/_lib/accountGate.js with a mocked fetch.
import assert from 'node:assert/strict';
import { accountGateStatus, rejectIfGated } from '../../../api/_lib/accountGate.js';

process.env.SUPABASE_URL = 'https://x.supabase.co';
process.env.SUPABASE_ANON_KEY = 'anon';
const reply = (status, body) => async (url, init) => {
  assert.equal(url, 'https://x.supabase.co/rest/v1/rpc/account_gate_ok');
  assert.equal(init.headers.Authorization, 'Bearer tok'); // the CALLER'S token
  return { status, ok: status >= 200 && status < 300, json: async () => body };
};
const res = () => { const r = { code: null, body: null }; r.status = (c) => { r.code = c; return r; }; r.json = (b) => { r.body = b; return r; }; return r; };

global.fetch = reply(200, true);
assert.deepEqual(await accountGateStatus('tok'), { ok: true });
global.fetch = reply(200, false);
let r = res(); assert.equal(await rejectIfGated(r, 'tok'), true); assert.equal(r.code, 403); assert.equal(r.body.error, 'ACCOUNT_GATE_REQUIRED');
global.fetch = reply(403, { message: 'ACCOUNT_GATE_REQUIRED' });
r = res(); assert.equal(await rejectIfGated(r, 'tok'), true); assert.equal(r.code, 403);
global.fetch = reply(404, {});
assert.deepEqual(await accountGateStatus('tok'), { ok: true }); // migration not deployed yet -> allowed
global.fetch = reply(500, {});
r = res(); assert.equal(await rejectIfGated(r, 'tok'), true); assert.equal(r.code, 503); assert.equal(r.body.error, 'GATE_CHECK_FAILED');
global.fetch = async () => { throw new Error('network'); };
r = res(); assert.equal(await rejectIfGated(r, 'tok'), true); assert.equal(r.code, 503);
r = res(); assert.equal(await rejectIfGated(r, ''), true); assert.equal(r.code, 503); // no token -> never passes
global.fetch = reply(200, true);
r = res(); assert.equal(await rejectIfGated(r, 'tok'), false); assert.equal(r.code, null);
console.log('api gate: 9 assertions passed');
