#!/usr/bin/env python3
"""
Migration 225 against the THROWAWAY stack (g-db), on the 210 seed. Every check runs in its own rolled-back
transaction that first applies the migration (or the migration then its rollback), as a real `authenticated`
caller. Exit 0 only if every check holds. Touches nothing remote.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = open(os.path.join(ROOT, 'supabase/migrations/20261231000225_225_no_booking_after_event_ends.sql')).read()
RB = open(os.path.join(ROOT, 'supabase/rollbacks/20261231000225_225_revert_no_booking_after_event_ends.sql')).read()
strip_tx = lambda sql: re.sub(r'(?m)^\s*(BEGIN|COMMIT);\s*$', '', sql)
MIG, RB = strip_tx(MIG), strip_tx(RB)
FAILS, PASSES = [], 0

A = 'a0100000-0000-0000-0000-000000000001'  # profile + organizer owner in the 210 seed
SETUP = """UPDATE public.profiles SET role = 'goer' WHERE id = '%s';
UPDATE public.events SET capacity = 40, price_vnd = 100000, visibility = 'public', status = 'live',
       tz = 'Asia/Ho_Chi_Minh', end_open = false WHERE id IN ('pj_main', 'pj_new', 'pj_past');
-- pj_main: 19:00-21:00 on 2026-01-01 (ICT), long over.
UPDATE public.events SET starts_at = '2026-01-01 19:00+07', event_date = '2026-01-01', event_time = '19:00',
       end_time = '21:00' WHERE id = 'pj_main';
-- pj_new: a future event, still open.
UPDATE public.events SET starts_at = now() + interval '3 days', event_date = (now() + interval '3 days')::date,
       event_time = '19:00', end_time = '23:00' WHERE id = 'pj_new';
-- pj_past: over via an open end 13h after the start.
UPDATE public.events SET starts_at = now() - interval '13 hours', end_time = NULL, end_open = true WHERE id = 'pj_past';
DELETE FROM public.bookings WHERE event_id IN ('pj_main', 'pj_new', 'pj_past');
INSERT INTO public.events (id, organizer_id, name, status, event_date, event_time, starts_at, tz, end_time, end_open, capacity, price_vnd, visibility)
VALUES ('pj_open_recent', 'org_pj', 'PJ Open Recent', 'live', (now() - interval '1 hour')::date, '19:00',
        now() - interval '1 hour', 'Asia/Ho_Chi_Minh', NULL, true, 40, 100000, 'public')
ON CONFLICT (id) DO UPDATE SET starts_at = now() - interval '1 hour', end_open = true, end_time = NULL, status = 'live';
CREATE SCHEMA t225;
CREATE FUNCTION t225.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r, 'ok'); EXCEPTION WHEN OTHERS THEN RETURN 'ERR:' || SQLERRM; END $$;
GRANT USAGE ON SCHEMA t225 TO authenticated;
GRANT EXECUTE ON FUNCTION t225.try(text) TO authenticated;
""" % A


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(kind):
    if kind == 'postgres':
        return 'RESET ROLE;\n'
    return f"RESET ROLE;\nSELECT set_config('request.jwt.claims', {lit(json.dumps({'sub': A, 'role': 'authenticated'}))}, true);\nSET LOCAL ROLE authenticated;\n"


def tx(steps, apply_rollback=False):
    body = 'BEGIN;\n' + MIG + '\n' + (RB + '\n' if apply_rollback else '') + SETUP
    for i, (u, q) in enumerate(steps):
        body += as_user(u) + f"SELECT 'R|{i}|' || t225.try({lit(q)});\n"
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


hold = lambda ev: f"SELECT (hold_seats('{ev}', 1)).qty::text"
direct = ("INSERT INTO public.bookings (event_id, user_id, qty, total_vnd, status, code) "
          f"VALUES ('pj_main', '{A}', 1, 0, 'confirmed', 'ended-225') RETURNING 'ok'")

r = tx([
    ('auth', hold('pj_main')),
    ('auth', hold('pj_new')),
    ('auth', hold('pj_past')),
    ('auth', hold('pj_open_recent')),
    ('auth', direct),
    ('auth', "SELECT public.event_ends_at('2026-01-01 19:00+07'::timestamptz, '21:00'::time, false, 'Asia/Ho_Chi_Minh')::text"),
    ('auth', "SELECT public.event_ends_at('2026-01-01 22:00+07'::timestamptz, '02:00'::time, false, 'Asia/Ho_Chi_Minh')::text"),
    ('auth', "SELECT public.event_ends_at('2026-01-01 19:00+07'::timestamptz, NULL, true, 'Asia/Ho_Chi_Minh')::text"),
])
check('an event past its end time refuses the hold', (r.get(0) or '').startswith('ERR:EVENT_ENDED'), r.get(0))
check('a future event still holds', r.get(1) == '1', r.get(1))
check('an open-ended event 13h past its start refuses the hold', (r.get(2) or '').startswith('ERR:EVENT_ENDED'), r.get(2))
check('an open-ended event 1h in is still holdable', r.get(3) == '1', r.get(3))
check('a direct INSERT for an ended event is refused too', (r.get(4) or '').startswith('ERR:EVENT_ENDED'), r.get(4))
check('end of a same-day range', (r.get(5) or '').startswith('2026-01-01 14:00:00'), r.get(5))
check('end past midnight is the next venue day', (r.get(6) or '').startswith('2026-01-01 19:00:00'), r.get(6))
check('no end stated is start + 12h', (r.get(7) or '').startswith('2026-01-02 00:00:00'), r.get(7))

r = tx([('auth', hold('pj_main'))], apply_rollback=True)
check('rollback restores the hold', r.get(0) == '1', r.get(0))

print(f'225: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
