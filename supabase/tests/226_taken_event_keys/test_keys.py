#!/usr/bin/env python3
"""
Migration 226 against the THROWAWAY stack (g-db), on the 210 seed. Every check runs in its own rolled-back
transaction that first applies the migration (or the migration then its rollback), as a real `anon` / `authenticated`
caller. Exit 0 only if every check holds. Touches nothing remote.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = open(os.path.join(ROOT, 'supabase/migrations/20261231000226_226_taken_event_keys.sql')).read()
RB = open(os.path.join(ROOT, 'supabase/rollbacks/20261231000226_226_revert_taken_event_keys.sql')).read()
strip_tx = lambda sql: re.sub(r'(?m)^\s*(BEGIN|COMMIT);\s*$', '', sql)
MIG, RB = strip_tx(MIG), strip_tx(RB)
FAILS, PASSES = [], 0

A = 'a0100000-0000-0000-0000-000000000001'
SETUP = """SET LOCAL session_replication_role = replica;
INSERT INTO public.events (id, key, slug, organizer_id, name, status, visibility, event_date, event_time)
VALUES ('removed_probe', 'removed_probe', 'removed-probe', 'org_pj', 'Removed probe', 'removed', 'public', current_date, '19:00'),
       ('draft_probe', 'draft_probe', 'draft-probe', 'org_pj', 'Draft probe', 'draft', 'public', current_date, '19:00')
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status;
SET LOCAL session_replication_role = origin;
CREATE SCHEMA t226;
CREATE FUNCTION t226.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r, 'ok'); EXCEPTION WHEN OTHERS THEN RETURN 'ERR:' || SQLERRM; END $$;
GRANT USAGE ON SCHEMA t226 TO anon, authenticated;
GRANT EXECUTE ON FUNCTION t226.try(text) TO anon, authenticated;
"""


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(kind):
    if kind == 'postgres':
        return 'RESET ROLE;\n'
    role = 'anon' if kind == 'anon' else 'authenticated'
    claims = json.dumps({'role': role} if role == 'anon' else {'sub': A, 'role': role})
    return f"RESET ROLE;\nSELECT set_config('request.jwt.claims', {lit(claims)}, true);\nSET LOCAL ROLE {role};\n"


def tx(steps, apply_rollback=False):
    body = 'BEGIN;\n' + MIG + '\n' + (RB + '\n' if apply_rollback else '') + SETUP
    for i, (u, q) in enumerate(steps):
        body += as_user(u) + f"SELECT 'R|{i}|' || t226.try({lit(q)});\n"
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


has = lambda key: (f"SELECT count(*) FROM public.get_taken_event_keys() "
                   f"WHERE event_id = '{key}' OR event_key = '{key}' OR event_slug = '{key}'")

r = tx([
    ('anon', has('removed_probe')),
    ('anon', has('draft_probe')),
    ('anon', has('pj_main')),
    ('auth', has('removed_probe')),
    ('auth', "SELECT count(*) FROM public.get_taken_event_keys()"),
    ('anon', "SELECT count(*) FROM public.events WHERE id = 'removed_probe'"),
])
check('anon sees the removed event key (the client cannot)', r.get(0) == '1', r.get(0))
check('a draft event is not exposed', r.get(1) == '0', r.get(1))
check('a live event key is listed', r.get(2) == '1', r.get(2))
check('a signed-in caller sees it too', r.get(3) == '1', r.get(3))
check('the list is small and key-shaped only', (r.get(4) or '').isdigit() and int(r.get(4)) > 0, r.get(4))
check('anon cannot read the removed row itself', r.get(5) == '0', r.get(5))

r = tx([('auth', has('removed_probe'))], apply_rollback=True)
check('rollback removes the RPC', (r.get(0) or '').startswith('ERR:'), r.get(0))

print(f'226: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
