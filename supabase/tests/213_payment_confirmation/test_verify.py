#!/usr/bin/env python3
"""
Migration 213 against the THROWAWAY stack (g-db), on the 210 seed. Each check runs in its own rolled-back transaction as a
real `authenticated` caller. Touches nothing remote. Exit 0 only if every check holds.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = os.path.join(ROOT, 'supabase/migrations/20261231000213_213_remove_auto_payment_confirmation.sql')
ROLLBACK = os.path.join(ROOT, 'supabase/rollbacks/20261231000213_213_revert_remove_auto_confirmation.sql')
FAILS, PASSES = [], 0


def check(name, cond, detail=''):
    global PASSES
    if cond:
        PASSES += 1
    else:
        FAILS.append(name)
        print(f'  FAIL {name} {detail}')


def uid(n):
    return f'a{n:02x}00000-0000-0000-0000-0000000000{n:02x}'


OWNER, SECOND, MGR, FIN, LEAD, HELP, HM, HC, RF, OUT = (uid(i) for i in range(1, 11))
B = '7f000000-0000-0000-0000-000000000001'
SEED = f"""INSERT INTO bookings (id, event_id, user_id, qty, total_vnd, status, payment_state)
VALUES ('{B}', 'pj_main', '{HELP}', 1, 490000, 'pending', 'pending_verification');\n"""


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(u):
    if u == 'admin':
        return 'RESET ROLE;\n'
    return f"SELECT set_config('request.jwt.claims', {lit(json.dumps({'sub': u, 'role': 'authenticated'}))}, true);\nSET LOCAL ROLE authenticated;\n"


def tx(steps, setup=''):
    body = 'BEGIN;\n' + SEED + setup
    for i, (u, expr) in enumerate(steps):
        body += as_user(u) + f"SELECT 'R|{i}|' || coalesce(({expr})::text, 'NULL');\n"
    body += 'ROLLBACK;\n'
    r = subprocess.run(['docker', 'exec', '-i', 'g-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-At', '-q', '-v', 'ON_ERROR_STOP=0'],
                       input=body, capture_output=True, text=True)
    res = {}
    for line in r.stdout.splitlines():
        m = re.match(r'R\|(\d+)\|(.*)$', line)
        if m:
            res[int(m.group(1))] = m.group(2)
    if 'ERROR' in r.stderr:
        print('  sql error:', r.stderr.strip()[:300])
    return res


def j(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


V = "public.verify_payment('" + B + "', 'x', '{kind}', '{{}}')::text"
STATE = f"(SELECT payment_state::text || '/' || status::text FROM bookings WHERE id = '{B}')"
BY = f"(SELECT verified_by::text FROM bookings WHERE id = '{B}')"

print('213: the hole is closed')
for kind in ('webhook', 'system', 'organizer', 'admin'):
    r = tx([(OUT, V.format(kind=kind)), ('admin', STATE)])
    check(f'a stranger claiming "{kind}" is refused', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
    check(f'and the booking stays unpaid ("{kind}")', r.get(1) == 'pending_verification/pending', r.get(1))
for who, name in [(FIN, 'a project Finance member'), (MGR, 'a project Manager'), (HELP, 'the guest themself')]:
    r = tx([(who, V.format(kind='webhook'))])
    check(f'{name} cannot confirm either', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
r = tx([('admin', "has_function_privilege('anon', 'public.verify_payment(uuid,text,text,jsonb)', 'EXECUTE')")])
check('anon cannot call verify_payment at all', r.get(0) == 'false', r.get(0))

print('213: the people who should still can')
r = tx([(OWNER, V.format(kind='organizer')), ('admin', STATE), ('admin', BY)])
check('the owner confirms', j(r.get(0)).get('state') == 'confirmed', r.get(0))
check('the booking is confirmed', r.get(1) == 'confirmed/confirmed', r.get(1))
check('and records who did it', r.get(2) == OWNER, r.get(2))
r = tx([(SECOND, V.format(kind='organizer'))])
check('the second organizer account confirms', j(r.get(0)).get('success') is True, r.get(0))
r = tx([(OUT, V.format(kind='organizer'))], f"UPDATE profiles SET role = 'admin' WHERE id = '{OUT}';")
check('an admin confirms', j(r.get(0)).get('success') is True, r.get(0))
r = tx([(OWNER, V.format(kind='webhook')), ('admin', BY),
        ('admin', f"(SELECT actor_kind FROM payment_audit_log WHERE booking_id = '{B}' ORDER BY id DESC LIMIT 1)")])
check('an old client sending "webhook" as the owner still works', j(r.get(0)).get('success') is True, r.get(0))
check('but is recorded as the owner, never as an anonymous webhook', r.get(1) == OWNER, r.get(1))
check('and logged as organizer', r.get(2) == 'organizer', r.get(2))
r = tx([(OWNER, V.format(kind='organizer')), (OWNER, V.format(kind='organizer'))])
check('confirming twice is a no-op', j(r.get(1)).get('noop') is True, r.get(1))
r = tx([(OUT, f"public.confirm_payment('{B}', 'momo')::text")])
check('confirm_payment (060) still refuses strangers', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))

print('213: Telegram confirmation is gone, the bank feed stays')
r = tx([('admin', "(SELECT count(*) FROM pg_proc WHERE proname IN ('verify_payment_from_bot', 'save_organizer_alert_routing'))"),
        ('admin', "to_regclass('public.v_alert_queue')::text"),
        ('admin', "(SELECT count(*) FROM cron.job WHERE jobname = 'bb_sweep_verification_slas')"),
        ('admin', "to_regclass('public.payment_webhook_events')::text || ',' || to_regclass('public.alert_outbox')::text")])
check('the Telegram and routing functions are dropped', r.get(0) == '0', r.get(0))
r2 = tx([('admin', "has_function_privilege('authenticated', 'public.record_bank_transaction(text,text,bigint,text,jsonb,boolean)', 'EXECUTE')::text || ',' || has_function_privilege('service_role', 'public.record_bank_transaction(text,text,bigint,text,jsonb,boolean)', 'EXECUTE')::text")])
check('the Casso/PayOS bank feed is kept, service role only', r2.get(0) == 'false,true', r2.get(0))
check('the alert queue view is dropped', r.get(1) == 'NULL', r.get(1))
check('the Telegram reminder sweep is unscheduled', r.get(2) == '0', r.get(2))
check('history tables are kept', r.get(3) == 'payment_webhook_events,alert_outbox', r.get(3))
code = open(MIG).read()
body = code[code.index('CREATE OR REPLACE FUNCTION public.verify_payment('):code.index('$$;', code.index('CREATE OR REPLACE FUNCTION public.verify_payment('))]
check("verify_payment skips its check only for the bank feed with the service-role key",
      "v_bank := p_actor_kind = 'webhook' AND coalesce(auth.role(), '') = 'service_role';" in body and "IN ('webhook', 'system') THEN\n" not in body)
SR = "SELECT set_config('request.jwt.claims', '{\"role\": \"service_role\"}', true);\nSET LOCAL ROLE service_role;\n"
r = tx([('admin', "!" + SR + "SELECT 1"), ('admin', "(public.verify_payment('" + B + "', 'webhook', 'webhook', '{}'))::text")])
check('the bank feed (service role, webhook) still confirms', j(r.get(1)).get('success') is True, r.get(1))

print('213: re-apply and rollback')
r = tx([(OUT, V.format(kind='webhook')), (OWNER, V.format(kind='organizer'))], code + '\n' + code)
check('re-apply: idempotent, still closed and still working', j(r.get(0)).get('error') == 'NOT_AUTHORIZED' and j(r.get(1)).get('success') is True, r)
r = tx([(OUT, V.format(kind='webhook')),
        ('admin', "(SELECT count(*) FROM pg_proc WHERE proname IN ('verify_payment_from_bot', 'record_bank_transaction', 'save_organizer_alert_routing'))"),
        ('admin', "(SELECT count(*) FROM cron.job WHERE jobname = 'bb_sweep_verification_slas')")], open(ROLLBACK).read())
check('rollback restores 026 exactly (the hole comes back, which is why it is emergency-only)', j(r.get(0)).get('success') is True, r.get(0))
check('rollback recreates the three functions', r.get(1) == '3', r.get(1))
check('rollback re-schedules the sweep', r.get(2) == '1', r.get(2))

print(f'213: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
