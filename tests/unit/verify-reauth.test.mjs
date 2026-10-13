import test from 'node:test';
import assert from 'node:assert/strict';

// Exercises /api/auth verify_reauth (date-of-birth path) and delete_account's proof requirement with the
// network stubbed: Supabase auth getUser and the confirm_date_of_birth RPC.
process.env.SUPABASE_URL = 'https://example.supabase.co';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-key';
process.env.SUPABASE_ANON_KEY = 'anon-key';

const UID = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
let rpcResult = { success: true };
let rpcStatus = 200;
const calls = [];

globalThis.fetch = async (url, init = {}) => {
  const u = String(url);
  calls.push({ url: u, init });
  const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
  if (u.includes('/auth/v1/user')) return json({ id: UID, email: 'a@b.com', aud: 'authenticated', role: 'authenticated' });
  if (u.includes('/rest/v1/rpc/confirm_date_of_birth')) return json(rpcResult, rpcStatus);
  return json({ error: 'unexpected ' + u }, 500);
};

const { default: handler } = await import('../../api/auth/index.js');
const { verifyReauthProof } = await import('../../api/_lib/reauthProof.js');

function call(body, token = 'user-token') {
  return new Promise(resolve => {
    const res = { statusCode: 0, headers: {}, setHeader(k, v) { this.headers[k] = v; }, status(c) { this.statusCode = c; return this; }, json(b) { resolve({ status: this.statusCode, body: b }); } };
    handler({ method: 'POST', body, headers: token ? { authorization: `Bearer ${token}` } : {} }, res);
  });
}

test('correct date of birth returns a proof bound to the caller', async () => {
  rpcResult = { success: true }; rpcStatus = 200;
  const r = await call({ type: 'verify_reauth', dob: '1990-05-17' });
  assert.equal(r.status, 200);
  assert.equal(verifyReauthProof(r.body.proof, UID, 'service-key'), true);
  const rpc = calls.filter(c => c.url.includes('confirm_date_of_birth')).pop();
  assert.equal(JSON.parse(rpc.init.body).p_dob, '1990-05-17');
  assert.equal(rpc.init.headers.Authorization, 'Bearer user-token', 'runs as the caller, not as the service role');
});

test('wrong date reports attempts left; lockout reports retry time; no proof either way', async () => {
  rpcResult = { success: false, error: 'INCORRECT', attempts_left: 3 };
  let r = await call({ type: 'verify_reauth', dob: '1990-05-18' });
  assert.deepEqual([r.status, r.body.error, r.body.attemptsLeft, r.body.proof], [400, 'REAUTH_DOB_INCORRECT', 3, undefined]);
  rpcResult = { success: false, error: 'LOCKED', retry_after_seconds: 900 };
  r = await call({ type: 'verify_reauth', dob: '1990-05-18' });
  assert.deepEqual([r.status, r.body.error, r.body.retryAfter, r.body.proof], [429, 'REAUTH_DOB_LOCKED', 900, undefined]);
});

test('an account with no date of birth on file is sent to the emailed-code path, not given a proof', async () => {
  rpcResult = { success: true, not_required: true };
  const r = await call({ type: 'verify_reauth', dob: '1990-05-17' });
  assert.deepEqual([r.status, r.body.error, r.body.proof], [400, 'REAUTH_DOB_NOT_SET', undefined]);
});

test('malformed date and missing login are rejected', async () => {
  assert.equal((await call({ type: 'verify_reauth', dob: '17/05/1990' })).body.error, 'REAUTH_DOB_INVALID');
  assert.equal((await call({ type: 'verify_reauth', dob: '1990-05-17' }, '')).status, 401);
});

test('delete_account refuses without a valid proof', async () => {
  assert.equal((await call({ type: 'delete_account' })).body.error, 'REAUTH_REQUIRED');
  assert.equal((await call({ type: 'delete_account', reauthProof: 'forged.1.abc' })).status, 403);
});
