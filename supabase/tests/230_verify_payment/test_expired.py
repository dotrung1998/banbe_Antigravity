#!/usr/bin/env python3
"""
Migration 230 against the THROWAWAY stack (g-db), on the 210 seed. Each case runs in a rolled-back transaction that
applies the migration (or migration + rollback) and then calls verify_payment AS THE REAL HOST, so authorization, the
status trigger and the function body are all the production ones. Touches nothing remote.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = open(os.path.join(ROOT, 'supabase/migrations/20261231000230_230_verify_payment_expired_state.sql')).read()
RB = open(os.path.join(ROOT, 'supabase/rollbacks/20261231000230_230_revert_verify_payment_expired_state.sql')).read()
strip_tx = lambda sql: re.sub(r'(?m)^\s*(BEGIN|COMMIT);\s*$', '', sql)
MIG, RB = strip_tx(MIG), strip_tx(RB)
HOST = 'a0100000-0000-0000-0000-000000000001'      # owner of org_pj (so verify_payment is authorized)
GUEST = 'a0b00000-0000-0000-0000-00000000000b'     # pj.joiner
BID = 'd0000000-0000-0000-0000-00000000b230'
FAILS, PASSES = [], 0


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def call(status, payment_state, apply_rollback=False):
    claims = lit(json.dumps({'sub': HOST, 'role': 'authenticated'}))
    body = ('BEGIN;\n' + MIG + '\n' + (RB + '\n' if apply_rollback else '') +
            "INSERT INTO public.bookings (id, event_id, user_id, status, payment_state) VALUES ("
            f"'{BID}', 'pj_main', '{GUEST}', '{status}', '{payment_state}');\n"
            f"SET LOCAL request.jwt.claims = {claims};\n"
            "SET LOCAL ROLE authenticated;\n"
            f"SELECT public.verify_payment('{BID}')::text;\n"
            f"SELECT status::text || '/' || payment_state::text FROM public.bookings WHERE id = '{BID}';\n"
            "ROLLBACK;\n")
    r = subprocess.run(['docker', 'exec', '-i', 'g-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-At', '-q', '-v', 'ON_ERROR_STOP=1'],
                       input=body, capture_output=True, text=True)
    out = [l for l in (r.stdout or '').strip().split('\n') if l]
    return r.returncode, out, (r.stderr or '').strip()


def check(name, cond, detail=''):
    global PASSES
    if cond:
        PASSES += 1
    else:
        FAILS.append(name)
        print(f'  FAIL {name} {str(detail)[:300]}')


rc, out, err = call('expired', 'expired')
res = json.loads(out[0]) if rc == 0 and out else {}
check('an expired hold answers INVALID_STATE, not a trigger exception',
      rc == 0 and res.get('success') is False and res.get('error') == 'INVALID_STATE' and res.get('state') == 'expired',
      (rc, out, err))
check('an expired hold is left untouched', len(out) > 1 and out[1] == 'expired/expired', out)

rc, out, err = call('pending', 'expired')
res = json.loads(out[0]) if rc == 0 and out else {}
check('status pending but an expired payment_state is refused too',
      rc == 0 and res.get('error') == 'INVALID_STATE' and res.get('state') == 'expired', (rc, out, err))
check('nothing is written for that booking', len(out) > 1 and out[1] == 'pending/expired', out)

rc, out, err = call('pending', 'holding')
res = json.loads(out[0]) if rc == 0 and out else {}
check('a live hold still confirms', rc == 0 and res.get('success') is True and res.get('state') == 'confirmed', (rc, out, err))
check('a live hold is written to confirmed', len(out) > 1 and out[1] == 'confirmed/confirmed', out)

rc, out, err = call('expired', 'expired', apply_rollback=True)
check('rollback restores the old behaviour: the status trigger raises',
      rc != 0 and 'Invalid booking status transition from expired to confirmed' in err, (rc, out, err))

print(f'230: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
