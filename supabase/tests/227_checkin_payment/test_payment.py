#!/usr/bin/env python3
"""
Migration 227 against the THROWAWAY stack (g-db), on the 210 seed. Every check runs in its own rolled-back
transaction that first applies the migration (or the migration then its rollback), as a real `authenticated`
caller. Exit 0 only if every check holds. Touches nothing remote.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = open(os.path.join(ROOT, 'supabase/migrations/20261231000227_227_checkin_requires_payment.sql')).read()
RB = open(os.path.join(ROOT, 'supabase/rollbacks/20261231000227_227_revert_checkin_requires_payment.sql')).read()
strip_tx = lambda sql: re.sub(r'(?m)^\s*(BEGIN|COMMIT);\s*$', '', sql)
MIG, RB = strip_tx(MIG), strip_tx(RB)
FAILS, PASSES = [], 0

OWNER = 'a0100000-0000-0000-0000-000000000001'  # org_pj owner in the 210 seed
GUEST = 'a0300000-0000-0000-0000-000000000003'
SETUP = """UPDATE public.events SET capacity = 40, price_vnd = 100000, visibility = 'public', status = 'live',
       approval = 'instant', starts_at = now() + interval '3 days' WHERE id = 'pj_main';
DELETE FROM public.check_ins WHERE booking_id IN (SELECT id FROM public.bookings WHERE event_id = 'pj_main');
DELETE FROM public.booking_attendees WHERE booking_id IN (SELECT id FROM public.bookings WHERE event_id = 'pj_main');
DELETE FROM public.bookings WHERE event_id = 'pj_main';
INSERT INTO public.bookings (id, event_id, user_id, qty, total_vnd, status, payment_state, code)
VALUES ('b2270000-0000-0000-0000-000000000001', 'pj_main', '%s', 1, 100000, 'confirmed', 'holding', 'pay227');
CREATE SCHEMA t227;
CREATE FUNCTION t227.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r, 'ok'); EXCEPTION WHEN OTHERS THEN RETURN 'ERR:' || SQLERRM; END $$;
GRANT USAGE ON SCHEMA t227 TO authenticated;
GRANT EXECUTE ON FUNCTION t227.try(text) TO authenticated;
""" % GUEST


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(kind):
    if kind == 'postgres':
        return 'RESET ROLE;\n'
    return f"RESET ROLE;\nSELECT set_config('request.jwt.claims', {lit(json.dumps({'sub': OWNER, 'role': 'authenticated'}))}, true);\nSET LOCAL ROLE authenticated;\n"


def tx(steps, apply_rollback=False):
    body = 'BEGIN;\n' + MIG + '\n' + (RB + '\n' if apply_rollback else '') + SETUP
    for i, (u, q) in enumerate(steps):
        body += as_user(u) + f"SELECT 'R|{i}|' || t227.try({lit(q)});\n"
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


checkin = "SELECT (check_in_guest('b2270000-0000-0000-0000-000000000001'))->>'success'"
paid = "UPDATE public.bookings SET payment_state = 'confirmed' WHERE id = 'b2270000-0000-0000-0000-000000000001' RETURNING 'ok'"

r = tx([
    ('auth', checkin),
    ('auth', "SELECT jsonb_array_length((get_event_checkin_names('pj_main'))->'guests')::text"),
    ('auth', "SELECT (project_checkin_lookup('b2270000-0000-0000-0000-000000000001'))->>'error'"),
    ('postgres', paid),
    ('auth', "SELECT jsonb_array_length((get_event_checkin_names('pj_main'))->'guests')::text"),
    ('auth', "SELECT (project_checkin_lookup('b2270000-0000-0000-0000-000000000001'))->>'success'"),
    ('auth', checkin),
])
check('an unpaid hold cannot be checked in', (r.get(0) or '').startswith('ERR:PAYMENT_NOT_CONFIRMED'), r.get(0))
check('the door list hides unpaid holds', r.get(1) == '0', r.get(1))
check('the scanner says NOT_ELIGIBLE for an unpaid hold', r.get(2) == 'NOT_ELIGIBLE', r.get(2))
check('the paid booking appears in the door list', r.get(4) == '1', r.get(4))
check('the scanner resolves the paid booking', r.get(5) == 'true', r.get(5))
check('a paid booking checks in', r.get(6) == 'true', r.get(6))

r = tx([('auth', checkin)], apply_rollback=True)
check('rollback admits the unpaid hold again (proves the fix)', r.get(0) == 'true', r.get(0))

print(f'227: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
