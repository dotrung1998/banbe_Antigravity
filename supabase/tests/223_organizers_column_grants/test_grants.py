#!/usr/bin/env python3
"""
Migration 223 against the THROWAWAY stack (g-db), on the 210 seed. Every check runs in its own rolled-back
transaction that first applies the migration (or the migration then its rollback), as a real `authenticated`
caller. Exit 0 only if every check holds. Touches nothing remote.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = open(os.path.join(ROOT, 'supabase/migrations/20261231000223_223_organizers_private_columns.sql')).read()
RB = open(os.path.join(ROOT, 'supabase/rollbacks/20261231000223_223_revert_organizers_column_grants.sql')).read()
strip_tx = lambda sql: re.sub(r'(?m)^\s*(BEGIN|COMMIT);\s*$', '', sql)
MIG, RB = strip_tx(MIG), strip_tx(RB)
FAILS, PASSES = [], 0

OWNER = 'a0100000-0000-0000-0000-000000000001'   # org_pj owner_id
GUEST = 'a0300000-0000-0000-0000-000000000003'   # no link to org_pj, no booking yet
ADMIN = 'a0b00000-0000-0000-0000-00000000000b'   # made an admin by SETUP
SETUP = """UPDATE public.events SET capacity = 40, price_vnd = 100000, visibility = 'public' WHERE id = 'pj_main';
UPDATE public.organizers SET bank_name = 'VCB', bank_account_name = 'PJ Kitchen',
       bank_account_no = '0071000123456', momo_phone = '0911222333', pay_note = 'memo me'
 WHERE id = 'org_pj';
DELETE FROM public.bookings WHERE event_id = 'pj_main';
UPDATE public.profiles SET role = 'admin' WHERE id = '%s';
CREATE SCHEMA t223;
CREATE FUNCTION t223.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r, 'ok'); EXCEPTION WHEN OTHERS THEN RETURN 'ERR:' || SQLERRM; END $$;
GRANT USAGE ON SCHEMA t223 TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION t223.try(text) TO authenticated, service_role;
""" % ADMIN


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(kind):
    if kind == 'postgres':
        return 'RESET ROLE;\n'
    uid = {'auth': GUEST, 'owner': OWNER, 'admin': ADMIN}[kind]
    return f"RESET ROLE;\nSELECT set_config('request.jwt.claims', {lit(json.dumps({'sub': uid, 'role': 'authenticated'}))}, true);\nSET LOCAL ROLE authenticated;\n"


def tx(steps, apply_rollback=False):
    body = 'BEGIN;\n' + MIG + '\n' + (RB + '\n' if apply_rollback else '') + SETUP
    for i, (u, q) in enumerate(steps):
        body += as_user(u) + f"SELECT 'R|{i}|' || t223.try({lit(q)});\n"
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


bank = "SELECT bank_account_no FROM public.organizers WHERE id = 'org_pj'"
public = "SELECT name || '|' || coalesce(owner_id::text, '') FROM public.organizers WHERE id = 'org_pj'"
payouts = "SELECT count(*) FROM public.organizer_payouts WHERE id = 'org_pj'"

# --- with migration 223 applied ---
r = tx([
    ('auth', bank),
    ('auth', public),
    ('auth', payouts),
    ('owner', payouts),
    ('admin', payouts),
    ('auth', "SELECT (hold_seats('pj_main', 1)).qty::text"),
    ('auth', payouts),
    ('auth', "SELECT bank_account_no FROM public.organizer_payouts WHERE id = 'org_pj'"),
])
check('a signed-in non-host cannot select bank columns', (r.get(0) or '').startswith('ERR:permission denied'), r.get(0))
check('public columns (name, owner_id) still read', (r.get(1) or '').startswith('PJ Kitchen|' + OWNER), r.get(1))
check('no payout row for a non-host without a booking', r.get(2) == '0', r.get(2))
check('the host sees its own payout row', r.get(3) == '1', r.get(3))
check('a platform admin sees the payout row', r.get(4) == '1', r.get(4))
check('hold_seats still works', r.get(5) == '1', r.get(5))
check('a guest with a booking sees the payout row', r.get(6) == '1', r.get(6))
check('the guest reads the bank account from the view', r.get(7) == '0071000123456', r.get(7))

# --- rollback restores table-wide SELECT (proves the migration is what closed it) ---
r = tx([('auth', bank)], apply_rollback=True)
check('rollback restores table-wide SELECT', r.get(0) == '0071000123456', r.get(0))

print(f'223: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
