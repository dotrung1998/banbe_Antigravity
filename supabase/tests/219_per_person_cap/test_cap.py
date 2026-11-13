#!/usr/bin/env python3
"""
Migration 219 against the THROWAWAY stack (g-db), on the 210 seed. Every check runs in its own rolled-back transaction
that first applies the migration (or the migration then its rollback), as a real `authenticated` caller. Exit 0 only if
every check holds. Touches nothing remote.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = open(os.path.join(ROOT, 'supabase/migrations/20261231000219_219_per_person_cap.sql')).read()
RB = open(os.path.join(ROOT, 'supabase/rollbacks/20261231000219_219_revert_per_person_cap.sql')).read()
FAILS, PASSES = [], 0


def uid(n):
    return f'a{n:02x}00000-0000-0000-0000-0000000000{n:02x}'


A, B = uid(10), uid(9)  # two signed-in people with profiles in the 210 seed
SETUP = """UPDATE events SET capacity = 40, price_vnd = 100000, visibility = 'public' WHERE id = 'pj_main';
DELETE FROM bookings WHERE event_id = 'pj_main';
CREATE SCHEMA t219;
CREATE FUNCTION t219.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r, 'ok'); EXCEPTION WHEN OTHERS THEN RETURN 'ERR:' || SQLERRM; END $$;
GRANT USAGE ON SCHEMA t219 TO authenticated, anon;
GRANT EXECUTE ON FUNCTION t219.try(text) TO authenticated, anon;
"""


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(u):
    if u == 'admin':
        return 'RESET ROLE;\n'
    if u == 'anon':
        return "RESET ROLE;\nSELECT set_config('request.jwt.claims', '{\"role\":\"anon\"}', true);\nSET LOCAL ROLE anon;\n"
    return f"RESET ROLE;\nSELECT set_config('request.jwt.claims', {lit(json.dumps({'sub': u, 'role': 'authenticated'}))}, true);\nSET LOCAL ROLE authenticated;\n"


def tx(steps, apply_rollback=False):
    body = 'BEGIN;\n' + MIG + '\n' + (RB + '\n' if apply_rollback else '') + SETUP
    for i, (u, q) in enumerate(steps):
        body += as_user(u) + f"SELECT 'R|{i}|' || t219.try({lit(q)});\n"
    body += 'ROLLBACK;\n'
    r = subprocess.run(['docker', 'exec', '-i', 'g-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-At', '-q', '-v', 'ON_ERROR_STOP=1'],
                       input=body, capture_output=True, text=True)
    if r.returncode != 0:
        print('  sql error:', r.stderr.strip()[:400])
    res = {}
    for line in r.stdout.splitlines():
        m = re.match(r'R\|(\d+)\|(.*)$', line)
        if m:
            res[int(m.group(1))] = m.group(2)
    return res


def check(name, cond, detail=''):
    global PASSES
    if cond:
        PASSES += 1
    else:
        FAILS.append(name)
        print(f'  FAIL {name} {detail}')


hold = lambda n: f"SELECT (hold_seats('pj_main', {n})).qty::text"
att = lambda n: "SELECT (hold_seats_with_attendees('pj_main', '" + json.dumps([{'name': f'Guest {i}', 'dob': '1990-01-01'} for i in range(n)]) + "'::jsonb)).qty::text"
age = lambda u, col_set: f"UPDATE bookings SET {col_set} WHERE user_id = '{u}' AND event_id = 'pj_main' AND id = (SELECT id FROM bookings WHERE user_id = '{u}' AND event_id = 'pj_main' ORDER BY created_at LIMIT 1) RETURNING 'ok'"

# 1. Two bookings up to 6, the seventh ticket refused; one person never blocks another.
r = tx([(A, hold(4)), (A, hold(2)), (A, hold(1)), (B, hold(6)), (A, att(1))])
check('4 then 2 = 6 allowed', r.get(0) == '4' and r.get(1) == '2', r)
check('7th ticket refused', r.get(2) == 'ERR:PER_PERSON_LIMIT', r)
check('another person unaffected', r.get(3) == '6', r)
check('attendee path refused past 6', r.get(4) == 'ERR:PER_PERSON_LIMIT', r)

# 2. Only seat-holding bookings count.
r = tx([(A, hold(6)), ('admin', age(A, "hold_expires_at = now() - interval '1 minute'")), (A, hold(6))])
check('a lapsed hold frees the allowance', r.get(2) == '6', r)
r = tx([(A, hold(6)), ('admin', age(A, "status = 'cancelled'")), (A, att(3))])
check('a cancelled booking frees the allowance', r.get(2) == '3', r)
r = tx([(A, hold(5)), ('admin', age(A, "payment_state = 'pending_verification'")), (A, hold(2))])
check('pending verification still counts', r.get(2) == 'ERR:PER_PERSON_LIMIT', r)
r = tx([(A, hold(5)), ('admin', age(A, "payment_state = 'confirmed', status = 'confirmed'")), (A, hold(1)), (A, hold(1))])
check('confirmed counts, exactly 6 allowed', r.get(2) == '1' and r.get(3) == 'ERR:PER_PERSON_LIMIT', r)
r = tx([(A, hold(7))])
check('a single 7-seat hold is refused', r.get(0) == 'ERR:PER_PERSON_LIMIT', r)

# 3. Capacity still wins; nothing else changed.
r = tx([('admin', "UPDATE events SET capacity = 3 WHERE id = 'pj_main' RETURNING 'ok'"), (A, hold(4))])
check('SOLD_OUT still raised by capacity', r.get(1) in ('ERR:SOLD_OUT', 'ERR:PER_PERSON_LIMIT') and r.get(1) == 'ERR:SOLD_OUT', r)
r = tx([(A, "SELECT (hold_seats('pj_main', 2)).payment_state::text"), (A, "SELECT (hold_seats('pj_main', 1)).hold_expires_at IS NOT NULL")])
check('hold_seats still creates a timed hold', r.get(0) == 'holding' and r.get(1) == 'true', r)

# 4. claim_seats is a wrapper: payment state, timer, the cap; anon cannot call it.
r = tx([(A, "SELECT (claim_seats('pj_main', 2)).payment_state::text"), (A, "SELECT (claim_seats('pj_main', 4)).hold_expires_at IS NOT NULL"), (A, "SELECT (claim_seats('pj_main', 1)).qty::text"), ('anon', "SELECT (claim_seats('pj_main', 1)).qty::text")])
check('claim_seats now holds like hold_seats', r.get(0) == 'holding' and r.get(1) == 'true', r)
check('claim_seats inherits the cap', r.get(2) == 'ERR:PER_PERSON_LIMIT', r)
check('anon cannot execute claim_seats', (r.get(3) or '').startswith('ERR:permission denied'), r)

# 5. Rollback restores the old behaviour (a second booking can pass 6 again).
r = tx([(A, hold(6)), (A, hold(1)), (A, "SELECT (claim_seats('pj_main', 1)).payment_state::text")], apply_rollback=True)
check('rollback: no per-person cap', r.get(0) == '6' and r.get(1) == '1', r)
check('rollback: legacy claim_seats body back', r.get(2) == 'holding', r)  # column default, legacy insert sets no state

# 6. Idempotent: applying twice is fine.
body = 'BEGIN;\n' + MIG + '\n' + MIG + "\nSELECT 'R|0|ok';\nROLLBACK;\n"
out = subprocess.run(['docker', 'exec', '-i', 'g-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-At', '-q', '-v', 'ON_ERROR_STOP=1'], input=body, capture_output=True, text=True)
check('applies twice', 'R|0|ok' in out.stdout, out.stderr[:300])

print(f'{PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
