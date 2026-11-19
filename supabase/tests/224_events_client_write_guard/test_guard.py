#!/usr/bin/env python3
"""
Migration 224 against the THROWAWAY stack (g-db), on the 210 seed. Every check runs in its own rolled-back
transaction that first applies the migration (or the migration then its rollback), as a real `authenticated`
caller. Exit 0 only if every check holds. Touches nothing remote.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = open(os.path.join(ROOT, 'supabase/migrations/20261231000224_224_events_client_write_guard.sql')).read()
RB = open(os.path.join(ROOT, 'supabase/rollbacks/20261231000224_224_revert_events_client_write_guard.sql')).read()
strip_tx = lambda sql: re.sub(r'(?m)^\s*(BEGIN|COMMIT);\s*$', '', sql)
MIG, RB = strip_tx(MIG), strip_tx(RB)
FAILS, PASSES = [], 0

OWNER = 'a0100000-0000-0000-0000-000000000001'   # org_pj owner, hosts pj_main / pj_new
ADMIN = 'a0b00000-0000-0000-0000-00000000000b'   # made an admin by SETUP
SETUP = """UPDATE public.profiles SET role = 'admin' WHERE id = '%s';
UPDATE public.events SET status = 'live', price_vnd = 100000, capacity = 40, visibility = 'public' WHERE id IN ('pj_main', 'pj_new');
DELETE FROM public.bookings WHERE event_id IN ('pj_main', 'pj_new');
INSERT INTO public.bookings (event_id, user_id, qty, total_vnd, status, payment_state, code)
VALUES ('pj_main', 'a0200000-0000-0000-0000-000000000002', 2, 200000, 'confirmed', 'confirmed', 'guard-224');
CREATE SCHEMA t224;
CREATE FUNCTION t224.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r, 'ok'); EXCEPTION WHEN OTHERS THEN RETURN 'ERR:' || SQLERRM; END $$;
GRANT USAGE ON SCHEMA t224 TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION t224.try(text) TO authenticated, service_role;
""" % ADMIN


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(kind):
    if kind == 'postgres':
        return 'RESET ROLE;\n'
    uid = {'host': OWNER, 'admin': ADMIN}[kind]
    return f"RESET ROLE;\nSELECT set_config('request.jwt.claims', {lit(json.dumps({'sub': uid, 'role': 'authenticated'}))}, true);\nSET LOCAL ROLE authenticated;\n"


def tx(steps, apply_rollback=False):
    body = 'BEGIN;\n' + MIG + '\n' + (RB + '\n' if apply_rollback else '') + SETUP
    for i, (u, q) in enumerate(steps):
        body += as_user(u) + f"SELECT 'R|{i}|' || t224.try({lit(q)});\n"
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


upd = lambda ev, set_sql: f"UPDATE public.events SET {set_sql} WHERE id = '{ev}' RETURNING 'ok'"
ins = lambda status: ("INSERT INTO public.events (id, organizer_id, name, status, event_date, event_time) "
                      f"VALUES ('guard_new_{status}', 'org_pj', 'Guard', '{status}', current_date + 30, '19:00') RETURNING 'ok'")

r = tx([
    ('host', upd('pj_main', "status = 'ended'")),
    ('host', upd('pj_main', "status = 'review'")),
    ('host', upd('pj_main', 'price_vnd = 1')),
    ('host', upd('pj_main', 'capacity = 1')),
    ('host', upd('pj_main', 'visibility = \'invite\'')),
    ('host', upd('pj_new', 'price_vnd = 1')),
    ('host', upd('pj_main', "chat_greeting = 'hello'")),
    ('host', ins('live')),
    ('host', ins('review')),
    ('admin', upd('pj_main', "status = 'ended'")),
    ('host', "SELECT cancel_event('pj_new', 'guard test')::text"),
    ('host', "SELECT status::text FROM public.events WHERE id = 'pj_new'"),
])
check('a host cannot flip status directly', (r.get(0) or '').startswith('ERR:EVENT_STATUS_GUARDED'), r.get(0))
check('a host cannot re-set status directly', (r.get(1) or '').startswith('ERR:EVENT_STATUS_GUARDED'), r.get(1))
check('price cannot change once a booking exists', (r.get(2) or '').startswith('ERR:EVENT_TERMS_LOCKED_AFTER_BOOKING'), r.get(2))
check('capacity cannot change once a booking exists', (r.get(3) or '').startswith('ERR:EVENT_TERMS_LOCKED_AFTER_BOOKING'), r.get(3))
check('visibility cannot change once a booking exists', (r.get(4) or '').startswith('ERR:EVENT_TERMS_LOCKED_AFTER_BOOKING'), r.get(4))
check('price is still editable before any booking', r.get(5) == 'ok', r.get(5))
check('ordinary direct edits still work', r.get(6) == 'ok', r.get(6))
check('an event cannot be inserted straight to live', (r.get(7) or '').startswith('ERR:EVENT_STATUS_REVIEW_REQUIRED'), r.get(7))
check('an event can still be inserted into review', r.get(8) == 'ok', r.get(8))
check('a platform admin is exempt', r.get(9) == 'ok', r.get(9))
check('cancel_event (SECURITY DEFINER) is not blocked', not (r.get(10) or '').startswith('ERR:'), r.get(10))
check('cancel_event still moves the event to cancelled', r.get(11) == 'cancelled', r.get(11))

r = tx([('host', upd('pj_main', "status = 'ended'"))], apply_rollback=True)
check('rollback restores the direct status write', r.get(0) == 'ok', r.get(0))

print(f'224: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
