#!/usr/bin/env python3
"""
Migration 222 against the THROWAWAY stack (g-db), on the 210 seed. Every check runs in its own rolled-back
transaction that first applies the migration (or the migration then its rollback), as a real `authenticated`
caller. Exit 0 only if every check holds. Touches nothing remote.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = open(os.path.join(ROOT, 'supabase/migrations/20261231000222_222_bookings_insert_lock.sql')).read()
RB = open(os.path.join(ROOT, 'supabase/rollbacks/20261231000222_222_revert_bookings_insert_lock.sql')).read()
# The migration/rollback files carry their own BEGIN/COMMIT; the harness supplies the transaction.
strip_tx = lambda sql: re.sub(r'(?m)^\s*(BEGIN|COMMIT);\s*$', '', sql)
MIG, RB = strip_tx(MIG), strip_tx(RB)
FAILS, PASSES = [], 0

A = 'a0100000-0000-0000-0000-000000000001'  # profile + organizer owner in the 210 seed
SETUP = """UPDATE public.events SET capacity = 40, price_vnd = 100000, visibility = 'public' WHERE id = 'pj_main';
DELETE FROM public.bookings WHERE event_id = 'pj_main';
CREATE SCHEMA t222;
CREATE FUNCTION t222.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r, 'ok'); EXCEPTION WHEN OTHERS THEN RETURN 'ERR:' || SQLERRM; END $$;
GRANT USAGE ON SCHEMA t222 TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION t222.try(text) TO authenticated, service_role;
"""


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(kind):
    if kind == 'postgres':
        return 'RESET ROLE;\n'
    if kind == 'service':
        return "RESET ROLE;\nSET LOCAL ROLE service_role;\n"
    return f"RESET ROLE;\nSELECT set_config('request.jwt.claims', {lit(json.dumps({'sub': A, 'role': 'authenticated'}))}, true);\nSET LOCAL ROLE authenticated;\n"


def tx(steps, apply_rollback=False):
    body = 'BEGIN;\n' + MIG + '\n' + (RB + '\n' if apply_rollback else '') + SETUP
    for i, (u, q) in enumerate(steps):
        body += as_user(u) + f"SELECT 'R|{i}|' || t222.try({lit(q)});\n"
    body += 'ROLLBACK;\n'
    r = subprocess.run(['docker', 'exec', '-i', 'g-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-At', '-q', '-v', 'ON_ERROR_STOP=1'],
                       input=body, capture_output=True, text=True)
    if r.returncode != 0:
        print('  sql error:', r.stderr.strip()[:600])
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


direct = ("INSERT INTO public.bookings (event_id, user_id, qty, total_vnd, status, payment_state, code) "
          "VALUES ('pj_main', auth.uid(), 1, 0, 'confirmed', 'confirmed', 'pwned-222') RETURNING 'ok'")

# --- with migration 222 applied ---
r = tx([
    ('auth', "SELECT has_table_privilege('authenticated', 'public.bookings', 'INSERT')::text"),
    ('auth', direct),
    ('auth', "SELECT (hold_seats('pj_main', 1)).qty::text"),
    ('service', "INSERT INTO public.bookings (event_id, user_id, qty, total_vnd, status, code) "
                "VALUES ('pj_main', '" + A + "', 1, 0, 'confirmed', 'svc-222') RETURNING 'ok'"),
])
check('authenticated no longer holds INSERT on bookings', r.get(0) in ('f', 'false'), r.get(0))
check('a direct client INSERT is refused', (r.get(1) or '').startswith('ERR:permission denied'), r.get(1))
check('hold_seats still creates a booking', r.get(2) == '1', r.get(2))
check('service_role can still write bookings', r.get(3) == 'ok', r.get(3))

# --- rollback restores the old hole (proves the migration is what closed it) ---
r = tx([('auth', direct)], apply_rollback=True)
check('rollback restores the direct INSERT', r.get(0) == 'ok', r.get(0))

print(f'222: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
